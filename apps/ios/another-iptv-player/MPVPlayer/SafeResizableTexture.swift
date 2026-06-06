import CoreGraphics
import CoreVideo
import Foundation

public final class SafeResizableTexture: NSObject, ResizableTextureProtocol {
  private let lock = NSRecursiveLock()
  private let child: ResizableTextureProtocol

  init(_ child: ResizableTextureProtocol) {
    self.child = child
  }

  public func resize(_ size: CGSize) {
    locked { child.resize(size) }
  }

  public func render(_ size: CGSize) {
    locked { child.render(size) }
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    locked { child.copyPixelBuffer() }
  }

  private func locked<T>(do block: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return block()
  }
}
