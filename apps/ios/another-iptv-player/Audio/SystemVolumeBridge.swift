import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

/// Donanım / Kontrol Merkezi ile aynı sistem çıkış sesi (`MPVolumeView` iç `UISlider`).
final class SystemVolumeBridge: NSObject, ObservableObject {
  @Published private(set) var outputVolume: Float

  private weak var volumeSlider: UISlider?

  override init() {
    outputVolume = AVAudioSession.sharedInstance().outputVolume
    super.init()
  }

  func registerVolumeSlider(_ slider: UISlider) {
    guard volumeSlider !== slider else {
      outputVolume = slider.value
      return
    }
    volumeSlider?.removeTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    volumeSlider = slider
    slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    outputVolume = slider.value
  }

  @objc private func sliderValueChanged(_ sender: UISlider) {
    let v = sender.value
    if outputVolume != v {
      outputVolume = v
    }
  }

  func setOutputVolume(_ value: Float) {
    let v = min(max(value, 0), 1)
    guard let slider = volumeSlider else {
      outputVolume = v
      return
    }
    slider.setValue(v, animated: false)
    if outputVolume != v {
      outputVolume = v
    }
  }
}

// MARK: - Görünmez MPVolumeView

/// Görünmez `MPVolumeView`; SwiftUI kaydırıcısı `SystemVolumeBridge` ile bağlanır.
struct MPVolumeViewHost: UIViewRepresentable {
  @ObservedObject var bridge: SystemVolumeBridge

  func makeUIView(context: Context) -> MPVolumeHostingView {
    MPVolumeHostingView(bridge: bridge)
  }

  func updateUIView(_ uiView: MPVolumeHostingView, context: Context) {
    uiView.bridge = bridge
  }
}

/// `UIViewRepresentable` dönüş tipi en az `internal` olmalı (`private` Swift derleyicisinde reddedilir).
final class MPVolumeHostingView: UIView {
  var bridge: SystemVolumeBridge
  private let volumeView: MPVolumeView
  private weak var attachedSlider: UISlider?

  init(bridge: SystemVolumeBridge) {
    self.bridge = bridge
    let v = MPVolumeView()
    v.alpha = 0.02
    v.showsVolumeSlider = true
    v.showsRouteButton = false
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
