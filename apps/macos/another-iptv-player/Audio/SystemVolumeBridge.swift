import AppKit
import Combine
import CoreAudio
import SwiftUI

/// macOS varyantı: sistem default output cihazının ses seviyesini okur/yazar.
/// iOS'taki `MPVolumeView` köprüsünün yerini tutar; CoreAudio HAL üzerinden çalışır.
final class SystemVolumeBridge: NSObject, ObservableObject {
  @Published private(set) var outputVolume: Float = 0

  private var deviceID: AudioDeviceID = kAudioObjectUnknown
  private var listenerInstalled = false

  override init() {
    super.init()
    refreshDevice()
    outputVolume = readVolume()
    installListenerIfNeeded()
  }

  deinit {
    removeListenerIfNeeded()
  }

  func setOutputVolume(_ value: Float) {
    let v = min(max(value, 0), 1)
    writeVolume(v)
    if outputVolume != v {
      DispatchQueue.main.async { [weak self] in
        self?.outputVolume = v
      }
    }
  }

  // MARK: - CoreAudio plumbing

  private func refreshDevice() {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dev: AudioDeviceID = kAudioObjectUnknown
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &addr, 0, nil, &size, &dev
    )
    if status == noErr {
      deviceID = dev
    }
  }

  private func volumeAddress() -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyVolumeScalar,
      mScope: kAudioObjectPropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private func readVolume() -> Float {
    guard deviceID != kAudioObjectUnknown else { return 0 }
    var addr = volumeAddress()
    var value: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
    if status != noErr { return outputVolume }
    return value
  }

  private func writeVolume(_ value: Float) {
    guard deviceID != kAudioObjectUnknown else { return }
    var addr = volumeAddress()
    var v: Float32 = value
    let size = UInt32(MemoryLayout<Float32>.size)
    _ = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &v)
  }

  private func installListenerIfNeeded() {
    guard !listenerInstalled, deviceID != kAudioObjectUnknown else { return }
    var addr = volumeAddress()
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self else { return }
      let v = self.readVolume()
      DispatchQueue.main.async {
        if self.outputVolume != v {
          self.outputVolume = v
        }
      }
    }
    let status = AudioObjectAddPropertyListenerBlock(deviceID, &addr, .main, block)
    listenerInstalled = (status == noErr)
  }

  private func removeListenerIfNeeded() {
    // CoreAudio block listener'ları için aynı block referansı gerekir; basitlik adına
    // process sonunda OS temizler. Player kapanışında deinit yeterli.
  }
}
