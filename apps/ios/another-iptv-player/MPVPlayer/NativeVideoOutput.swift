import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import UIKit

/// SwiftUI/native counterpart of MPVPlayer `VideoOutput.swift` (no Flutter texture registry).
///
/// **Önemli:** libmpv, render iş parçacığında `mpv_get_property` vb. çağrılmasını yasaklar; bu yüzden
/// video boyutu yalnızca `mpv` kuyruğunda okunur ve burada önbelleğe alınır (`refreshDecodedVideoSizeFromMpv`).
/// Worker → tek `CVPixelBuffer` tutar; ana kuyruk yalnızca `CADisplayLink` ile (ekran yenilemesiyle) tüketir.
/// Her kare için `main.async` birikmesi PiP / arka plan geçişinde teklemeye yol açıyordu.
private final class LatestFrameMailbox {
  private let lock = NSLock()
  private var buffer: CVPixelBuffer?
  private var size: CGSize = .zero
  private var flipVertical = false

  func replace(with buffer: CVPixelBuffer, size: CGSize, flipVertical: Bool) {
    lock.lock()
    self.buffer = buffer
    self.size = size
    self.flipVertical = flipVertical
    lock.unlock()
  }

  func take() -> (CVPixelBuffer, CGSize, Bool)? {
    lock.lock()
    defer { lock.unlock() }
    guard let b = buffer else { return nil }
    buffer = nil
    return (b, size, flipVertical)
  }

  func drain() {
    lock.lock()
    buffer = nil
    lock.unlock()
  }
}

private final class FrameLinkProxy: NSObject {
  weak var owner: NativeVideoOutput?
  @objc func tick(_ link: CADisplayLink) {
    owner?.deliverLatestFrameIfAny()
  }
}

public final class NativeVideoOutput: NSObject {
  /// Üçüncü argüman: yalnızca OpenGL FBO (`TextureHW`) çıktısı için dikey çevirme (CI ile gösterim).
  public typealias FrameCallback = (CVPixelBuffer, CGSize, Bool) -> Void
  public typealias SizeCallback = (CGSize) -> Void

  private static let isSimulator: Bool = {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }()

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

  private let mailbox = LatestFrameMailbox()
  private let frameLinkProxy = FrameLinkProxy()
  private let linkLock = NSLock()
  private var displayLink: CADisplayLink?
  /// GL’den art arda `updateCallback` + mpv’den `refresh…` tek worker döngüsünde birleşsin (kuyruk şişmesin).
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
    frameLinkProxy.owner = self
    worker.enqueue { self._init() }
  }

  deinit {
    worker.cancel()
    disposed = true
    mailbox.drain()
    linkLock.lock()
    let link = displayLink
    displayLink = nil
    linkLock.unlock()
    if let link {
      DispatchQueue.main.async {
        link.invalidate()
      }
    }
  }

  /// Sadece **mpv API kuyruğundan** çağrılmalı (`WakeupHelper` veya `load` sonrası).
  public func refreshDecodedVideoSizeFromMpv() {
    let next = MPVHelpers.computeMpvDerivedDisplaySize(handle: handle)
    stateLock.lock()
    // Aspect değişimi/reconfig sırasında mpv kısa süre 0x0 döndürebiliyor.
    // 0x0'ı cache'e yazarsak render döngüsü "size==0" durumunda kalıp siyah ekrana düşebiliyor.
    // Bu yüzden yalnızca geçerli (non-zero) boyutu cache'e uygula; mevcut boyutu koru.
    if next.width > 0, next.height > 0 {
      mpvDerivedDisplaySize = next
    }
    stateLock.unlock()
    scheduleWorkerRenderDrain()
  }

  /// `MPVPlayer.dispose` (mpv API kuyruğu): `Worker` hâlâ `texture.render` çalıştırırken
  /// `NativeVideoOutput` deinit olursa `TextureHW`/`TextureSW` ile çarpışır. Önce işçi
  /// kuyruğunda GL / yazılım render bağlamını serbest bırak.
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
      self.mailbox.drain()
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
    let useHW = Self.isSimulator ? false : enableHardwareAcceleration
    Log.info("NativeVideoOutput", "enableHardwareAcceleration: \(useHW)")
    if Self.isSimulator {
      Log.info(
        "NativeVideoOutput",
        "hardware rendering disabled in Simulator (same policy as MPVPlayer)."
      )
    }

    if useHW {
      // `vo=libmpv` + GLES FBO çıktısı UIImageView/CI ile doğru yönde; ekstra dikey çevirme ters gösterir.
      flipVerticalForOpenGL = false
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
      flipVerticalForOpenGL = false
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
      self.installDisplayLinkIfNeeded()
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
    mailbox.replace(with: buffer, size: size, flipVertical: flipVerticalForOpenGL)
  }

  private func installDisplayLinkIfNeeded() {
    assert(Thread.isMainThread)
    linkLock.lock()
    defer { linkLock.unlock() }
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: frameLinkProxy, selector: #selector(FrameLinkProxy.tick(_:)))
    link.add(to: .main, forMode: .common)
    if #available(iOS 15.0, *) {
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
    }
    displayLink = link
  }

  fileprivate func deliverLatestFrameIfAny() {
    guard !disposed else { return }
    guard let triple = mailbox.take() else { return }
    let (buffer, size, flip) = triple
    onFrame(buffer, size, flip)
  }
}
