import Foundation
import Network

/// Minimal statik dosya sunucusu: Apple TV, AirPlay sırasında HLS playlist/segmentleri
/// buradan çeker. Yalnız GET, kök dizin altı (bir seviye oturum alt dizini dahil),
/// range'siz — HLS istemcileri için yeterli.
final class LocalHTTPServer {
  /// Zapping'de oturum başına listener kurup yıkmamak için süreç boyu paylaşılan örnek;
  /// oturumlar kök altında kendi alt dizinlerini kullanır. Port ve yerel-ağ doğrulaması
  /// böylece bir kez yapılır.
  static let shared: LocalHTTPServer = {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("airplay-remux", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // App kill ile yarım kalan önceki oturum dizinleri (segment yığınları) süpürülür;
    // ilk cast anında süreçte hiçbir oturum yok, kökün tamamı güvenle temizlenir.
    sweepLeftovers(in: root)
    return LocalHTTPServer(directory: root)
  }()

  /// Leftovers can be several GB of segments, and the first touch of `shared` is the
  /// AirPlay tap on the main thread, so only the cheap part runs here: what is in
  /// the root right now is renamed into a hidden trash directory (one rename per
  /// entry), and the trash is deleted on a utility queue. A directory created after
  /// this returns was never listed and is never moved, so it cannot be deleted. The
  /// server refuses dot-names, and a trash left behind by a killed process is swept
  /// with the next one.
  private static func sweepLeftovers(in root: URL) {
    let fileManager = FileManager.default
    guard let leftovers = try? fileManager.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil
    ), !leftovers.isEmpty else { return }
    let trash = root.appendingPathComponent(
      ".sweep-\(UUID().uuidString.prefix(8))", isDirectory: true
    )
    guard (try? fileManager.createDirectory(at: trash, withIntermediateDirectories: true)) != nil
    else { return }
    for item in leftovers {
      try? fileManager.moveItem(
        at: item, to: trash.appendingPathComponent(item.lastPathComponent)
      )
    }
    DispatchQueue.global(qos: .utility).async {
      try? FileManager.default.removeItem(at: trash)
    }
  }

  let directory: URL
  private let listenerQueue = DispatchQueue(label: "AirPlayRemux.http.listener")
  /// Apple TV may request the playlist, init segment and media segments in
  /// parallel. Serving them on the listener's serial queue made one large
  /// segment read block every other request and caused avoidable startup stalls.
  private let connectionQueue = DispatchQueue(
    label: "AirPlayRemux.http.connections", attributes: .concurrent
  )
  /// listener/port farklı thread'lerden okunur (main'den start, queue'dan state
  /// callback'leri) — kilitle korunur.
  private let stateLock = NSLock()
  private var listener: NWListener?
  private var listenerPort: UInt16 = 0
  /// Port of the last listener that became ready. It outlives the listener so a
  /// replacement can try to come back on it: the URLs a live session has already
  /// handed to the receiver carry this port.
  private var lastBoundPort: UInt16 = 0
  /// Set when a loopback probe got no answer although the listener still looks
  /// ready. iOS defuncts listening sockets when the app is suspended, and whether
  /// NWListener then reports `.failed` is undocumented; without this flag such a
  /// listener would pass `start()`'s shortcut for the rest of the process.
  private var listenerPresumedDead = false

  /// Sessions whose requests are attributed (see `noteRequest`); own lock, it
  /// is touched once per request on the connection queue.
  private let receiverLock = NSLock()
  private var trackedSessions = Set<String>()
  private var fetchCountersBySession: [String: FetchCounters] = [:]

