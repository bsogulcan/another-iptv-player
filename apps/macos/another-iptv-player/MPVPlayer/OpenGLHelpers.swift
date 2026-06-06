import AppKit
import Foundation
import OpenGL.GL3

/// macOS OpenGL yardımcıları — iOS `OpenGLESHelpers` karşılığı.
/// NSOpenGLContext Core Profile 3.2 ile mpv render API için offscreen FBO render eder.
/// IOSurface ile sıfır-kopya CVPixelBuffer paylaşımı yapılır.
enum OpenGLHelpers {
    static func createContext() -> NSOpenGLContext {
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFAAllowOfflineRenderers),
            UInt32(NSOpenGLPFAColorSize), 32,
            UInt32(NSOpenGLPFADepthSize), 0,
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]
        // macOS 14+ desteklenen tüm donanımda OpenGL 3.2 Core mevcut; aşağıdaki guard'lar
        // pratikte gerçekleşmez. Yine de net log + açıklayıcı mesajla son çare.
        guard let pf = NSOpenGLPixelFormat(attributes: attrs) else {
            Log.error("OpenGLHelpers", "NSOpenGLPixelFormat oluşturulamadı — bu sürücüde HW render imkânsız")
            fatalError("OpenGL 3.2 Core pixel format yok (sürücü/donanım): app HW render edemez")
        }
        guard let ctx = NSOpenGLContext(format: pf, share: nil) else {
            Log.error("OpenGLHelpers", "NSOpenGLContext oluşturulamadı (pixel format vardı)")
            fatalError("OpenGL context yaratılamadı (sistem GPU kaynağı yok): app HW render edemez")
        }
        return ctx
    }

    static func checkError(_ label: String) {
        let err = glGetError()
        if err != GL_NO_ERROR {
            Log.error("OpenGLHelpers", "glError 0x\(String(err, radix: 16)) at \(label)")
        }
    }

    /// mpv `get_proc_address` için: OpenGL.framework'ten sembol çözümle.
    static func getProcAddress(_ name: UnsafePointer<Int8>?) -> UnsafeMutableRawPointer? {
        guard let name else { return nil }
        let symbol: CFString = CFStringCreateWithCString(
            kCFAllocatorDefault, name, kCFStringEncodingASCII
        )
        // macOS modern OpenGL bundle id; eski "com.apple.opengles" iOS'a özeldi.
        guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else {
            Log.error("OpenGLHelpers", "com.apple.opengl bundle bulunamadı")
            return nil
        }
        return CFBundleGetFunctionPointerForName(bundle, symbol)
    }
}
