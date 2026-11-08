import AVFoundation
import KSPlayer

/// AVAudioEngine stops itself when iOS changes the output configuration. KSPlayer
/// flushes its frames on route changes but never restarts that stopped engine.
// KSPlayer's transport calls and our recovery work run on main. Notifications
// from the audio thread only enqueue work; they never touch the transport state.
nonisolated final class RecoveringAudioEnginePlayer: AudioOutput, @unchecked Sendable {
  private let output = AudioEnginePlayer()
  var engine: AVAudioEngine { output.engine }
  var renderSource: OutputRenderSourceDelegate? {
    get { output.renderSource }
    set { output.renderSource = newValue }
  }
  var playbackRate: Float {
    get { output.playbackRate }
    set { output.playbackRate = newValue }
  }
  var volume: Float {
    get { output.volume }
    set { output.volume = newValue }
  }
  var isMuted: Bool {
    get { output.isMuted }
    set { output.isMuted = newValue }
  }
  private var wantsPlayback = false
  private var configurationObserver: NSObjectProtocol?
  private var recovery: DispatchWorkItem?

  init() {
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in self?.scheduleRecovery(attempt: 0) }
    }
  }

  func prepare(audioFormat: AVAudioFormat) { output.prepare(audioFormat: audioFormat) }
  func flush() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.flush() }
      return
    }
    output.flush()
    recoverIfStopped()
  }

  /// Also called by the playback watchdog: a spontaneous engine stop need not
  /// produce a route-change notification, and the video can keep playing.
  func recoverIfStopped() {
    if wantsPlayback, !engine.isRunning, recovery == nil {
      scheduleRecovery(attempt: 0)
    }
  }

  func play() {
    wantsPlayback = true
    output.play()
    if !engine.isRunning { scheduleRecovery(attempt: 0) }
  }

  func pause() {
    wantsPlayback = false
    recovery?.cancel()
    recovery = nil
    output.pause()
  }

  private func scheduleRecovery(attempt: Int) {
    recovery?.cancel()
    guard wantsPlayback, attempt < 3 else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.wantsPlayback else { return }
      self.recovery = nil
      if !self.engine.isRunning {
        Log.info("PlayerAudio", "restarting stopped audio engine (attempt \(attempt + 1))")
        self.output.play()
        if !self.engine.isRunning { self.scheduleRecovery(attempt: attempt + 1) }
      }
    }
    recovery = work
    // Let the audio session and graph settle before restarting. Do not seek or
    // reopen the source: that would interrupt single-connection IPTV accounts.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
  }

  deinit {
    recovery?.cancel()
    if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
  }
}

#if os(macOS)
import CoreAudio

