import SwiftUI
import UIKit

/// media-kit tarzı: kontroller **kapalıyken** tek parmak `UITapGestureRecognizer` ile göster (sürükleyerek kapatmayı
/// `touchesBegan` ile karıştırmaz). **Açıkken** gizleme yine tap; `UILongPressGestureRecognizer` (2x) ile
/// `require(toFail:)` sırası kullanılır.
/// VOD atlama ±15 sn, play/pause yanındaki SwiftUI düğmeleriyle.
/// Tüm pinch + pan (zoomluyken) bu UIKit container'ında; SwiftUI `.gesture` scaled-view'a
/// attached olduğunda koordinat sistemi bozuluyor ve outer dismiss gesture ile çakışıyor.
/// `hitTest` her zaman `super` döner — gesture recognizer'lar touch'ları yakalar, tap/pinch/pan
/// aynı anda `shouldRecognizeSimultaneouslyWith` ile konuşur.
final class PlayerMediaKitTouchContainerView: UIView, UIGestureRecognizerDelegate {
  fileprivate weak var coordinator: PlayerMediaKitStyleTouchOverlay.Coordinator?

  var videoZoomScale: CGFloat = 1 {
    didSet { videoPan.isEnabled = videoZoomScale > 1.02 }
  }
  var enableSpeedHold: Bool = false
  var isSpeedHoldActive: Bool = false

  fileprivate let centerView = MediaKitCenterPanel()
  private let videoPinch = UIPinchGestureRecognizer()
  private let videoPan = UIPanGestureRecognizer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isMultipleTouchEnabled = true
    isOpaque = false
    backgroundColor = .clear

