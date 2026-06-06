import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore

/// macOS varyantı (iOS NativeVideoOutput.swift'ten port).
///
/// **Önemli:** libmpv, render iş parçacığında `mpv_get_property` vb. çağrılmasını yasaklar; bu yüzden
/// video boyutu yalnızca `mpv` kuyruğunda okunur ve burada önbelleğe alınır (`refreshDecodedVideoSizeFromMpv`).
///
/// macOS port notu: iOS'taki `CADisplayLink(target:selector:)` macOS'ta yok ve `NSView.displayLink`
/// bir view referansı gerektirir (NativeVideoOutput'un yok). Pacing'i AVSampleBufferDisplayLayer'a
/// devredip mailbox + display link katmanını çıkardık; worker render edip onFrame'i doğrudan
/// çağırır. Layer `isReadyForMoreMediaData` ile geri basıncı yönetiyor.
public final class NativeVideoOutput: NSObject {
  /// Üçüncü argüman: yalnızca OpenGL FBO çıktısı için dikey çevirme (macOS SW path daima false).
  public typealias FrameCallback = (CVPixelBuffer, CGSize, Bool) -> Void
  public typealias SizeCallback = (CGSize) -> Void

  private let handle: OpaquePointer
  private let enableHardwareAcceleration: Bool
  private let onVideoSizeChange: SizeCallback?
  private let onFrame: FrameCallback
  private let worker = Worker()

  private let stateLock = NSLock()
  private var overrideWidth: Int64?
  private var overrideHeight: Int64?
  /// `mpv_wait_event` / komut kuyruğunda güncellenir; render worker buradan okur.
  private var mpvDerivedDisplaySize: CGSize = .zero

  private var texture: ResizableTextureProtocol?
  private var pipelineReady = false
  private var currentSize: CGSize = .zero
  private var disposed = false
  private var flipVerticalForOpenGL = false
  /// `TextureHW` / `TextureSW` içinde `mpv_render_context_create` bittikten sonra (worker kuyruğu).
  private let onPipelineReady: (() -> Void)?

  /// GL'den art arda `updateCallback` + mpv'den `refresh…` tek worker döngüsünde birleşsin (kuyruk şişmesin).
  private var pendingWorkerRender = false
  private var workerDrainRunning = false

  init(
    mpvHandle: OpaquePointer,
    configuration: VideoOutputConfiguration,
    onVideoSizeChange: SizeCallback?,
    onFrame: @escaping FrameCallback,
    onPipelineReady: (() -> Void)? = nil
  ) {
    self.handle = mpvHandle
    overrideWidth = configuration.width
    overrideHeight = configuration.height
    enableHardwareAcceleration = configuration.enableHardwareAcceleration
    self.onVideoSizeChange = onVideoSizeChange
    self.onFrame = onFrame
    self.onPipelineReady = onPipelineReady
    super.init()
    worker.enqueue { self._init() }
  }

  deinit {
    worker.cancel()
    disposed = true
  }

  /// Sadece **mpv API kuyruğundan** çağrılmalı (`WakeupHelper` veya `load` sonrası).
  public func refreshDecodedVideoSizeFromMpv() {
    let next = MPVHelpers.computeMpvDerivedDisplaySize(handle: handle)
    stateLock.lock()
    if next.width > 0, next.height > 0 {
      mpvDerivedDisplaySize = next
    }
    stateLock.unlock()
    scheduleWorkerRenderDrain()
  }

  func releaseRenderingResourcesSynchronously() {
    let sem = DispatchSemaphore(value: 0)
    worker.enqueue { [weak self] in
      guard let self else {
        sem.signal()
        return
      }
      self.disposed = true
      self.stateLock.lock()
      self.pendingWorkerRender = false
      self.workerDrainRunning = false
      self.stateLock.unlock()
      self.texture = nil
      self.pipelineReady = false
      sem.signal()
    }
    sem.wait()
  }

  public func setSize(width: Int64?, height: Int64?) {
    worker.enqueue {
      self.stateLock.lock()
      self.overrideWidth = width
      self.overrideHeight = height
      self.stateLock.unlock()
      self._updateCallback()
    }
  }

  private func _init() {
    Log.info("NativeVideoOutput", "enableHardwareAcceleration: \(enableHardwareAcceleration)")
    flipVerticalForOpenGL = false
    if enableHardwareAcceleration {
      // macOS HW: NSOpenGLContext + IOSurface-backed FBO
      texture = SafeResizableTexture(
        TextureHW(
          handle: handle,
          updateCallback: { [weak self] in
            guard let self else { return }
            self.updateCallback()
          }
        )
      )
    } else {
      texture = SafeResizableTexture(
        TextureSW(
          handle: handle,
          updateCallback: { [weak self] in
            guard let self else { return }
            self.updateCallback()
          }
        )
      )
    }

    pipelineReady = true
    onPipelineReady?()

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.onVideoSizeChange?(CGSize(width: 0, height: 0))
    }
  }

  public func updateCallback() {
    scheduleWorkerRenderDrain()
  }

  private func scheduleWorkerRenderDrain() {
    stateLock.lock()
    pendingWorkerRender = true
    if workerDrainRunning {
      stateLock.unlock()
      return
    }
    workerDrainRunning = true
    stateLock.unlock()
    worker.enqueue { [weak self] in
      self?.runWorkerRenderDrainLoop()
    }
  }

  private func runWorkerRenderDrainLoop() {
    while true {
      stateLock.lock()
      guard pendingWorkerRender else {
        workerDrainRunning = false
        stateLock.unlock()
        return
      }
      pendingWorkerRender = false
      stateLock.unlock()
      _updateCallback()
    }
  }

  private func effectiveVideoSize() -> CGSize {
    stateLock.lock()
    let intrinsic = mpvDerivedDisplaySize
    let ow = overrideWidth
    let oh = overrideHeight
    stateLock.unlock()

    if let w = ow, let h = oh, w > 0, h > 0 {
      return CGSize(width: Double(w), height: Double(h))
    }
    return intrinsic
  }

  private func _updateCallback() {
    guard pipelineReady, let texture else {
      MPVPlayerVideoLog.throttled("NativeOut.nopipe", first: 15, every: 0) {
        "pipelineReady=\(pipelineReady) textureMissing=\(self.texture == nil)"
      }
      return
    }

    let size = effectiveVideoSize()
    if size.width == 0 || size.height == 0 {
      stateLock.lock()
      let intr = mpvDerivedDisplaySize
      let oww = overrideWidth
      let ohh = overrideHeight
      stateLock.unlock()
      MPVPlayerVideoLog.throttled("NativeOut.size0", first: 50, every: 40) {
        "effectiveSize=\(size) intrinsic=\(intr.width)x\(intr.height) overrideW=\(String(describing: oww)) overrideH=\(String(describing: ohh))"
      }
      return
    }

    if currentSize != size {
      currentSize = size
      texture.resize(size)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.onVideoSizeChange?(size)
      }
    }

    if disposed { return }

    texture.render(size)
    guard let unmanaged = texture.copyPixelBuffer() else {
      MPVPlayerVideoLog.throttled("NativeOut.nopb", first: 30, every: 35) {
        "copyPixelBuffer nil (render sonrası current yok)"
      }
      return
    }
    let buffer = unmanaged.takeRetainedValue()
    onFrame(buffer, size, flipVerticalForOpenGL)
  }
}