  /// What was asked of one session and by whom: the record that tells, after a cast
  /// went wrong, "the TV never connected" from "the TV was refused" from "the TV
  /// fetched and then stopped". Counts only; no address is kept.
  nonisolated struct FetchCounters: Equatable {
    /// Receiver requests answered with the file (200 or 206).
    var receiverServed = 0
    /// Receiver requests answered 404 or 416: a file that is not there (yet, or any
    /// more) or a range past its end.
    var receiverRefused = 0
    /// Requests from this phone: its own player loading the same playlist.
    var phoneRequests = 0
    /// When the receiver last asked for anything, whatever the answer; nil = never.
    /// This is the stamp the receiver watchdog reads.
    var lastReceiverFetch: Date?

    /// One line for the log. Pure function.
    func summary(now: Date) -> String {
      guard let lastReceiverFetch else {
        return "receiver never fetched; phone requests \(phoneRequests)"
      }
      let age = max(Int(now.timeIntervalSince(lastReceiverFetch)), 0)
      return "receiver served \(receiverServed), refused \(receiverRefused), "
        + "last fetch \(age)s ago; phone requests \(phoneRequests)"
    }
  }

  var port: UInt16 {
    stateLock.lock()
    defer { stateLock.unlock() }
    return listenerPort
  }

  init(directory: URL) {
    self.directory = directory
  }

  /// Idempotent: listener zaten ayaktaysa hızla döner. Ölmüş (failed/cancelled)
  /// listener state callback'inde kendini temizler — bir sonraki start() yeniden
  /// kurar; süreç ömrü boyu "ölü sunucu" durumu kalıcı olamaz.
  func start() throws {
    stateLock.lock()
    let alreadyRunning = listener != nil && listenerPort > 0 && !listenerPresumedDead
    let previousPort = lastBoundPort
    stateLock.unlock()
    if alreadyRunning { return }

    // A replacement first tries the port the previous listener had, which keeps the
    // URLs of a live session valid. The rebind is not guaranteed on devices
    // (EADDRINUSE despite allowLocalEndpointReuse), so any port is the fallback and
    // `ensureRunning()` tells its caller when that happened.
    if previousPort > 0, let samePort = NWEndpoint.Port(rawValue: previousPort),
       (try? bringUpListener(on: samePort)) == true {
      return
    }
    _ = try bringUpListener(on: .any)
  }

  /// Makes sure a listener is serving. Returns true when it came back on a
  /// different port than before (or could not be brought back at all): every URL
  /// handed out earlier is then stale and the session has to be rebuilt. A healthy
  /// listener returns false at once; a restart may block for up to about 2 s (one
  /// wait per bind attempt), like `start()`. A failed `checkHealth` marks the
  /// listener dead, so calling this afterwards replaces it.
  func ensureRunning() -> Bool {
    stateLock.lock()
    let running = listener != nil && listenerPort > 0 && !listenerPresumedDead
    let previousPort = lastBoundPort
    stateLock.unlock()
    if running { return false }
    do {
      try start()
    } catch {
      Log.error("AirPlayRemux", "http listener restart failed: \(error.localizedDescription)")
    }
    let currentPort = port
    guard previousPort > 0 else { return false }  // never served: no URL to go stale
    if currentPort != previousPort {
      Log.info("AirPlayRemux", "http listener moved from :\(previousPort) to :\(currentPort)")
    }
    return currentPort != previousPort
  }