    videoPinch.addTarget(self, action: #selector(handleVideoPinch(_:)))
    videoPinch.cancelsTouchesInView = false
    videoPinch.delegate = self
    addGestureRecognizer(videoPinch)

    videoPan.addTarget(self, action: #selector(handleVideoPan(_:)))
    videoPan.cancelsTouchesInView = false
    videoPan.delegate = self
    videoPan.minimumNumberOfTouches = 1
    videoPan.maximumNumberOfTouches = 1
    videoPan.isEnabled = false  // yalnızca zoomluyken aktif
    addGestureRecognizer(videoPan)

    addSubview(centerView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    centerView.frame = bounds
  }

  func bindToCoordinator(_ c: PlayerMediaKitStyleTouchOverlay.Coordinator) {
    coordinator = c
    centerView.coordinator = c
    syncPanels()
  }

  func syncPanels() {
    let show = coordinator?.showControls.wrappedValue ?? true
    centerView.configureRecognizers(
      showControls: show,
      enableSpeedHold: enableSpeedHold,
      isSpeedHoldActive: isSpeedHoldActive
    )
  }

  @objc private func handleVideoPinch(_ g: UIPinchGestureRecognizer) {
    switch g.state {
    case .began:
      let loc = g.location(in: self)
      coordinator?.onVideoPinchBegan(loc, bounds.size)
    case .changed:
      coordinator?.onVideoPinchChanged(g.scale)
    case .ended, .cancelled, .failed:
      coordinator?.onVideoPinchEnded()
    default:
      break
    }
  }

  @objc private func handleVideoPan(_ g: UIPanGestureRecognizer) {
    switch g.state {
    case .changed:
      let t = g.translation(in: self)
      coordinator?.onVideoPanChanged(CGSize(width: t.x, height: t.y))
    case .ended, .cancelled, .failed:
      let t = g.translation(in: self)
      coordinator?.onVideoPanEnded(CGSize(width: t.x, height: t.y))
    default:
      break
    }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

private final class MediaKitCenterPanel: UIView, UIGestureRecognizerDelegate {
  fileprivate weak var coordinator: PlayerMediaKitStyleTouchOverlay.Coordinator?

  private let showTap = UITapGestureRecognizer()
  private let hideTap = UITapGestureRecognizer()
  private let speedHold = UILongPressGestureRecognizer()

  override init(frame: CGRect) {
    super.init(frame: .zero)
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = true

    showTap.addTarget(self, action: #selector(showTapRecognized))
    showTap.numberOfTapsRequired = 1
    showTap.cancelsTouchesInView = false
    addGestureRecognizer(showTap)

    hideTap.addTarget(self, action: #selector(hideTapRecognized))
    hideTap.numberOfTapsRequired = 1
    hideTap.cancelsTouchesInView = false
    addGestureRecognizer(hideTap)

    speedHold.addTarget(self, action: #selector(speedHoldRecognized(_:)))
    speedHold.minimumPressDuration = 0.42
    speedHold.allowableMovement = 80
    speedHold.cancelsTouchesInView = false
    speedHold.delegate = self
    addGestureRecognizer(speedHold)

    showTap.require(toFail: speedHold)
    hideTap.require(toFail: speedHold)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configureRecognizers(showControls: Bool, enableSpeedHold: Bool, isSpeedHoldActive: Bool) {
    showTap.isEnabled = !showControls && !isSpeedHoldActive
    hideTap.isEnabled = showControls && !isSpeedHoldActive
    speedHold.isEnabled = enableSpeedHold
  }

  @objc private func showTapRecognized() {
    coordinator?.requestShowChromeFromUIKit()
  }

  @objc private func hideTapRecognized() {
    coordinator?.requestHideChromeFromUIKit()
  }

  @objc private func speedHoldRecognized(_ g: UILongPressGestureRecognizer) {
    switch g.state {
    case .began:
      coordinator?.requestSpeedHoldBeganFromUIKit()
    case .ended, .cancelled, .failed:
      coordinator?.requestSpeedHoldEndedFromUIKit()
    default:
      break
    }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }
}

struct PlayerMediaKitStyleTouchOverlay: UIViewRepresentable {
  @Binding var showControls: Bool
  let isSeekDisabled: Bool
  let videoZoomScale: CGFloat
  let isSpeedHoldActive: Bool
  let onResetTimer: () -> Void
  let onInvalidateTimer: () -> Void
  let onSpeedHoldBegan: () -> Void
  let onSpeedHoldEnded: () -> Void
  let onVideoPinchBegan: (CGPoint, CGSize) -> Void
  let onVideoPinchChanged: (CGFloat) -> Void
  let onVideoPinchEnded: () -> Void
  let onVideoPanChanged: (CGSize) -> Void
  let onVideoPanEnded: (CGSize) -> Void
  var onVideoSurfaceTap: (() -> Void)? = nil

  func makeCoordinator() -> Coordinator {
    Coordinator(
      showControls: $showControls,
      onResetTimer: onResetTimer,
      onInvalidateTimer: onInvalidateTimer,
      onSpeedHoldBegan: onSpeedHoldBegan,
      onSpeedHoldEnded: onSpeedHoldEnded,
      onVideoPinchBegan: onVideoPinchBegan,
      onVideoPinchChanged: onVideoPinchChanged,
      onVideoPinchEnded: onVideoPinchEnded,
      onVideoPanChanged: onVideoPanChanged,
      onVideoPanEnded: onVideoPanEnded,
      onVideoSurfaceTap: onVideoSurfaceTap
    )
  }

  func makeUIView(context: Context) -> PlayerMediaKitTouchContainerView {
    let v = PlayerMediaKitTouchContainerView()
    v.bindToCoordinator(context.coordinator)
    return v
  }

  func updateUIView(_ uiView: PlayerMediaKitTouchContainerView, context: Context) {
    context.coordinator.showControls = $showControls
    context.coordinator.onResetTimer = onResetTimer
    context.coordinator.onInvalidateTimer = onInvalidateTimer
    context.coordinator.onSpeedHoldBegan = onSpeedHoldBegan
    context.coordinator.onSpeedHoldEnded = onSpeedHoldEnded
    context.coordinator.onVideoPinchBegan = onVideoPinchBegan
    context.coordinator.onVideoPinchChanged = onVideoPinchChanged
    context.coordinator.onVideoPinchEnded = onVideoPinchEnded
    context.coordinator.onVideoPanChanged = onVideoPanChanged
    context.coordinator.onVideoPanEnded = onVideoPanEnded
    context.coordinator.onVideoSurfaceTap = onVideoSurfaceTap
    uiView.videoZoomScale = videoZoomScale
    uiView.enableSpeedHold = !isSeekDisabled && videoZoomScale <= 1.02
    uiView.isSpeedHoldActive = isSpeedHoldActive
    uiView.syncPanels()
    uiView.setNeedsLayout()
  }

  final class Coordinator: NSObject {
    var showControls: Binding<Bool>
    var onResetTimer: () -> Void
    var onInvalidateTimer: () -> Void
    var onSpeedHoldBegan: () -> Void
    var onSpeedHoldEnded: () -> Void
    var onVideoPinchBegan: (CGPoint, CGSize) -> Void
    var onVideoPinchChanged: (CGFloat) -> Void
    var onVideoPinchEnded: () -> Void
    var onVideoPanChanged: (CGSize) -> Void
    var onVideoPanEnded: (CGSize) -> Void
    var onVideoSurfaceTap: (() -> Void)?

    init(
      showControls: Binding<Bool>,
      onResetTimer: @escaping () -> Void,
      onInvalidateTimer: @escaping () -> Void,
      onSpeedHoldBegan: @escaping () -> Void,
      onSpeedHoldEnded: @escaping () -> Void,
      onVideoPinchBegan: @escaping (CGPoint, CGSize) -> Void,
      onVideoPinchChanged: @escaping (CGFloat) -> Void,
      onVideoPinchEnded: @escaping () -> Void,
      onVideoPanChanged: @escaping (CGSize) -> Void,
      onVideoPanEnded: @escaping (CGSize) -> Void,
      onVideoSurfaceTap: (() -> Void)? = nil
    ) {
      self.showControls = showControls
      self.onResetTimer = onResetTimer
      self.onInvalidateTimer = onInvalidateTimer
      self.onSpeedHoldBegan = onSpeedHoldBegan
      self.onSpeedHoldEnded = onSpeedHoldEnded
      self.onVideoPinchBegan = onVideoPinchBegan
      self.onVideoPinchChanged = onVideoPinchChanged
      self.onVideoPinchEnded = onVideoPinchEnded
      self.onVideoPanChanged = onVideoPanChanged
      self.onVideoPanEnded = onVideoPanEnded
      self.onVideoSurfaceTap = onVideoSurfaceTap
    }

    private func runOnMain(_ body: @escaping () -> Void) {
      if Thread.isMainThread {
        body()
      } else {
        DispatchQueue.main.async(execute: body)
      }
    }

    private func setShowControlsInstant(_ newValue: Bool) {
      var t = Transaction(animation: nil)
      t.disablesAnimations = true
      withTransaction(t) {
        showControls.wrappedValue = newValue
      }
    }

    func requestShowChromeFromUIKit() {
      runOnMain { [weak self] in
        guard let self else { return }
        self.onVideoSurfaceTap?()
        guard !self.showControls.wrappedValue else { return }
        self.setShowControlsInstant(true)
        self.onResetTimer()
      }
    }

    func requestHideChromeFromUIKit() {
      runOnMain { [weak self] in
        guard let self else { return }
        self.onVideoSurfaceTap?()
        guard self.showControls.wrappedValue else { return }
        self.setShowControlsInstant(false)
        self.onInvalidateTimer()
      }
    }

    func requestSpeedHoldBeganFromUIKit() {
      runOnMain { [weak self] in
        self?.onSpeedHoldBegan()
      }
    }

    func requestSpeedHoldEndedFromUIKit() {
      runOnMain { [weak self] in
        self?.onSpeedHoldEnded()
      }
    }
  }
}
