import CoreVideo
import Foundation

/// Native stand-in for Flutter's `FlutterTexture`: supplies BGRA frames from mpv's render path.
@objc public protocol MPVPixelBufferProviding: NSObjectProtocol {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>?
}