  /// Creates a listener on `requestedPort` and waits up to 1 s for it to become
  /// ready. Returns whether it is serving. Whatever listener was current is
  /// cancelled, so a dead or never-ready one cannot linger beside its replacement.
  private func bringUpListener(on requestedPort: NWEndpoint.Port) throws -> Bool {
    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    let newListener = try NWListener(using: params, on: requestedPort)
    let ready = DispatchSemaphore(value: 0)
    newListener.newConnectionHandler = { [weak self] connection in
      self?.handle(connection)
    }
    newListener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        self.stateLock.lock()
        // A listener that was replaced while starting must not publish its port.
        let isCurrent = self.listener === newListener
        if isCurrent {
          self.listenerPort = newListener.port?.rawValue ?? 0
          if self.listenerPort > 0 { self.lastBoundPort = self.listenerPort }
        }
        let port = self.listenerPort
        self.stateLock.unlock()
        if isCurrent { Log.info("AirPlayRemux", "http server ready on :\(port)") }
        ready.signal()
      case let .failed(error):
        Log.error("AirPlayRemux", "http listener failed: \(error.localizedDescription)")
        newListener.cancel()
        self.clearIfCurrent(newListener)
        ready.signal()
      case .cancelled:
        self.clearIfCurrent(newListener)
        ready.signal()
      default:
        break
      }
    }
    stateLock.lock()
    let replaced = listener
    listener = newListener
    listenerPort = 0
    listenerPresumedDead = false
    stateLock.unlock()
    replaced?.cancel()
    newListener.start(queue: listenerQueue)
    // Çağıran port'u senkron bekler (en fazla 1 sn); polling yerine state sinyali.
    _ = ready.wait(timeout: .now() + 1)
    stateLock.lock()
    let serving = listener === newListener && listenerPort > 0
    stateLock.unlock()
    return serving
  }

  private func clearIfCurrent(_ candidate: NWListener) {
    stateLock.lock()
    if listener === candidate {
      listener = nil
      listenerPort = 0
      listenerPresumedDead = false
    }
    stateLock.unlock()
  }

  func stop() {
    stateLock.lock()
    let current = listener
    listener = nil
    listenerPort = 0
    listenerPresumedDead = false
    stateLock.unlock()
    current?.cancel()
  }

  // MARK: - Health

  /// A proxy or a cached response must never vouch for a dead listener.
  private static let probeSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.connectionProxyDictionary = [:]
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }()

  /// Does the listener really answer? GET http://127.0.0.1:<port>/ping, the only
  /// proof that survives a suspension (the state callback may never report a
  /// defunct socket). `completion` runs on main. A failure marks the listener dead,
  /// so the next `ensureRunning()` / `start()` replaces it.
  func checkHealth(completion: @escaping (Bool) -> Void) {
    checkHealth(attempts: 2, completion: completion)
  }

  /// `attempts` quick tries, 0.2 s apart, each bounded by a 1 s timeout (a live
  /// listener answers in milliseconds, a defunct socket refuses at once).
  func checkHealth(attempts: Int, completion: @escaping (Bool) -> Void) {
    stateLock.lock()
    let probedListener = listener
    let probedPort = listenerPort
    stateLock.unlock()
    guard let probedListener, probedPort > 0,
          let url = URL(string: "http://127.0.0.1:\(probedPort)/ping") else {
      DispatchQueue.main.async { completion(false) }
      return
    }
    probe(url, attemptsLeft: max(attempts, 1)) { [weak self] answered in
      if !answered { self?.markPresumedDead(probedListener, port: probedPort) }
      completion(answered)
    }
  }

  private func probe(_ url: URL, attemptsLeft: Int, completion: @escaping (Bool) -> Void) {
    var request = URLRequest(url: url)
    request.timeoutInterval = 1
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let task = Self.probeSession.dataTask(with: request) { [weak self] data, response, _ in
      // The body is checked too: once our socket is gone another process may own
      // the port, and any 200 from it would pass for ours.
      if (response as? HTTPURLResponse)?.statusCode == 200, data == Data("ok".utf8) {
        DispatchQueue.main.async { completion(true) }
      } else if attemptsLeft > 1, let self {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
          self.probe(url, attemptsLeft: attemptsLeft - 1, completion: completion)
        }
      } else {
        DispatchQueue.main.async { completion(false) }
      }
    }
    task.resume()
  }

  private func markPresumedDead(_ probed: NWListener, port deadPort: UInt16) {
    stateLock.lock()
    // Only the listener that was probed, by identity: a replacement may already be
    // serving, and it deliberately comes back on the same port.
    let marked = listener === probed
    if marked { listenerPresumedDead = true }
    stateLock.unlock()
    if marked {
      Log.error("AirPlayRemux", "http listener on :\(deadPort) does not answer; will be replaced")
    }
  }

  // MARK: - Receiver fetches

  /// Starts attributing requests under `/<session>/…` to that session. Only tracked
  /// names are stamped, so stray requests cannot grow the table.
  func beginTrackingReceiverFetches(session: String) {
    receiverLock.lock()
    trackedSessions.insert(session)
    receiverLock.unlock()
  }

  func endTrackingReceiverFetches(session: String) {
    receiverLock.lock()
    trackedSessions.remove(session)
    fetchCountersBySession[session] = nil
    receiverLock.unlock()
  }

  /// When a peer that is not this phone last requested anything under
  /// `/<session>/…` (a 404 counts: the receiver reached us). nil = never.
  func lastReceiverFetch(session: String) -> Date? {
    receiverLock.lock()
    defer { receiverLock.unlock() }
    return fetchCountersBySession[session]?.lastReceiverFetch
  }

  /// The request record of a tracked session; nil when it is not tracked.
  func fetchCounters(session: String) -> FetchCounters? {
    receiverLock.lock()
    defer { receiverLock.unlock() }
    guard trackedSessions.contains(session) else { return nil }
    return fetchCountersBySession[session] ?? FetchCounters()
  }

  /// A request for `/<session>/…` arrived. A receiver request is stamped here,
  /// before the file lookup, exactly as before the counters existed: the watchdog
  /// reads the stamp and a 404 still proves the receiver reached us. `peer` is only
  /// for the log line of the first receiver fetch.
  func noteRequest(session: String, fromReceiver: Bool, peer: String?) {
    receiverLock.lock()
    let tracked = trackedSessions.contains(session)
    var isFirst = false
    if tracked {
      var counters = fetchCountersBySession[session] ?? FetchCounters()
      if fromReceiver {
        isFirst = counters.lastReceiverFetch == nil
        counters.lastReceiverFetch = Date()
      } else {
        counters.phoneRequests += 1
      }
      fetchCountersBySession[session] = counters
    }
    receiverLock.unlock()
    if isFirst {
      Log.info("AirPlayRemux", "first receiver fetch for \(session) from \(peer ?? "unknown peer")")
    }
  }

  /// How a receiver request for `/<session>/…` was answered: `served` for 200 and
  /// 206, otherwise 404 or 416. Record only; nothing reads it to make a decision.
  func noteReceiverResponse(session: String, served: Bool) {
    receiverLock.lock()
    if trackedSessions.contains(session) {
      var counters = fetchCountersBySession[session] ?? FetchCounters()
      if served {
        counters.receiverServed += 1
      } else {
        counters.receiverRefused += 1
      }
      fetchCountersBySession[session] = counters
    }
    receiverLock.unlock()
  }

  /// Is a request from `address` evidence that the receiver can reach the phone?
  /// Not when it is loopback or one of the phone's own addresses: those are our own
  /// probes and the phone-side AVPlayer, which loads the same URL. IPv4-mapped IPv6
  /// (the dual-stack listener reports `::ffff:192.168.1.20`) and zone suffixes are
  /// normalised on both sides. An address that cannot be identified counts as the
  /// receiver: a missing stamp may be used to end a cast, a spare one only keeps
  /// today's behaviour. Pure function.
  static func isReceiverPeer(_ address: String, ownAddresses: Set<String>) -> Bool {
    let peer = normalizedAddress(address)
    if peer.isEmpty { return true }
    if isLoopbackAddress(peer) { return false }
    return !ownAddresses.contains { normalizedAddress($0) == peer }
  }

  /// Canonical numeric form: no zone ("fe80::1%en0"), IPv4-mapped IPv6 as dotted
  /// IPv4, IPv6 in inet_ntop's spelling. Anything else is lowercased as is.
  static func normalizedAddress(_ raw: String) -> String {
    let unscoped = raw.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init) ?? raw
    let text = unscoped.trimmingCharacters(in: .whitespaces)
    var v6 = in6_addr()
    if inet_pton(AF_INET6, text, &v6) == 1 {
      let bytes = withUnsafeBytes(of: &v6) { Array($0) }
      if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
        return bytes[12...].map { String($0) }.joined(separator: ".")
      }
      var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
      if inet_ntop(AF_INET6, &v6, &buffer, socklen_t(buffer.count)) != nil {
        return String(cString: buffer)
      }
    }
    var v4 = in_addr()
    if inet_pton(AF_INET, text, &v4) == 1 {
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      if inet_ntop(AF_INET, &v4, &buffer, socklen_t(buffer.count)) != nil {
        return String(cString: buffer)
      }
    }
    return text.lowercased()
  }

  /// `address` must already be normalised.
  static func isLoopbackAddress(_ address: String) -> Bool {
    address == "::1" || address == "localhost" || address.hasPrefix("127.")
  }

  /// Every IPv4/IPv6 address on any interface of this phone, normalised. Unlike
  /// `lanIPv4Address()` nothing is filtered: the phone's own requests may leave
  /// from any of them.
  static func ownInterfaceAddresses() -> Set<String> {
    var addrList: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrList) == 0, let first = addrList else { return [] }
    defer { freeifaddrs(addrList) }
    var addresses = Set<String>()
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = cursor {
      let ifa = entry.pointee
      cursor = ifa.ifa_next
      guard let sa = ifa.ifa_addr else { continue }
      let family = sa.pointee.sa_family
      guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(
        sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
        nil, 0, NI_NUMERICHOST
      ) == 0 {
        addresses.insert(normalizedAddress(String(cString: host)))
      }
    }
    return addresses
  }

  /// Numeric address of a connection's remote end; nil when it is not an IP endpoint.
  private static func peerAddress(of endpoint: NWEndpoint) -> String? {
    guard case let .hostPort(host, _) = endpoint else { return nil }
    switch host {
    case let .ipv4(address):
      return numericString(address.rawValue, family: AF_INET)
    case let .ipv6(address):
      return numericString(address.rawValue, family: AF_INET6)
    case let .name(name, _):
      return name
    @unknown default:
      return nil
    }
  }

  private static func numericString(_ raw: Data, family: Int32) -> String? {
    guard raw.count == (family == AF_INET ? 4 : 16) else { return nil }
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    let converted = raw.withUnsafeBytes { bytes in
      inet_ntop(family, bytes.baseAddress, &buffer, socklen_t(buffer.count)) != nil
    }
    return converted ? String(cString: buffer) : nil
  }

  /// Telefonun, Apple TV'nin erişebileceği IPv4 adresi. Tercih sırası: en0 (Wi-Fi) →
  /// bridge* (hotspot: TV telefonun hotspot'undaysa) → diğer en* arayüzleri.
  /// lo/utun(VPN)/pdp_ip(hücresel)/awdl-llw adresleri TV'den erişilemez, atlanır;
  /// 169.254.* link-local adresler de (DHCP yokken) elenir.
  static func lanIPv4Address() -> String? {
    var addrList: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
    defer { freeifaddrs(addrList) }
    var best: (rank: Int, address: String)?
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = cursor {
      let ifa = entry.pointee
      cursor = ifa.ifa_next
      guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
      let name = String(cString: ifa.ifa_name)
      let rank: Int
      if name == "en0" {
        rank = 0
      } else if name.hasPrefix("bridge") {
        rank = 1
      } else if name.hasPrefix("en") {
        rank = 2
      } else {
        continue
      }
      if let bestSoFar = best, bestSoFar.rank <= rank { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(
        sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
        nil, 0, NI_NUMERICHOST
      ) == 0 {
        let address = String(cString: host)
        guard isReceiverReachableIPv4(address) else { continue }
        best = (rank, address)
      }
    }
    return best?.address
  }

  /// Can a receiver on the LAN fetch from this IPv4 address of the phone? Not from
  /// a link-local one (169.254/16: no DHCP lease) and not from 192.0.0.0/29, the
  /// range an IPv6-only network gives the phone for its own IPv4 translation (CLAT,
  /// RFC 7335): that address exists only inside the phone. Pure function.
  static func isReceiverReachableIPv4(_ address: String) -> Bool {
    if address.hasPrefix("169.254.") { return false }
    let parts = address.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 4, parts[0] == "192", parts[1] == "0", parts[2] == "0",
       let last = Int(parts[3]), (0..<8).contains(last)
    {
      return false
    }
    return true
  }

  // MARK: - Request handling

  /// Who is on the other end of a connection. Known when it is accepted; which
  /// session it asks for is known only once the request line is parsed.
  private struct Peer {
    let address: String?
    let isReceiver: Bool
  }

  private func handle(_ connection: NWConnection) {
    let address = Self.peerAddress(of: connection.endpoint)
    let peer = Peer(
      address: address,
      isReceiver: address.map {
        Self.isReceiverPeer($0, ownAddresses: Self.ownInterfaceAddresses())
      } ?? true
    )
    connection.start(queue: connectionQueue)
    receiveRequest(connection, buffer: Data(), peer: peer)
  }

  private func receiveRequest(_ connection: NWConnection, buffer: Data, peer: Peer) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
      [weak self] data, _, _, error in
      guard let self, error == nil, let data else {
        connection.cancel()
        return
      }
      var accumulated = buffer
      accumulated.append(data)
      if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
        let head = String(decoding: accumulated[..<headerEnd.lowerBound], as: UTF8.self)
        self.respond(connection, requestHead: head, peer: peer)
      } else if accumulated.count < 64 * 1024 {
        self.receiveRequest(connection, buffer: accumulated, peer: peer)
      } else {
        connection.cancel()
      }
    }
  }

  private func respond(_ connection: NWConnection, requestHead: String, peer: Peer) {
    guard let requestLine = requestHead.components(separatedBy: "\r\n").first,
          requestLine.hasPrefix("GET ")
    else {
      send(connection, status: "405 Method Not Allowed", body: Data(), contentType: "text/plain")
      return
    }
    let rawPath = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
    let cleanPath = rawPath.split(separator: "?").first.map(String.init) ?? "/"
    if cleanPath == "/ping" {
      // Erişilebilirlik/izin ön-doğrulaması: playlist hazır olmadan da 200 verir.
      send(connection, status: "200 OK", body: Data("ok".utf8), contentType: "text/plain")
      return
    }
    // Yol atlatmaya kapalı: kök altında en fazla iki bileşen (oturum-dizini/dosya),
    // ".." ve boş bileşen reddedilir.
    let components = cleanPath.split(separator: "/").map(String.init)
    guard !components.isEmpty, components.count <= 2,
          components.allSatisfy({ !$0.isEmpty && $0 != ".." && !$0.hasPrefix(".") })
    else {
      send(connection, status: "404 Not Found", body: Data(), contentType: "text/plain")
      return
    }
    // Stamped before the file lookup: a 404 still proves the receiver reached us.
    let session = components.count == 2 ? components[0] : nil
    if let session {
      noteRequest(session: session, fromReceiver: peer.isReceiver, peer: peer.address)
    }
    // The answer a receiver got is counted where it is sent (record only).
    func noteAnswer(served: Bool) {
      guard let session, peer.isReceiver else { return }
      noteReceiverResponse(session: session, served: served)
    }
    let fileURL = components.reduce(directory) { $0.appendingPathComponent($1) }
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
          let number = attributes[.size] as? NSNumber
    else {
      noteAnswer(served: false)
      send(connection, status: "404 Not Found", body: Data(), contentType: "text/plain")
      return
    }
    let fileSize = number.intValue
    let fileName = components.last!
    let contentType = Self.contentType(for: fileName)
    let rangeHeader = requestHead.components(separatedBy: "\r\n")
      .first { $0.lowercased().hasPrefix("range:") }
      .map { $0.dropFirst("range:".count).trimmingCharacters(in: .whitespaces) }

    if let rangeHeader {
      guard let range = Self.byteRange(from: rangeHeader, fileSize: fileSize),
            let data = Self.read(fileURL, range: range)
      else {
        noteAnswer(served: false)
        send(
          connection, status: "416 Range Not Satisfiable", body: Data(),
          contentType: contentType,
          additionalHeaders: ["Content-Range": "bytes */\(fileSize)"]
        )
        return
      }
      noteAnswer(served: true)
      send(
        connection, status: "206 Partial Content", body: data,
        contentType: contentType, noCache: fileName.hasSuffix(".m3u8"),
        additionalHeaders: [
          "Accept-Ranges": "bytes",
          "Content-Range": "bytes \(range.lowerBound)-\(range.upperBound)/\(fileSize)",
        ]
      )
      return
    }

    guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
      noteAnswer(served: false)
      send(connection, status: "404 Not Found", body: Data(), contentType: "text/plain")
      return
    }
    noteAnswer(served: true)
    send(
      connection, status: "200 OK", body: data,
      contentType: contentType, noCache: fileName.hasSuffix(".m3u8"),
      additionalHeaders: ["Accept-Ranges": "bytes"]
    )
  }

  /// Parses a single RFC 7233 byte range. AVPlayer commonly uses both open-ended
  /// (`bytes=1024-`) and suffix (`bytes=-1024`) forms for fMP4 resources.
  private static func byteRange(from header: String, fileSize: Int) -> ClosedRange<Int>? {
    guard fileSize > 0, header.lowercased().hasPrefix("bytes=") else { return nil }
    let value = header.dropFirst("bytes=".count)
    guard !value.contains(",") else { return nil }  // multipart ranges unsupported
    let bounds = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard bounds.count == 2 else { return nil }

    if bounds[0].isEmpty {
      guard let suffix = Int(bounds[1]), suffix > 0 else { return nil }
      let length = min(suffix, fileSize)
      return (fileSize - length)...(fileSize - 1)
    }

    guard let start = Int(bounds[0]), start >= 0, start < fileSize else { return nil }
    let requestedEnd = bounds[1].isEmpty ? fileSize - 1 : Int(bounds[1])
    guard let requestedEnd, requestedEnd >= start else { return nil }
    return start...min(requestedEnd, fileSize - 1)
  }

  private static func read(_ url: URL, range: ClosedRange<Int>) -> Data? {
    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(range.lowerBound))
      return try handle.read(upToCount: range.count)
    } catch {
      return nil
    }
  }

  private static func contentType(for fileName: String) -> String {
    if fileName.hasSuffix(".m3u8") { return "application/vnd.apple.mpegurl" }
    if fileName.hasSuffix(".ts") { return "video/mp2t" }
    if fileName.hasSuffix(".m4s") { return "video/iso.segment" }
    if fileName.hasSuffix(".mp4") { return "video/mp4" }
    // WebVTT subtitle rendition (AirPlay subtitles). AVPlayer rejects a legible
    // rendition unless it is served as text/vtt.
    if fileName.hasSuffix(".vtt") { return "text/vtt" }
    return "application/octet-stream"
  }

  private func send(
    _ connection: NWConnection,
    status: String,
    body: Data,
    contentType: String,
    noCache: Bool = false,
    additionalHeaders: [String: String] = [:]
  ) {
    var header = "HTTP/1.1 \(status)\r\n"
    header += "Content-Type: \(contentType)\r\n"
    header += "Content-Length: \(body.count)\r\n"
    header += "Access-Control-Allow-Origin: *\r\n"
    if noCache { header += "Cache-Control: no-cache\r\n" }
    for (name, value) in additionalHeaders {
      header += "\(name): \(value)\r\n"
    }
    header += "Connection: close\r\n\r\n"
    var response = Data(header.utf8)
    response.append(body)
    connection.send(
      content: response,
      completion: .contentProcessed { _ in
        connection.cancel()
      }
    )
  }
}
