import CoreVideo
import Foundation
import OpenGLES
import UIKit

/// OpenGL ES → CVPixelBuffer path (same as MPVPlayer iOS `TextureHW.swift`).
public final class TextureHW: NSObject, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  private let handle: OpaquePointer
  private let coalescer: UpdateCoalescer
  private let context: EAGLContext
  private let textureCache: CVOpenGLESTextureCache
  private var renderContext: OpaquePointer?
  private var textureContexts = SwappableObjectManager<TextureGLESContext>(
    objects: [],
    skipCheckArgs: true
  )

  init(
    handle: OpaquePointer,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.context = OpenGLESHelpers.createContext()
    self.textureCache = OpenGLESHelpers.createTextureCache(context)
    self.coalescer = UpdateCoalescer(callback: updateCallback)
    super.init()
    self.initMPV()
  }

  deinit {
    disposePixelBuffer()
    disposeMPV()
    OpenGLESHelpers.deleteTextureCache(textureCache)
    OpenGLESHelpers.deleteContext(context)
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let textureContext = textureContexts.current else {
      MPVPlayerVideoLog.throttled("TextureHW.copy", first: 15, every: 0) {
        "current texture nil (henüz render yok veya triple-buffer boş)"
      }
      return nil
    }
    return Unmanaged.passRetained(textureContext.pixelBuffer)
  }

  private func initMPV() {
    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("initMPV")
      EAGLContext.setCurrent(nil)
    }

    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
    )
    var procAddress = mpv_opengl_init_params(
      get_proc_address: { ctx, name in
        TextureHW.getProcAddress(ctx, name)
      },
      get_proc_address_ctx: nil
    )

    var params: [mpv_render_param] = withUnsafeMutableBytes(of: &procAddress) {
      procAddress in
      [
        mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
        mpv_render_param(
          type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
          data: procAddress.baseAddress.map {
            UnsafeMutableRawPointer($0)
          }
        ),
        mpv_render_param(),
      ]
    }

    MPVHelpers.checkError(
      mpv_render_context_create(&renderContext, handle, &params)
    )

    mpv_render_context_set_update_callback(
      renderContext,
      { ctx in
        let that = unsafeBitCast(ctx, to: TextureHW.self)
        that.coalescer.schedule()
      },
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
  }

  private func disposeMPV() {
    guard let ctx = renderContext else { return }
    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("disposeMPV")
      EAGLContext.setCurrent(nil)
    }
    mpv_render_context_set_update_callback(ctx, nil, nil)
    mpv_render_context_free(ctx)
    renderContext = nil
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 { return }
    Log.info("TextureHW", "resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()
    // Eski boyuttan kalan stale texture cache entry'leri temizle; bu olmadan yeniden
    // boyutlandırma sırasında renk bozulması oluşabilir.
    CVOpenGLESTextureCacheFlush(textureCache, 0)
    let contexts = (0 ..< 3).compactMap { _ in
      TextureGLESContext(context: context, textureCache: textureCache, size: size)
    }
    if contexts.isEmpty {
      Log.error("TextureHW", "createPixelBuffer: hiç TextureGLESContext oluşturulamadı (\(Int(size.width))x\(Int(size.height)))")
      return
    }
    if contexts.count < 3 {
      Log.error("TextureHW", "createPixelBuffer: \(contexts.count)/3 context oluşturulabildi")
    }
    textureContexts.reinit(objects: contexts, skipCheckArgs: true)
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    guard let rctx = renderContext else {
      MPVPlayerVideoLog.throttled("TextureHW.render", first: 5, every: 0) { "renderContext nil" }
      return
    }
    guard let textureContext = textureContexts.nextAvailable() else {
      MPVPlayerVideoLog.always(
        "TextureHW.render",
        "nextAvailable nil — tüm FBO’lar meşgul (üçlü tampon tükendi); bu normalde kısa sürer"
      )
      return
    }

    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("render")
      EAGLContext.setCurrent(nil)
    }

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), textureContext.frameBuffer)
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    // mpv, glViewport durumunu yönetmez (render_gl.h). FBO boyutu ile eşleşmezse kare boş kalır.
    let w = max(1, Int32(size.width))
    let h = max(1, Int32(size.height))
    glDisable(GLenum(GL_SCISSOR_TEST))
    glViewport(0, 0, GLsizei(w), GLsizei(h))

    var fbo = mpv_opengl_fbo(
      fbo: Int32(textureContext.frameBuffer),
      w: w,
      h: h,
      internal_format: 0
    )
    let fboPtr = withUnsafeMutablePointer(to: &fbo) { $0 }

    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]

    let updateFlags = mpv_render_context_update(rctx)
    let renderErr = mpv_render_context_render(rctx, &params)
    if renderErr < 0 {
      MPVPlayerVideoLog.always(
        "TextureHW.render",
        "mpv_render_context_render failed: \(String(cString: mpv_error_string(renderErr))) (\(renderErr))"
      )
    } else {
      // mpv’nin A/V ve kare hızı tahmini için (render_gl.h); yoksa oynatma “sert” hissedebilir.
      mpv_render_context_report_swap(rctx)
    }
    let glErr = glGetError()
    if glErr != GL_NO_ERROR {
      MPVPlayerVideoLog.throttled("TextureHW.gl", first: 20, every: 30) {
        "glGetError after render: \(glErr)"
      }
    }

    glFinish()
    CVOpenGLESTextureCacheFlush(textureCache, 0)

    MPVPlayerVideoLog.throttled("TextureHW.renderOK", first: 15, every: 120) {
      "fbo=\(textureContext.frameBuffer) viewport \(w)x\(h) updateFlags=\(updateFlags) mpvRender=\(renderErr) \(MPVPlayerVideoLog.pixelBufferSummary(textureContext.pixelBuffer))"
    }

    textureContexts.pushAsReady(textureContext)
  }

  private static func getProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<Int8>?
  ) -> UnsafeMutableRawPointer? {
    let symbol: CFString = CFStringCreateWithCString(
      kCFAllocatorDefault,
      name,
      kCFStringEncodingASCII
    )
    let indentifier = CFBundleGetBundleWithIdentifier(
      "com.apple.opengles" as CFString
    )
    let addr = CFBundleGetFunctionPointerForName(indentifier, symbol)
    if addr == nil {
      let symName = name.map { String(cString: $0) } ?? "<nil>"
      Log.error("TextureHW", "Cannot get OpenGLES function pointer for \(symName)")
    }
    return addr
  }
}
