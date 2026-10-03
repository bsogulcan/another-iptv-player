import Foundation

/// Bounded input, batched writes and a reusable file handle. All sanitizing/IO is off the caller.
nonisolated final class DiagnosticArchive: @unchecked Sendable {
    static let shared = DiagnosticArchive(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics", isDirectory: true))
    private let worker: DiagnosticWorkQueue
    private let directory: URL
    private let fileLimit: Int
    private let fileCount: Int
    private let lifetime: TimeInterval
    private let flushInterval: TimeInterval
    private var failure: String?
    private var buffer = Data()
    private var handle: FileHandle?
    private var fileSize = 0
    private var prepared = false
    private var nextMaintenance = Date.distantPast
    private var flushScheduled = false
    // Counters are read through the worker, used by performance regression tests.
    private var writes = 0
    private var opens = 0

    init(directory: URL, fileLimit: Int = 512 * 1024, fileCount: Int = 3,
         lifetime: TimeInterval = 7 * 86400, flushInterval: TimeInterval = 0.25) {
        self.directory = directory
        self.fileLimit = max(1024, fileLimit)
        self.fileCount = max(1, fileCount)
        self.lifetime = lifetime
        self.flushInterval = flushInterval
        worker = DiagnosticWorkQueue(label: "app.diagnostics.archive", countLimit: 4096, byteLimit: 2 * 1024 * 1024)
    }

    deinit { try? handle?.close() }
    private func url(_ index: Int) -> URL { directory.appendingPathComponent("events-\(index).log") }

    func append(_ text: String) {
        // Swift strings are retained copy-on-write; this does not sanitize or format on the caller.
        worker.submit(bytes: text.utf8.count) { [self] in
            let safe = SupportReport.sanitized(text)
            var record = Data(safe.utf8)
            if record.count > fileLimit / 2 {
                record = Data(String(decoding: record.prefix(fileLimit / 2), as: UTF8.self).utf8)
                record.append(Data("\n[record truncated]".utf8))
            }
            record.append(10)
            if buffer.count + record.count > min(32 * 1024, fileLimit) { flushBuffer() }
            buffer.append(record)
            if !flushScheduled {
                flushScheduled = true
                worker.queue.asyncAfter(deadline: .now() + flushInterval) { [weak self] in
                    guard let self else { return }
                    self.flushScheduled = false
                    self.flushBuffer()
                }
            }
        }
    }

    /// On a background thread. Flush all upstream work before taking the report snapshot.
    func snapshot() -> String {
        if self === Self.shared {
            APIDiagnostics.flush()
            Log.flush()
        }
        return worker.sync {
            flushBuffer()
            do { try maintain(force: true) } catch { failure = "Diagnostic archive cleanup failed" }
            let text = (0..<fileCount).reversed().compactMap { try? String(contentsOf: url($0), encoding: .utf8) }.joined(separator: "\n")
            let skipped = worker.skippedCount
            let overflow = skipped > 0 ? "[Diagnostics: \(skipped) archive records skipped during overload]" : nil
            return [text, failure, overflow].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    func flush() { worker.sync { flushBuffer() } }
    func ioCounts() -> (writes: Int, opens: Int) { worker.sync { (writes, opens) } }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        defer { buffer.removeAll(keepingCapacity: true) }
        do {
            try prepare()
            try maintain()
            if fileSize + buffer.count > fileLimit {
                try handle?.close()
                handle = nil
                for index in stride(from: fileCount - 1, through: 0, by: -1) {
                    let source = url(index)
                    guard FileManager.default.fileExists(atPath: source.path) else { continue }
                    if index == fileCount - 1 { try FileManager.default.removeItem(at: source) }
                    else { try FileManager.default.moveItem(at: source, to: url(index + 1)) }
                }
                fileSize = 0
            }
            if handle == nil {
                if !FileManager.default.fileExists(atPath: url(0).path) {
                    try Data().write(to: url(0), options: .completeFileProtectionUntilFirstUserAuthentication)
                }
                handle = try FileHandle(forWritingTo: url(0))
                try handle?.seekToEnd()
                opens += 1
            }
            try handle?.write(contentsOf: buffer)
            fileSize += buffer.count
            writes += 1
            failure = nil
        } catch {
            try? handle?.close()
            handle = nil
            prepared = false
            failure = "Diagnostic archive unavailable: \(error.localizedDescription)"
        }
    }

    private func prepare() throws {
        guard !prepared else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = directory
        try folder.setResourceValues(values)
        fileSize = (try? url(0).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        prepared = true
    }

    private func maintain(force: Bool = false) throws {
        guard force || Date() >= nextMaintenance else { return }
        nextMaintenance = Date().addingTimeInterval(60)
        for index in 0..<fileCount {
            let file = url(index)
            guard let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
                  let date = [values.creationDate, values.contentModificationDate].compactMap({ $0 }).min() else { continue }
            if Date().timeIntervalSince(date) > lifetime {
                if index == 0 {
                    try handle?.close()
                    handle = nil
                    fileSize = 0
                }
                try FileManager.default.removeItem(at: file)
            }
        }
    }
}
