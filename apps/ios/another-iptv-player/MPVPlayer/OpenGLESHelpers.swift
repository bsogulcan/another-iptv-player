import OpenGLES
import UIKit

public enum OpenGLESHelpers {
  public static func createContext() -> EAGLContext {
    let context = EAGLContext(api: .openGLES3)
    return context!
  }

  public static func createTextureCache(
    _ context: EAGLContext
  ) -> CVOpenGLESTextureCache {
    var textureCache: CVOpenGLESTextureCache?
    let cvret: CVReturn = CVOpenGLESTextureCacheCreate(
      kCFAllocatorDefault,
      nil,
      context,
      nil,
      &textureCache
    )
    assert(cvret == kCVReturnSuccess, "CVOpenGLESTextureCacheCreate")
    return textureCache!
  }

  public static func createPixelBuffer(_ size: CGSize) -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attrs =
      [
        kCVPixelBufferMetalCompatibilityKey: true
      ] as CFDictionary

    let cvret: CVReturn = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32BGRA,
      attrs,
      &pixelBuffer
    )
    assert(cvret == kCVReturnSuccess, "CVPixelBufferCreate")
    return pixelBuffer!
  }

  public static func createTexture(
    _ textureCache: CVOpenGLESTextureCache,
    _ pixelBuffer: CVPixelBuffer,
    _ size: CGSize
  ) -> CVOpenGLESTexture {
    var texture: CVOpenGLESTexture?
    let cvret: CVReturn = CVOpenGLESTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      textureCache,
      pixelBuffer,
      nil,
      GLenum(GL_TEXTURE_2D),
      GL_RGBA,
      GLsizei(size.width),
      GLsizei(size.height),
      GLenum(GL_BGRA),
      GLenum(GL_UNSIGNED_BYTE),
      0,
      &texture
    )
    assert(
      cvret == kCVReturnSuccess,
      "CVOpenGLESTextureCacheCreateTextureFromImage"
    )
    return texture!
  }

  public enum FrameBufferError: Error {
    case status(status: GLuint)
  }

  public static func createFrameBuffer(
    context: EAGLContext,
    texture: CVOpenGLESTexture,
    size: CGSize
  ) throws -> GLuint {
    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("createFrameBuffer")
      EAGLContext.setCurrent(nil)
    }

    let textureName: GLuint = CVOpenGLESTextureGetName(texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), textureName)
    defer {
      glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    }

    var frameBuffer: GLuint = 0
    glGenFramebuffers(1, &frameBuffer)
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    glFramebufferTexture2D(
      GLenum(GL_FRAMEBUFFER),
      GLenum(GL_COLOR_ATTACHMENT0),
      GLenum(GL_TEXTURE_2D),
      textureName,
      0
    )

    let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    if status != GLenum(GL_FRAMEBUFFER_COMPLETE) {
      glDeleteFramebuffers(1, &frameBuffer)
      throw OpenGLESHelpers.FrameBufferError.status(status: status)
    }

    return frameBuffer
  }

  public static func deleteContext(_ context: EAGLContext) {
    // Release function for EAGLContext not found (MPVPlayer comment).
  }

  public static func deleteTextureCache(_ textureCache: CVOpenGLESTextureCache) {
    CVOpenGLESTextureCacheFlush(textureCache, 0)
  }

  public static func deletePixeBuffer(
    _ context: EAGLContext,
    _ pixelBuffer: CVPixelBuffer
  ) {}

  public static func deleteTexture(
    _ context: EAGLContext,
    _ texture: CVOpenGLESTexture
  ) {
    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("deleteTexture")
      EAGLContext.setCurrent(nil)
    }
    var textureName: GLuint = CVOpenGLESTextureGetName(texture)
    glDeleteTextures(1, &textureName)
  }

  public static func deleteFrameBuffer(
    _ context: EAGLContext,
    _ frameBuffer: GLuint
  ) {
    EAGLContext.setCurrent(context)
    defer {
      OpenGLESHelpers.checkError("deleteFrameBuffer")
      EAGLContext.setCurrent(nil)
    }
    var frameBuffer = frameBuffer
    glDeleteFramebuffers(1, &frameBuffer)
  }

  public static func checkError(_ message: String) {
    let error = glGetError()
    if error == GL_NO_ERROR { return }
    Log.error("OpenGLESHelpers", "\(message): \(error)")
  }
}
