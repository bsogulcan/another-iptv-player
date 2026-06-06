import CoreGraphics
import CoreVideo
import OpenGLES
import UIKit

public final class TextureGLESContext {
  private let context: EAGLContext
  public let frameBuffer: GLuint
  public let texture: CVOpenGLESTexture
  public let pixelBuffer: CVPixelBuffer

  init?(
    context: EAGLContext,
    textureCache: CVOpenGLESTextureCache,
    size: CGSize
  ) {
    self.context = context

    for _ in 0 ... 3 {
      let pixelBuffer = OpenGLESHelpers.createPixelBuffer(size)
      let texture = OpenGLESHelpers.createTexture(
        textureCache,
        pixelBuffer,
        size
      )
      let frameBuffer = try? OpenGLESHelpers.createFrameBuffer(
        context: context,
        texture: texture,
        size: size
      )
      if frameBuffer != nil {
        self.pixelBuffer = pixelBuffer
        self.texture = texture
        self.frameBuffer = frameBuffer!
        return
      }
      OpenGLESHelpers.deletePixeBuffer(context, pixelBuffer)
      OpenGLESHelpers.deleteTexture(context, texture)
    }

    Log.error("TextureGLESContext", "unable to create a valid frameBuffer after 4 attempts")
    return nil
  }

  deinit {
    OpenGLESHelpers.deletePixeBuffer(context, pixelBuffer)
    OpenGLESHelpers.deleteTexture(context, texture)
    OpenGLESHelpers.deleteFrameBuffer(context, frameBuffer)
  }
}
