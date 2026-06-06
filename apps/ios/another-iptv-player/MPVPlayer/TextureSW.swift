import CoreGraphics
import CoreVideo
import Foundation
import UIKit

/// Software render path (simulator / GLES fallback), matching MPVPlayer `TextureSW.swift`.
public final class TextureSW: NSObject, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  private let handle: OpaquePointer
  private let coalescer: UpdateCoalescer
  private var renderContext: OpaquePointer?
  private var textureContexts = SwappableObjectManager<TextureSWContext>(
    objects: [],
    skipCheckArgs: true
  )

  init(
    handle: OpaquePointer,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.coalescer = UpdateCoalescer(callback: updateCallback)
    super.init()
    // Worker iş parçacığında senkron: `NativeVideoOutput` resize/render bu kuyrukta;
    // main.async gecikmesi `renderContext == nil` iken `render` çağrılmasına yol açabiliyordu.
    initMPV()
  }

  deinit {
    disposePixelBuffer()
    disposeMPV()
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let textureContext = textureContexts.current else {
      MPVPlayerVideoLog.throttled("TextureSW.copy", first: 15, every: 0) {
        "current nil"
      }
      return nil
    }
    return Unmanaged.passRetained(textureContext.pixelBuffer)
  }

  private func initMPV() {
    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_SW as NSString).utf8String
    )
    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]

    MPVHelpers.checkError(
      mpv_render_context_create(&renderContext, handle, &params)
    )

    mpv_render_context_set_update_callback(
      renderContext,
      { ctx in
        let that = unsafeBitCast(ctx, to: TextureSW.self)
        that.coalescer.schedule()
      },
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
  }

  private func disposeMPV() {
    guard let ctx = renderContext else { return }
    mpv_render_context_set_update_callback(ctx, nil, nil)
    mpv_render_context_free(ctx)
    renderContext = nil
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 { return }
    Log.info("TextureSW", "resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()
    textureContexts.reinit(
      objects: [
        TextureSWContext(size: size),
        TextureSWContext(size: size),
        TextureSWContext(size: size),
      ],
      skipCheckArgs: true
    )
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    guard let ctx = renderContext else {
      MPVPlayerVideoLog.throttled("TextureSW.render", first: 5, every: 0) { "renderContext nil" }
      return
    }
    guard let textureContext = textureContexts.nextAvailable() else {
      MPVPlayerVideoLog.always("TextureSW.render", "nextAvailable nil (buffer tükendi)")
      return
    }

    CVPixelBufferLockBaseAddress(
      textureContext.pixelBuffer,
      CVPixelBufferLockFlags(rawValue: 0)
    )
    defer {
      CVPixelBufferUnlockBaseAddress(
        textureContext.pixelBuffer,
        CVPixelBufferLockFlags(rawValue: 0)
      )
    }

    var ssize: [Int32] = [Int32(size.width), Int32(size.height)]
    let format: String = "bgr0"
    var pitch: Int = CVPixelBufferGetBytesPerRow(textureContext.pixelBuffer)
    guard let buffer = CVPixelBufferGetBaseAddress(textureContext.pixelBuffer) else {
      MPVPlayerVideoLog.always("TextureSW.render", "pixelBuffer base address nil — render atlandı")
      return
    }

    let ssizePtr = ssize.withUnsafeMutableBytes {
      $0.baseAddress?.assumingMemoryBound(to: Int32.self)
    }
    let formatPtr = UnsafeMutablePointer(
      mutating: (format as NSString).utf8String
    )
    let pitchPtr = withUnsafeMutablePointer(to: &pitch) { $0 }
    let bufferPtr = buffer.assumingMemoryBound(to: UInt8.self)

    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: ssizePtr),
      mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: formatPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: pitchPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: bufferPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]

    _ = mpv_render_context_update(ctx)
    let renderErr = mpv_render_context_render(ctx, &params)
    if renderErr < 0 {
      MPVPlayerVideoLog.always(
        "TextureSW.render",
        "mpv_render_context_render: \(String(cString: mpv_error_string(renderErr))) (\(renderErr))"
      )
    } else {
      mpv_render_context_report_swap(ctx)
    }
    MPVPlayerVideoLog.throttled("TextureSW.renderOK", first: 15, every: 120) {
      "sw \(Int(size.width))x\(Int(size.height)) mpv=\(renderErr) \(MPVPlayerVideoLog.pixelBufferSummary(textureContext.pixelBuffer))"
    }
    textureContexts.pushAsReady(textureContext)
  }
}
