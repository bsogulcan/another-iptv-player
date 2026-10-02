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
