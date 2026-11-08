import Foundation
import Network

// MARK: - Mock panel

/// Test-only stand-in for an IPTV panel: an HTTP server on 127.0.0.1 that serves one
/// MPEG-TS stream at the pace of the stream's own clock and admits one connection at
/// a time, like a single-connection account. It can go quiet or drop the connection
/// on command, which is how most cast start failures look from the phone.
///
/// Everything runs on one serial queue; the counters are read from the test through
/// a lock. No receiver is involved: this covers the phone side of the cast pipeline
/// (source connection, remux, local playlist), not AirPlay itself.
nonisolated final class MockPanelServer: @unchecked Sendable {
    /// An MPEG-TS byte stream and, for each 188-byte packet, the stream time at
    /// which a real-time source would have sent it (taken from the PCR).
    nonisolated struct Stream: Sendable {
        static let packetSize = 188

        let data: Data
        /// Seconds since the first PCR, per packet, never decreasing.
        let packetDueSeconds: [Double]

        var durationSeconds: Double { packetDueSeconds.last ?? 0 }

        init(transportStream: Data) {
            let bytes = [UInt8](transportStream)
            let count = bytes.count / Self.packetSize
            var due = [Double](repeating: 0, count: count)
            var firstPCR: Double?
            var clock = 0.0
            for index in 0..<count {
                let base = index * Self.packetSize
                // Sync byte, adaptation field present and long enough, PCR flag set.
                if bytes[base] == 0x47, bytes[base + 3] & 0x20 != 0,
                   bytes[base + 4] >= 7, bytes[base + 5] & 0x10 != 0
                {
                    let pcrBase = UInt64(bytes[base + 6]) << 25
                        | UInt64(bytes[base + 7]) << 17
                        | UInt64(bytes[base + 8]) << 9
                        | UInt64(bytes[base + 9]) << 1
                        | UInt64(bytes[base + 10]) >> 7
                    let seconds = Double(pcrBase) / 90_000
                    let first = firstPCR ?? seconds
                    firstPCR = first
                    // Packets ahead of the first PCR (PAT / PMT) are due at once;
                    // the clock never runs backward.
                    clock = max(clock, seconds - first)
                }
                due[index] = clock
            }
            data = Data(bytes[0..<(count * Self.packetSize)])
            packetDueSeconds = due
        }

        /// Bytes (whole packets) a real-time source has sent `seconds` into the stream.
        func byteCount(dueBy seconds: Double) -> Int {
            var low = 0
            var high = packetDueSeconds.count
            while low < high {
                let middle = (low + high) / 2
                if packetDueSeconds[middle] <= seconds {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low * Self.packetSize
        }
    }

    /// What the connection that holds the slot gets.
    nonisolated enum Script: Sendable {
        /// 200, then the stream at its own pace. Once it is used up the connection
        /// stays open and silent.
        case stream
        /// Streaming response with an explicit end marker, for a clean EOF.
        case chunkedStream
        /// A finite downloadable episode served with its byte length.
        case download
        /// 200 and the response headers, then nothing: a channel that is listed but dead.
        case headersOnly
        /// The connection is accepted and never answered: an overloaded panel.
        case silent
        /// A catalogue fetch has two parallel requests. Hold the first, answer the second.
        case waitingCatalogue
    }

    nonisolated struct Stats: Sendable, Equatable {
        /// Connections that got the slot.
        var admitted = 0
        /// Connections turned away with 403 because the slot was taken.
        var refused = 0
        /// 1 while a connection holds the slot.
        var open = 0
        var bytesSent = 0
        var providerHLSRequests = 0
        /// User-Agent of the last request that was read, admitted or refused.
        var lastUserAgent: String?
    }

    nonisolated enum MockPanelError: Error {
        case listenerNotReady
    }

    /// The connection that holds the slot. Only touched on `queue`.
    nonisolated private final class Admitted: @unchecked Sendable {
        let connection: NWConnection
        /// Set when the response headers went out; the stream clock starts here.
        var streamStartedAt: DispatchTime?
        var sentBytes = 0
        var sendInFlight = false
        var released = false

        init(_ connection: NWConnection) {
            self.connection = connection
        }
    }

    private let stream: Stream
    private let script: Script
    private let providerHLS: String?
    /// 1 = real time. The stream clock is multiplied by this.
    private let pace: Double
    private let queue = DispatchQueue(label: "MockPanelServer")
    private let lock = NSLock()
    private var statsStorage = Stats()
    private var portStorage: UInt16 = 0

    // Queue-confined state.
    private var listener: NWListener?
    private var ticker: DispatchSourceTimer?
    private var admitted: Admitted?
    /// Stream time past which nothing is sent; nil = no stall was asked for.
    private var stallAtStreamSeconds: Double?

    init(stream: Stream, script: Script = .stream, pace: Double = 1, providerHLS: String? = nil) {
        self.providerHLS = providerHLS
        self.stream = stream
        self.script = script
        self.pace = pace
    }

    var stats: Stats {
        lock.lock()
        defer { lock.unlock() }
        return statsStorage
    }

    var port: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return portStorage
    }

    /// Shaped like a live channel URL of an Xtream panel.
    var streamURL: URL {
        URL(string: "http://127.0.0.1:\(port)/live/harness/harness/1.ts")!
    }

    private func updateStats(_ change: (inout Stats) -> Void) {
        lock.lock()
        change(&statsStorage)
        lock.unlock()
    }

    // MARK: Lifecycle

    /// Binds 127.0.0.1 on a free port and waits (up to 2 s) until it is listening.
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let newListener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        newListener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.pump() }
        queue.sync {
            listener = newListener
            ticker = timer
        }
        timer.resume()
        newListener.start(queue: queue)
        guard ready.wait(timeout: .now() + 2) == .success,
              let bound = newListener.port?.rawValue, bound > 0
        else {
            stop()
            throw MockPanelError.listenerNotReady
        }
        lock.lock()
        portStorage = bound
        lock.unlock()
    }

    func stop() {
        queue.sync {
            ticker?.cancel()
            ticker = nil
            listener?.cancel()
            listener = nil
            if let entry = admitted {
                release(entry)
                entry.connection.cancel()
            }
        }
    }

    // MARK: Commands

    /// Stops sending once the stream clock reaches `streamSeconds` and keeps the
    /// connection open: a source that hangs. Given before the client connects it
    /// hangs at a known point of the stream, whatever the test's own timing; with
    /// 0 on a running stream nothing more is sent from now on.
    func stall(atStreamSeconds streamSeconds: Double = 0) {
        queue.async { self.stallAtStreamSeconds = streamSeconds }
    }

    /// Drops the open connection without finishing the response: a panel reset. The
    /// slot is free at once, so a client that reconnects is admitted again and gets
    /// the stream from its beginning.
    func reset() {
        queue.async {
            guard let entry = self.admitted else { return }
            self.release(entry)
            entry.connection.forceCancel()
        }
    }

    func sendPendingPlaylist(_ contents: String) {
        queue.async {
            guard self.script == .silent, let entry = self.admitted else { return }
            let body = Data(contents.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/x-mpegURL\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            entry.connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in
                self.release(entry)
                entry.connection.cancel()
            })
        }
    }

    func finishStream() {
        queue.async {
            guard case .chunkedStream = self.script, let entry = self.admitted else { return }
            entry.streamStartedAt = nil
            entry.connection.send(content: Data("0\r\n\r\n".utf8), completion: .contentProcessed { [weak self] _ in
                self?.release(entry)
                entry.connection.cancel()
            })
        }
    }

    // MARK: Connections (on `queue`)

    private func accept(_ connection: NWConnection) {
        guard admitted == nil else {
            // The slot is taken: answer like a panel at its connection limit. The
            // request is read first; closing with it unread would turn the 403
            // into a bare connection reset.
            updateStats { $0.refused += 1 }
            connection.start(queue: queue)
            readRequestHead(connection, buffer: Data()) { [weak self] head in
                self?.noteUserAgent(in: head)
                let response = self?.script == .waitingCatalogue
                    ? "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n[]"
                    : "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(
                    content: Data(response.utf8),
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            }
            return
        }
        let entry = Admitted(connection)
        admitted = entry
        updateStats {
            $0.admitted += 1
            $0.open += 1
        }
        connection.stateUpdateHandler = { [weak self, weak entry] state in
            guard let self, let entry else { return }
            switch state {
            case .failed:
                self.release(entry)
                entry.connection.cancel()
            case .cancelled:
                self.release(entry)
            default:
                break
            }
        }
        connection.start(queue: queue)
        readRequestHead(connection, buffer: Data()) { [weak self, weak entry] head in
            guard let self, let entry, !entry.released else { return }
            self.noteUserAgent(in: head)
            if let playlist = self.providerHLS,
               head.hasPrefix("GET /live/harness/harness/1.m3u8 ") {
                self.updateStats { $0.providerHLSRequests += 1 }
                let body = Data(playlist.utf8)
                let header = "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in
                    self.release(entry)
                    connection.cancel()
                })
                return
            }
            self.respond(to: entry)
            self.watchForClose(entry)
        }
    }

    private func readRequestHead(
        _ connection: NWConnection, buffer: Data, then handle: @escaping (String) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, isComplete, error in
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                handle(String(decoding: accumulated[..<headerEnd.lowerBound], as: UTF8.self))
            } else if error != nil || isComplete || accumulated.count > 64 * 1024 {
                connection.cancel()
            } else if let self {
                self.readRequestHead(connection, buffer: accumulated, then: handle)
            }
        }
    }

    private func noteUserAgent(in head: String) {
        let line = head.components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("user-agent:") }
        guard let line else { return }
        let value = line.dropFirst("user-agent:".count).trimmingCharacters(in: .whitespaces)
        updateStats { $0.lastUserAgent = value }
    }

    private func respond(to entry: Admitted) {
        if script == .download {
            let header = "HTTP/1.1 200 OK\r\nContent-Length: \(stream.data.count)\r\nConnection: close\r\n\r\n"
            entry.connection.send(content: Data(header.utf8) + stream.data, completion: .contentProcessed { _ in
                self.release(entry)
                entry.connection.cancel()
            })
            return
        }
        if script == .silent || script == .waitingCatalogue { return }
        // No Content-Length: the body runs until the connection ends, as live
        // channels are served.
        let transfer = script == .chunkedStream ? "Transfer-Encoding: chunked\r\n" : ""
        let header = "HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\n\(transfer)Connection: close\r\n\r\n"
        entry.connection.send(
            content: Data(header.utf8),
            completion: .contentProcessed { [weak self, weak entry] error in
                guard let self, let entry, error == nil else { return }
                if self.script == .stream || self.script == .chunkedStream {
                    entry.streamStartedAt = .now()
                }
            }
        )
    }

    /// The client sends nothing after its request, so a completed receive is the
    /// peer closing. The slot is released here, not when the connection object
    /// reports `.cancelled`: a client that reconnects right after closing must
    /// find the slot free.
    private func watchForClose(_ entry: Admitted) {
        entry.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self, weak entry] _, _, isComplete, error in
            guard let self, let entry else { return }
            if isComplete || error != nil {
                self.release(entry)
                entry.connection.cancel()
            } else {
                self.watchForClose(entry)
            }
        }
    }

    private func release(_ entry: Admitted) {
        guard !entry.released else { return }
        entry.released = true
        if admitted === entry { admitted = nil }
        updateStats { $0.open -= 1 }
    }

    /// Sends what the stream clock says is due. One send at a time: a slow reader
    /// simply gets more in the next one.
    private func pump() {
        guard let entry = admitted, let startedAt = entry.streamStartedAt, !entry.sendInFlight
        else { return }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
        var streamSeconds = Double(elapsedNanoseconds) / 1_000_000_000 * pace
        if let stallAtStreamSeconds { streamSeconds = min(streamSeconds, stallAtStreamSeconds) }
        let due = stream.byteCount(dueBy: streamSeconds)
        guard due > entry.sentBytes else { return }
        let payload = stream.data.subdata(in: entry.sentBytes..<due)
        let chunk = script == .chunkedStream
            ? Data("\(String(payload.count, radix: 16))\r\n".utf8) + payload + Data("\r\n".utf8)
            : payload
        entry.sentBytes = due
        entry.sendInFlight = true
        entry.connection.send(
            content: chunk,
            completion: .contentProcessed { [weak self, weak entry] error in
                guard let self, let entry else { return }
                entry.sendInFlight = false
                if error != nil {
                    self.release(entry)
                    entry.connection.cancel()
                } else {
                    self.updateStats { $0.bytesSent += chunk.count }
                }
            }
        )
    }
}
