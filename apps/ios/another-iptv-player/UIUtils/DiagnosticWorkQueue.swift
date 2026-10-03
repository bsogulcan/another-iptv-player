import Foundation

/// At most one scheduled drain, with bounded retained work even if producers outrun IO.
nonisolated final class DiagnosticWorkQueue: @unchecked Sendable {
    private struct Job {
        let bytes: Int
        let run: @Sendable () -> Void
    }
    let queue: DispatchQueue
    private let key = DispatchSpecificKey<Bool>()
    private let lock = NSLock()
    private var jobs: [Job] = []
    private var bytes = 0
    private var scheduled = false
    private var dropped = 0
    private var droppedTotal = 0
    private let countLimit: Int
    private let byteLimit: Int
    private let onDrop: @Sendable (Int) -> Void

    init(label: String, countLimit: Int = 512, byteLimit: Int = 1024 * 1024,
         onDrop: @escaping @Sendable (Int) -> Void = { _ in }) {
        queue = DispatchQueue(label: label, qos: .utility)
        self.countLimit = countLimit
        self.byteLimit = byteLimit
        self.onDrop = onDrop
        queue.setSpecific(key: key, value: true)
    }

    @discardableResult
    func submit(bytes cost: Int, _ run: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        let accepted = cost <= byteLimit && jobs.count < countLimit && bytes + cost <= byteLimit
        if accepted {
            jobs.append(Job(bytes: cost, run: run))
            bytes += cost
        } else { dropped += 1; droppedTotal += 1 }
        if !scheduled {
            scheduled = true
            queue.async { [self] in drain() }
        }
        lock.unlock()
        return accepted
    }

    var skippedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return droppedTotal
    }

    private func drain() {
        runBatch()
        lock.lock()
        if jobs.isEmpty && dropped == 0 { scheduled = false }
        else { queue.async { [self] in drain() } }
        lock.unlock()
    }

    private func runBatch() {
        lock.lock()
        let batch = jobs
        let skipped = dropped
        jobs = []
        bytes = 0
        dropped = 0
        // Leave scheduled set while processing: producers cannot enqueue extra drains.
        lock.unlock()
        for job in batch { job.run() }
        if skipped > 0 { onDrop(skipped) }
    }

    /// Only diagnostic reads/background lifecycle flushing wait for work, never producers.
    func sync<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: key) == true { return body() }
        return queue.sync {
            // Include work submitted while the previous drain was running.
            // A queued empty drain is harmless; each job is removed under the lock once.
            runBatch()
            return body()
        }
    }

    func flush() { sync {} }
}
