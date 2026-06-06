import AppKit
import Nuke
import SwiftUI

/// macOS varyantı: NSScrollView'in built-in magnification'ı (trackpad pinch / Cmd+scroll)
/// ile zoom destekler. Çift tıkla 1x ↔ 3x toggle. Pan native scroll ile gelir.
struct ZoomableImageView: NSViewRepresentable {
    let url: URL
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1.0
        scrollView.maxMagnification = 5.0
        scrollView.contentView.postsBoundsChangedNotifications = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = scrollView.bounds
        scrollView.documentView = imageView
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .large
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addFloatingSubview(spinner, for: .vertical)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
        context.coordinator.spinner = spinner

        // Çift tıkla zoom toggle
        let dblClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        dblClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(dblClick)

        loadImage(into: imageView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    private func loadImage(into imageView: NSImageView, coordinator: Coordinator) {
        ImagePipeline.shared.loadImage(with: url) { result in
            DispatchQueue.main.async {
                coordinator.spinner?.stopAnimation(nil)
                coordinator.spinner?.removeFromSuperview()
                if case .success(let response) = result {
                    imageView.image = response.image
                }
            }
        }
    }

    final class Coordinator: NSObject {
        weak var imageView: NSImageView?
        weak var scrollView: NSScrollView?
        weak var spinner: NSProgressIndicator?
        private let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        @objc func handleDoubleClick(_ sender: NSClickGestureRecognizer) {
            guard let sv = scrollView else { return }
            if sv.magnification > 1.01 {
                sv.animator().magnification = 1.0
            } else {
                let point = sender.location(in: sv.documentView)
                sv.setMagnification(3.0, centeredAt: point)
            }
        }
    }
}
