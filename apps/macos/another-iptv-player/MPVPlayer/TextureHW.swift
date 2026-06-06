import AppKit
import CoreVideo
import Foundation
import OpenGL.GL3

/// macOS HW render yolu — iOS `TextureHW.swift` portu.
/// NSOpenGLContext + IOSurface-backed FBO; mpv GPU shader'ları ile render eder,
/// pixel buffer GPU bellekte AVSampleBufferDisplayLayer'a sıfır-kopya iletilir.
public final class TextureHW: NSObject, ResizableTextureProtocol {
    public typealias UpdateCallback = () -> Void

    private let handle: OpaquePointer
    private let coalescer: UpdateCoalescer
    private let context: NSOpenGLContext
    private var renderContext: OpaquePointer?
    private var textureContexts = SwappableObjectManager<TextureGLContext>(
        objects: [],
        skipCheckArgs: true
    )

    init(handle: OpaquePointer, updateCallback: @escaping UpdateCallback) {
        self.handle = handle
        self.context = OpenGLHelpers.createContext()
        self.coalescer = UpdateCoalescer(callback: updateCallback)
        super.init()
        initMPV()
    }

    deinit {
        disposePixelBuffer()
        disposeMPV()
    }

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let tc = textureContexts.current else {
            MPVPlayerVideoLog.throttled("TextureHW.copy", first: 15, every: 0) {
                "current texture nil (henüz render yok veya triple-buffer boş)"
            }
            return nil
        }
        return Unmanaged.passRetained(tc.pixelBuffer)
    }

    private func initMPV() {
        context.makeCurrentContext()
        defer {
            OpenGLHelpers.checkError("initMPV")
            NSOpenGLContext.clearCurrentContext()
        }

        let api = UnsafeMutableRawPointer(
            mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
        )
        var procAddress = mpv_opengl_init_params(
            get_proc_address: { _, name in
                OpenGLHelpers.getProcAddress(name)
            },
            get_proc_address_ctx: nil
        )

        var params: [mpv_render_param] = withUnsafeMutableBytes(of: &procAddress) { ptr in
            [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
                mpv_render_param(
                    type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                    data: ptr.baseAddress.map { UnsafeMutableRawPointer($0) }
                ),
                mpv_render_param()
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
        context.makeCurrentContext()
        defer {
            OpenGLHelpers.checkError("disposeMPV")
            NSOpenGLContext.clearCurrentContext()
        }
        mpv_render_context_set_update_callback(ctx, nil, nil)
        mpv_render_context_free(ctx)
        renderContext = nil
    }

    public func resize(_ size: CGSize) {
        if size.width == 0 || size.height == 0 { return }
        Log.info("TextureHW", "(macOS) resize \(Int(size.width))x\(Int(size.height))")
        createPixelBuffer(size)
    }

    private func createPixelBuffer(_ size: CGSize) {
        disposePixelBuffer()
        let contexts = (0 ..< 3).compactMap { _ in
            TextureGLContext(context: context, size: size)
        }
        if contexts.isEmpty {
            Log.error("TextureHW", "(macOS) hiç TextureGLContext oluşturulamadı (\(Int(size.width))x\(Int(size.height)))")
            return
        }
        if contexts.count < 3 {
            Log.error("TextureHW", "(macOS) \(contexts.count)/3 context oluşturulabildi")
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
        guard let tc = textureContexts.nextAvailable() else {
            MPVPlayerVideoLog.always(
                "TextureHW.render",
                "nextAvailable nil — tüm FBO’lar meşgul (üçlü tampon tükendi)"
            )
            return
        }

        context.makeCurrentContext()
        defer {
            OpenGLHelpers.checkError("render")
            NSOpenGLContext.clearCurrentContext()
        }

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), tc.frameBuffer)
        defer {
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        }

        // mpv glViewport durumunu yönetmiyor (render_gl.h); FBO ile uyumlu olmalı.
        let w = max(1, Int32(size.width))
        let h = max(1, Int32(size.height))
        glDisable(GLenum(GL_SCISSOR_TEST))
        glViewport(0, 0, GLsizei(w), GLsizei(h))

        var fbo = mpv_opengl_fbo(
            fbo: Int32(tc.frameBuffer),
            w: w,
            h: h,
            internal_format: 0
        )
        let fboPtr = withUnsafeMutablePointer(to: &fbo) { $0 }

        var params: [mpv_render_param] = [
            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
            mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
        ]

        let updateFlags = mpv_render_context_update(rctx)
        let renderErr = mpv_render_context_render(rctx, &params)
        if renderErr < 0 {
            MPVPlayerVideoLog.always(
                "TextureHW.render",
                "mpv_render_context_render: \(String(cString: mpv_error_string(renderErr))) (\(renderErr))"
            )
        } else {
            mpv_render_context_report_swap(rctx)
        }

        // glFlush IOSurface tarafına GPU komutlarını yollar; AVSampleBufferDisplayLayer
        // pixel buffer'ı okumadan önce GPU işin bitirmiş olur. glFinish stall yapar,
        // kullanmıyoruz çünkü display layer kendi GPU senkronizasyonunu yapıyor.
        glFlush()

        MPVPlayerVideoLog.throttled("TextureHW.renderOK", first: 15, every: 120) {
            "fbo=\(tc.frameBuffer) viewport \(w)x\(h) updateFlags=\(updateFlags) mpvRender=\(renderErr)"
        }

        textureContexts.pushAsReady(tc)
    }
}
