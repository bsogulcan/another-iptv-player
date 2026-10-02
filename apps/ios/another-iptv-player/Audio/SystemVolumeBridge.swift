import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit
    
/// Donanım / Kontrol Merkezi ile aynı sistem çıkış sesi (`MPVolumeView` iç `UISlider`).
///
/// Owned by `VideoPlayerController` as a plain `let` (one instance per player, created
/// once). Only the volume capsule and `MPVolumeViewHost` observe it: held as a
/// `@StateObject` of the player view, every volume publish re-evaluated the whole
/// player body.
final class SystemVolumeBridge: NSObject, ObservableObject {
  @Published private(set) var outputVolume: Float

  private weak var volumeSlider: UISlider?

  /// KVO on `AVAudioSession.outputVolume`: the public signal for hardware-button and
  /// Control Center changes. The private slider's `.valueChanged` stays as a second
  /// source, but the capsule must not depend on `MPVolumeSlider` internals to follow
  /// the buttons.
  private var sessionVolumeObservation: NSKeyValueObservation?

  /// Volume reports that arrive right after one of our own writes are mostly echoes of
  /// that write, and during a drag they lag the finger. They are parked here and the
  /// newest one is published once the writes have stopped, so a drag neither bounces
  /// the published value nor publishes once per echo.
  private var deferredVolume: Float?
  private var isDeferredFlushScheduled = false
  private var lastAppWriteAt: TimeInterval = 0
  private static let appWriteEchoWindow: TimeInterval = 0.25

  override init() {
    let session = AVAudioSession.sharedInstance()
    outputVolume = session.outputVolume
    super.init()
    // Fires only while the audio session is active, which holds during playback.
    sessionVolumeObservation = session.observe(\.outputVolume, options: [.new]) {
      [weak self] session, change in
      let reported = change.newValue ?? session.outputVolume
      DispatchQueue.main.async { self?.adoptReportedVolume(reported) }
    }
  }

  deinit {
    sessionVolumeObservation?.invalidate()
  }

  func registerVolumeSlider(_ slider: UISlider) {
    guard volumeSlider !== slider else {
      if outputVolume != slider.value { outputVolume = slider.value }
      return
    }
    volumeSlider?.removeTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    volumeSlider = slider
    slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    if outputVolume != slider.value { outputVolume = slider.value }
  }

  @objc private func sliderValueChanged(_ sender: UISlider) {
    adoptReportedVolume(sender.value)
  }

  /// Sets the system volume and publishes it right away (taps, accessibility steps and
  /// the end of a drag).
  func setOutputVolume(_ value: Float) {
    let v = min(max(value, 0), 1)
    guard let slider = volumeSlider else {
      if outputVolume != v { outputVolume = v }
      return
    }
    lastAppWriteAt = ProcessInfo.processInfo.systemUptime
    // This value supersedes whatever was parked; echoes still in flight park again.
    deferredVolume = nil
    slider.setValue(v, animated: false)
    if outputVolume != v {
      outputVolume = v
    }
  }

  /// Sets the system volume while a drag is in flight, without publishing: the capsule
  /// draws its own finger-driven value, and every publish here re-evaluates each view
  /// that observes the bridge. `setOutputVolume` at the end of the drag publishes; if
  /// that never comes (the gesture was cancelled or the view went away) the parked
  /// value is published once the writes stop.
  func previewOutputVolume(_ value: Float) {
    let v = min(max(value, 0), 1)
    lastAppWriteAt = ProcessInfo.processInfo.systemUptime
    volumeSlider?.setValue(v, animated: false)
    deferredVolume = v
    scheduleDeferredFlush()
  }

  /// Main thread. A volume the system reported (session KVO or the hidden slider).
  private func adoptReportedVolume(_ value: Float) {
    let sinceWrite = ProcessInfo.processInfo.systemUptime - lastAppWriteAt
    if sinceWrite < Self.appWriteEchoWindow {
      deferredVolume = value
      scheduleDeferredFlush()
      return
    }
    deferredVolume = nil
    if outputVolume != value {
      outputVolume = value
    }
  }

  private func scheduleDeferredFlush() {
    guard !isDeferredFlushScheduled else { return }
    isDeferredFlushScheduled = true
    let sinceWrite = ProcessInfo.processInfo.systemUptime - lastAppWriteAt
    let delay = max(Self.appWriteEchoWindow - sinceWrite, 0) + 0.02
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      self.isDeferredFlushScheduled = false
      guard let parked = self.deferredVolume else { return }
      // Re-parks (and re-schedules) if another write landed in the meantime.
      self.adoptReportedVolume(parked)
    }
  }
}

// MARK: - Görünmez MPVolumeView

/// Görünmez `MPVolumeView`; SwiftUI kaydırıcısı `SystemVolumeBridge` ile bağlanır.
struct MPVolumeViewHost: UIViewRepresentable {
  @ObservedObject var bridge: SystemVolumeBridge
  /// An on-screen `MPVolumeView` (even a nearly transparent one) makes iOS drop its own
  /// volume HUD. Pass `false` while the in-app capsule is not visible (chrome hidden,
  /// mini player) so hardware volume presses get the system HUD back; the view is then
  /// hidden, not unmounted, because a fresh slider can report a stale value until its
  /// first sync. Must be `true` whenever the capsule is on screen: the capsule sets the
  /// volume through this view's slider. Defaults to the previous always-on behaviour.
  var suppressesSystemHUD: Bool = true

  func makeUIView(context: Context) -> MPVolumeHostingView {
    let view = MPVolumeHostingView(bridge: bridge)
    view.suppressesSystemHUD = suppressesSystemHUD
    return view
  }

  func updateUIView(_ uiView: MPVolumeHostingView, context: Context) {
    uiView.bridge = bridge
    uiView.suppressesSystemHUD = suppressesSystemHUD
  }
}

/// `UIViewRepresentable` dönüş tipi en az `internal` olmalı (`private` Swift derleyicisinde reddedilir).
final class MPVolumeHostingView: UIView {
  var bridge: SystemVolumeBridge
  /// See `MPVolumeViewHost.suppressesSystemHUD`.
  var suppressesSystemHUD = true {
    didSet {
      guard oldValue != suppressesSystemHUD else { return }
      volumeView.isHidden = !suppressesSystemHUD
    }
  }
  private let volumeView: MPVolumeView
  private weak var attachedSlider: UISlider?

  init(bridge: SystemVolumeBridge) {
    self.bridge = bridge
    let v = MPVolumeView()
    v.alpha = 0.02
    v.showsVolumeSlider = true
    v.isUserInteractionEnabled = false
    self.volumeView = v
    super.init(frame: .zero)
    addSubview(v)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    volumeView.frame = bounds
    guard let slider = Self.findVolumeSlider(in: volumeView) else { return }
    guard attachedSlider !== slider else { return }
    attachedSlider = slider
    bridge.registerVolumeSlider(slider)
  }

  private static func findVolumeSlider(in view: UIView) -> UISlider? {
    if let s = view as? UISlider { return s }
    for sub in view.subviews {
      if let s = findVolumeSlider(in: sub) { return s }
    }
    return nil
  }
}
