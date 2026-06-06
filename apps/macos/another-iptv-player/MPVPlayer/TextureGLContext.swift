import AppKit
import CoreVideo
import Foundation
import IOSurface
import OpenGL.GL3

/// IOSurface-backed CVPixelBuffer + OpenGL texture + FBO üçlüsü. mpv FBO'ya render eder,
/// IOSurface GPU bellekte kalır, AVSampleBufferDisplayLayer aynı IOSurface'i zero-copy okur.
///
/// macOS'ta CVOpenGLTextureCache deprecated; modern yol `CGLTexImageIOSurface2D` ile
/// manuel `GL_TEXTURE_RECTANGLE` bağlamaktır. mpv FBO render edebilir, gravity-aware
/// display layer ise IOSurface'in pixel formatından okur.
public final class TextureGLContext {
    public let pixelBuffer: CVPixelBuffer
    public let texture: GLuint
    public let frameBuffer: GLuint
    public let size: CGSize

    private let context: NSOpenGLContext

    init?(context: NSOpenGLContext, size: CGSize) {
        self.context = context
        self.size = size

        let w = max(1, Int(size.width))
        let h = max(1, Int(size.height))

        // 1) IOSurface (BGRA, GPU bellek). Bellek baskısında / sürücü hatasında nil dönebilir.
        let surfaceProps: [IOSurfacePropertyKey: Any] = [
            .width: w,
            .height: h,
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        guard let surface = IOSurface(properties: surfaceProps) else {
            Log.error("TextureGLContext", "IOSurface oluşturulamadı (\(w)x\(h)) — GPU memory baskısı?")
            return nil
        }

        // 2) IOSurface'i wrap eden CVPixelBuffer — Metal compat + GL compat anahtarları.
        // CVPixelBufferCreateWithIOSurface Unmanaged döner; takeRetainedValue ile alıyoruz.
        var pbUnmanaged: Unmanaged<CVPixelBuffer>?
        let pbAttrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferOpenGLCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ]
        let surfaceRef = unsafeBitCast(surface, to: IOSurfaceRef.self)
        let cvret = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surfaceRef,
            pbAttrs as CFDictionary,
            &pbUnmanaged
        )
        guard cvret == kCVReturnSuccess, let pixelBuffer = pbUnmanaged?.takeRetainedValue() else {
            Log.error("TextureGLContext", "CVPixelBufferCreateWithIOSurface başarısız (\(cvret))")
            return nil
        }
        self.pixelBuffer = pixelBuffer

        // 3) OpenGL bağlantısı — GL_TEXTURE_RECTANGLE IOSurface ile zorunlu
        context.makeCurrentContext()
        defer { NSOpenGLContext.clearCurrentContext() }

        var tex: GLuint = 0
        glGenTextures(1, &tex)
        glBindTexture(GLenum(GL_TEXTURE_RECTANGLE), tex)
        glTexParameteri(GLenum(GL_TEXTURE_RECTANGLE), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_RECTANGLE), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_RECTANGLE), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_RECTANGLE), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)

        // CGLTexImageIOSurface2D ile IOSurface'i texture'a bağla — bu sayede
        // GL render → IOSurface → CVPixelBuffer arasında bellek paylaşılır.
        let cgl: CGLContextObj = context.cglContextObj!
        let cglErr = CGLTexImageIOSurface2D(
            cgl,
            GLenum(GL_TEXTURE_RECTANGLE),
            GLenum(GL_RGBA),
            GLsizei(w),
            GLsizei(h),
            GLenum(GL_BGRA),
            GLenum(GL_UNSIGNED_INT_8_8_8_8_REV),
            surfaceRef,
            0
        )
        if cglErr != kCGLNoError {
            Log.error("TextureGLContext", "CGLTexImageIOSurface2D hata \(cglErr)")
        }
        self.texture = tex

        // 4) FBO + texture attachment
        var fbo: GLuint = 0
        glGenFramebuffers(1, &fbo)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_TEXTURE_RECTANGLE),
            tex,
            0
        )
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GL_FRAMEBUFFER_COMPLETE {
            Log.error("TextureGLContext", "FBO tamamlanmadı status=0x\(String(status, radix: 16))")
        }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        self.frameBuffer = fbo

        OpenGLHelpers.checkError("TextureGLContext.init")
    }

    deinit {
        context.makeCurrentContext()
        var fb = frameBuffer
        glDeleteFramebuffers(1, &fb)
        var tx = texture
        glDeleteTextures(1, &tx)
        NSOpenGLContext.clearCurrentContext()
    }
}
