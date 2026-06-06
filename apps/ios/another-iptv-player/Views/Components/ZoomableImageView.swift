import SwiftUI
import UIKit
import Nuke

struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    var onDismiss: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tag = 1
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        
        // Activity Indicator
        let loader = UIActivityIndicatorView(style: .large)
        loader.color = .white
        loader.tag = 2
        loader.startAnimating()
        scrollView.addSubview(loader)
        
        // Nuke load using Core API
        ImagePipeline.shared.loadImage(with: url) { [weak imageView, weak loader, weak scrollView] result in
            DispatchQueue.main.async {
                loader?.stopAnimating()
                loader?.removeFromSuperview()
                
                if case .success(let response) = result {
                    imageView?.image = response.image
                    if let sv = scrollView {
                        context.coordinator.updateLayout(for: sv, image: response.image)
                    }
                }
            }
        }
        
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
        if let imageView = uiView.viewWithTag(1) as? UIImageView, let image = imageView.image {
            context.coordinator.updateLayout(for: uiView, image: image)
        } else if let loader = uiView.viewWithTag(2) {
            loader.center = CGPoint(x: uiView.bounds.midX, y: uiView.bounds.midY)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableImageView
        var isDismissing = false

        init(_ parent: ZoomableImageView) {
            self.parent = parent
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
