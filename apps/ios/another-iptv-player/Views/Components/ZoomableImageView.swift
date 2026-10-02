import SwiftUI
import UIKit
import Nuke

struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    /// The request under which the caller already has this image on screen, usually at a
    /// much smaller size. When it is still in the memory cache, that bitmap is shown from
    /// the first frame and the full-size image replaces it once loaded.
    var placeholderRequest: ImageRequest? = nil
    var onDismiss: () -> Void

    fileprivate static let imageTag = 1
    fileprivate static let loaderTag = 2
    fileprivate static let failureTag = 3

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LayoutReportingScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tag = Self.imageTag
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        
        // The view has no size yet, so nothing can be laid out here. The scroll view
        // reports every change of its bounds size instead, the first real one included.
        let coordinator = context.coordinator
        scrollView.onBoundsSizeChange = { [weak coordinator] scrollView in
            coordinator?.boundsSizeDidChange(in: scrollView)
        }
        
        imageView.image = Self.imageInMemory(url: url, placeholderRequest: placeholderRequest)
        if imageView.image == nil {
            // Activity Indicator
            let loader = UIActivityIndicatorView(style: .large)
            loader.color = .white
            loader.tag = Self.loaderTag
            loader.startAnimating()
            scrollView.addSubview(loader)
        }
        
        coordinator.loadFullImage(into: scrollView)
        
        // Double tap to zoom
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
        
        // Dismiss gesture (Pan/Drag)
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        scrollView.addGestureRecognizer(panGesture)
        
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: UIScrollView, coordinator: Coordinator) {
        // Closing the viewer must not leave a full-size download running.
        coordinator.cancelLoad()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// What can be shown without waiting: the original when an earlier visit left it in
    /// the memory cache, otherwise the smaller copy the caller points at. Memory only;
    /// this runs on the main thread while the cover is being presented.
    static func imageInMemory(url: URL, placeholderRequest: ImageRequest?) -> UIImage? {
        let cache = ImagePipeline.shared.cache
        if let original = cache.cachedImage(for: ImageRequest(url: url), caches: [.memory]) {
            return original.image
        }
        guard let placeholderRequest else { return nil }
        return cache.cachedImage(for: placeholderRequest, caches: [.memory])?.image
    }

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableImageView
        var isDismissing = false
        private var loadTask: Task<Void, Never>?

        init(_ parent: ZoomableImageView) {
            self.parent = parent
        }

        deinit {
            loadTask?.cancel()
        }

        func loadFullImage(into scrollView: UIScrollView) {
            let request = ImageRequest(url: parent.url, priority: .veryHigh)
            loadTask = Task { [weak self, weak scrollView] in
                let image = try? await ImagePipeline.shared.imageTask(with: request).image
                guard !Task.isCancelled, let self, let scrollView else { return }
                self.didFinishLoading(image, in: scrollView)
            }
        }

        func cancelLoad() {
            loadTask?.cancel()
            loadTask = nil
        }

        private func didFinishLoading(_ image: UIImage?, in scrollView: UIScrollView) {
            loadTask = nil
            scrollView.viewWithTag(ZoomableImageView.loaderTag)?.removeFromSuperview()
            guard let imageView = scrollView.viewWithTag(ZoomableImageView.imageTag) as? UIImageView else { return }
            if let image {
                let replacesPlaceholder = imageView.image != nil
                imageView.image = image
                if !replacesPlaceholder {
                    // Nothing has been laid out yet. A pinch on the empty screen still
                    // changes the zoom scale, and a frame cannot be set under a zoom.
                    if scrollView.zoomScale != 1.0 {
                        scrollView.setZoomScale(1.0, animated: false)
                    }
                    updateLayout(for: scrollView, image: image)
                } else if scrollView.zoomScale == 1.0 {
                    // The placeholder has the same proportions, so a user who already
                    // zoomed into it keeps the frame and only gets the sharper pixels.
                    updateLayout(for: scrollView, image: image)
                }
            } else if imageView.image == nil {
                // Nothing to show at all: say so instead of leaving a black screen.
                let configuration = UIImage.SymbolConfiguration(pointSize: 56, weight: .light)
                let failure = UIImageView(image: UIImage(systemName: "photo", withConfiguration: configuration))
                failure.tintColor = UIColor(white: 1, alpha: 0.35)
                failure.tag = ZoomableImageView.failureTag
                failure.center = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
                scrollView.addSubview(failure)
            }
        }

        /// Fits the image into the new bounds and keeps the spinner or the failure symbol
        /// centred. A frame cannot be set on a view that is zoomed, so a zoomed image goes
        /// back to fit first; in practice that is a rotation.
        func boundsSizeDidChange(in scrollView: UIScrollView) {
            if scrollView.zoomScale != 1.0 {
                scrollView.setZoomScale(1.0, animated: false)
            }
            if let imageView = scrollView.viewWithTag(ZoomableImageView.imageTag) as? UIImageView,
               let image = imageView.image {
                updateLayout(for: scrollView, image: image)
            }
            let center = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
            scrollView.viewWithTag(ZoomableImageView.loaderTag)?.center = center
            scrollView.viewWithTag(ZoomableImageView.failureTag)?.center = center
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return scrollView.viewWithTag(1)
        }
        
        func updateLayout(for scrollView: UIScrollView, image: UIImage) {
            let containerSize = scrollView.bounds.size
            if containerSize == .zero { return }
            
            let imageSize = image.size
            let widthRatio = containerSize.width / imageSize.width
            let heightRatio = containerSize.height / imageSize.height
            let minRatio = min(widthRatio, heightRatio)
            
            let newSize = CGSize(width: imageSize.width * minRatio, height: imageSize.height * minRatio)
            
            if let imageView = scrollView.viewWithTag(1) as? UIImageView {
                imageView.frame = CGRect(origin: .zero, size: newSize)
                scrollView.contentSize = newSize
                centerImage(in: scrollView, imageView: imageView)
            }
        }
        
        func centerImage(in scrollView: UIScrollView, imageView: UIView) {
            let containerSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize
            
            let offsetX = max((containerSize.width - contentSize.width) * 0.5, 0)
            let offsetY = max((containerSize.height - contentSize.height) * 0.5, 0)
            
            imageView.center = CGPoint(x: contentSize.width * 0.5 + offsetX, y: contentSize.height * 0.5 + offsetY)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            if let imageView = scrollView.viewWithTag(1) {
                centerImage(in: scrollView, imageView: imageView)
            }
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let pointInView = gesture.location(in: scrollView.viewWithTag(1))
                let w = scrollView.frame.size.width / 3.0
                let h = scrollView.frame.size.height / 3.0
                let x = pointInView.x - (w / 2.0)
                let y = pointInView.y - (h / 2.0)
                scrollView.zoom(to: CGRect(x: x, y: y, width: w, height: h), animated: true)
            }
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView, scrollView.zoomScale == 1.0 else { return }
            
            let translation = gesture.translation(in: scrollView)
            let velocity = gesture.velocity(in: scrollView)
            
            switch gesture.state {
            case .changed:
                // Visual feedback: simple translation without scaling
                if translation.y > 0 {
                    scrollView.transform = CGAffineTransform(translationX: 0, y: translation.y)
                }
            case .ended, .cancelled:
                if translation.y > 100 || velocity.y > 500 {
                    self.parent.onDismiss()
                } else {
                    UIView.animate(withDuration: 0.3) {
                        scrollView.transform = .identity
                    }
                }
            default:
                break
            }
        }
        
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            if let pan = gesture as? UIPanGestureRecognizer, let scrollView = pan.view as? UIScrollView {
                if scrollView.zoomScale > 1.0 { return false }
                let velocity = pan.velocity(in: scrollView)
                // Minimal: only swipe down to dismiss
                return abs(velocity.y) > abs(velocity.x) && velocity.y > 0
            }
            return true
        }
    }
}

/// A scroll view that tells its owner when its bounds change size. `layoutSubviews` also
/// runs for every scroll and zoom step, which is why the size is compared first.
private final class LayoutReportingScrollView: UIScrollView {
    var onBoundsSizeChange: ((UIScrollView) -> Void)?
    private var lastBoundsSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBoundsSize else { return }
        lastBoundsSize = bounds.size
        onBoundsSizeChange?(self)
    }
}
