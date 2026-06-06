import CoreVideo
import SwiftUI
import UIKit

/// SwiftUI köprüsü: `MPVPlayer` karelerini ekrana basar.
public struct MPVPlayerVideoSurface: UIViewRepresentable {
  @ObservedObject var player: MPVPlayer

  public init(player: MPVPlayer) {
    self.player = player
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  public func makeUIView(context: Context) -> PixelBufferDisplayView {
    let view = PixelBufferDisplayView()
    context.coordinator.attachIfNeeded(player: player, view: view)
    return view
  }

  public func updateUIView(_ uiView: PixelBufferDisplayView, context: Context) {
    context.coordinator.attachIfNeeded(player: player, view: uiView)
  }

  public final class Coordinator {
    private weak var boundPlayer: MPVPlayer?
    private var didConfigure = false

    func attachIfNeeded(player: MPVPlayer, view: PixelBufferDisplayView) {
      if didConfigure, boundPlayer === player { return }
      boundPlayer = player
      didConfigure = true
      player.configure(
        enableHardwareAcceleration: true,
        onVideoSizeChange: { _ in },
        onFrame: { [weak view] buffer, _, flip in
          guard let view else {
            MPVPlayerVideoLog.throttled("Surface.weakView", first: 25, every: 0) {
              "onFrame: UIView nil (Representable yaşam döngüsü) — kare atlandı"
            }
            return
          }
          view.enqueuePixelBuffer(buffer, flipVerticalForOpenGL: flip)
        }
      )
    }
  }
}
