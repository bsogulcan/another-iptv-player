import AppKit
import AVFoundation
import CoreVideo
import SwiftUI

/// SwiftUI köprüsü (macOS NSViewRepresentable): `MPVPlayer` karelerini ekrana basar.
/// Yeni Metal display path'i: MetalVideoView (CAMetalLayer + Metal shader).
public struct MPVPlayerVideoSurface: NSViewRepresentable {
  @ObservedObject var player: MPVPlayer
  var videoGravity: AVLayerVideoGravity

  public init(player: MPVPlayer, videoGravity: AVLayerVideoGravity = .resizeAspect) {
    self.player = player
    self.videoGravity = videoGravity
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  public func makeNSView(context: Context) -> MetalVideoView {
    let view = MetalVideoView()
    view.videoGravity = videoGravity
    context.coordinator.attachIfNeeded(player: player, view: view)
    return view
  }

  public func updateNSView(_ nsView: MetalVideoView, context: Context) {
    nsView.videoGravity = videoGravity
    context.coordinator.attachIfNeeded(player: player, view: nsView)
  }

  public final class Coordinator {
    private weak var boundPlayer: MPVPlayer?
    private var didConfigure = false

    func attachIfNeeded(player: MPVPlayer, view: MetalVideoView) {
      if didConfigure, boundPlayer === player { return }
      boundPlayer = player
      didConfigure = true
      player.configure(
        enableHardwareAcceleration: true,
        onVideoSizeChange: { _ in },
        onFrame: { [weak view] buffer, _, flip in
          guard let view else {
            MPVPlayerVideoLog.throttled("Surface.weakView", first: 25, every: 0) {
              "onFrame: MetalVideoView nil (Representable yaşam döngüsü) — kare atlandı"
            }
            return
          }
          view.enqueuePixelBuffer(buffer, flipVerticalForOpenGL: flip)
        }
      )
    }
  }
}