/// HAL may wait several seconds for an output device. Keep every graph operation
/// on one queue so a stalled device cannot block the window or its controls.
nonisolated final class MacAudioOutput: AudioOutput, @unchecked Sendable {
  static let speakerKey = "mac.useBuiltInSpeakers"
  private let queue = DispatchQueue(label: "iptv.mac.audio-output", qos: .userInitiated)
  private let lock = NSLock()
  private weak var source: OutputRenderSourceDelegate?
  private var rate: Float = 1
  private var gain: Float = 1
  private var muted = false
  private var playing = false
  // Accessed only on queue.
  private var output: AudioEnginePlayer?
  private var format: AVAudioFormat?
  private var builtIn: Bool?
  private var failedStartAt: ContinuousClock.Instant?
  private var configurationObserver: NSObjectProtocol?
  private var defaultsObserver: NSObjectProtocol?

  private let defaults: UserDefaults
  private let startAudio: @Sendable (AudioEnginePlayer) -> Void
  convenience init() { self.init(startAudio: { $0.play() }) }
  init(defaults: UserDefaults = .standard, startAudio: @escaping @Sendable (AudioEnginePlayer) -> Void) {
    self.defaults = defaults
    self.startAudio = startAudio
    defaultsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: nil
    ) { [weak self] _ in
      self?.enqueue { player in
        if player.updateRoute() { player.playIfRequested() }
      }
    }
  }

  private func enqueue(_ action: @escaping @Sendable (MacAudioOutput) -> Void) {
    queue.async { [weak self] in
      if let self { action(self) }
    }
  }

  var renderSource: OutputRenderSourceDelegate? {
    get { lock.withLock { source } }
    set {
      lock.withLock { source = newValue }
      enqueue { $0.output?.renderSource = $0.renderSource }
    }
  }
  var playbackRate: Float {
    get { lock.withLock { rate } }
    set { lock.withLock { rate = newValue }; enqueue { $0.output?.playbackRate = $0.playbackRate } }
  }
  var volume: Float {
    get { lock.withLock { gain } }
    set { lock.withLock { gain = newValue }; enqueue { $0.output?.volume = $0.volume } }
  }
  var isMuted: Bool {
    get { lock.withLock { muted } }
    set { lock.withLock { muted = newValue }; enqueue { $0.output?.isMuted = $0.isMuted } }
  }

  func prepare(audioFormat: AVAudioFormat) {
    enqueue { player in
      if player.output == nil {
        let output = AudioEnginePlayer()
        player.output = output
        output.renderSource = player.renderSource
        player.configurationObserver = NotificationCenter.default.addObserver(
          forName: .AVAudioEngineConfigurationChange, object: output.engine, queue: nil
        ) { [weak player] _ in player?.enqueue { $0.playIfRequested() } }
      }
      _ = player.updateRoute()
      guard player.format != audioFormat, let output = player.output else { return }
      player.format = audioFormat
      output.pause()
      output.prepare(audioFormat: audioFormat)
      output.playbackRate = player.playbackRate
      output.volume = player.volume
      output.isMuted = player.isMuted
      player.playIfRequested()
    }
  }

  func play() {
    lock.withLock { playing = true }
    enqueue { $0.playIfRequested() }
  }
  func pause() {
    lock.withLock { playing = false }
    enqueue { $0.output?.pause() }
  }
  func flush() { enqueue { $0.output?.flush() } }

  private func playIfRequested() {
    guard lock.withLock({ playing }), format != nil, let output, !output.engine.isRunning else { return }
    if let failedStartAt, ContinuousClock.now < failedStartAt.advanced(by: .seconds(3)) { return }
    startAudio(output)
    failedStartAt = output.engine.isRunning ? nil : .now
  }

  @discardableResult private func updateRoute() -> Bool {
    guard let output else { return false }
    let requested = defaults.bool(forKey: Self.speakerKey)
    guard requested != builtIn else { return false }
    let initial = builtIn == nil
    failedStartAt = nil
    builtIn = requested
    // Leave a new graph attached to the default route so normal system changes
    // continue to work. When returning from an override, rebuild that graph.
    if !requested && initial { return false }
    if !requested {
      output.engine.stop()
      if let token = configurationObserver { NotificationCenter.default.removeObserver(token) }
      configurationObserver = nil
      self.output = nil
      if let format {
        self.format = nil
        prepare(audioFormat: format)
      }
      builtIn = nil
      return false
    }
    guard let device = Self.builtInOutput() else { return false }
    output.pause()
    do {
      try output.engine.outputNode.auAudioUnit.setDeviceID(device)
      return true
    } catch {
      Log.info("PlayerAudio", "Built-in audio output could not be selected.")
      return false
    }
  }

  static func builtInOutput() -> AudioDeviceID? {
    let system = AudioObjectID(kAudioObjectSystemObject)
    func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
      .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    var devicesAddress = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr else { return nil }
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard !devices.isEmpty, AudioObjectGetPropertyData(system, &devicesAddress, 0, nil, &size, &devices) == noErr else { return nil }
    return devices.first { device in
      var transport = UInt32(0), bytes = UInt32(MemoryLayout<UInt32>.size)
      var type = address(kAudioDevicePropertyTransportType)
      guard AudioObjectGetPropertyData(device, &type, 0, nil, &bytes, &transport) == noErr,
            transport == kAudioDeviceTransportTypeBuiltIn else { return false }
      var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
      return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &bytes) == noErr && bytes > 0
    }
  }

  static func builtInOutputUID() -> String? {
    guard let device = builtInOutput() else { return nil }
    var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var uid: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &uid) == noErr else { return nil }
    return uid?.takeRetainedValue() as String?
  }

  deinit {
    if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    // The last graph reference is transferred to the same queue that owns it.
    nonisolated(unsafe) let output = output
    queue.async { output?.pause() }
  }
}
#endif
