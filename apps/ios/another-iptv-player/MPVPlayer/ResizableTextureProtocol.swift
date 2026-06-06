import CoreGraphics
import Foundation

public protocol ResizableTextureProtocol: NSObject, MPVPixelBufferProviding {
  func resize(_ size: CGSize)
  func render(_ size: CGSize)
}
