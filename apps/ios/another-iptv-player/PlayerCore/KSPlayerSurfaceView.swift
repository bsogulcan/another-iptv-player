import AVKit
import Combine
import SwiftUI
import UIKit

/// AirPlay hedef seçici (yalnız KSPlayer motoru; AVPlayer yolunda gerçek external
/// playback, FFmpeg yolunda sistem yansıtması olarak çalışır).
struct AirPlayRoutePickerButton: UIViewRepresentable {
  var tintColor: UIColor = .white
  /// Called on the main thread when the system device list is about to appear.
  var onWillBegin: (() -> Void)? = nil
  /// Called on the main thread when the system device list has gone away,
  /// whether a device was picked or the list was cancelled.
  var onDidEnd: (() -> Void)? = nil

  func makeCoordinator() -> AirPlayRoutePickerPresentationDelegate {
    AirPlayRoutePickerPresentationDelegate()
  }

  func makeUIView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.tintColor = tintColor
    view.activeTintColor = .systemBlue
    view.prioritizesVideoDevices = true
    context.coordinator.onWillBegin = onWillBegin
    context.coordinator.onDidEnd = onDidEnd
    view.delegate = context.coordinator
    return view
  }

  func updateUIView(_: AVRoutePickerView, context: Context) {
    // The closures capture the caller's current state; refresh them on every update
    // so a callback never runs against a stale copy.
    context.coordinator.onWillBegin = onWillBegin
    context.coordinator.onDidEnd = onDidEnd
  }
}

/// Forwards the system route picker's presentation callbacks to closures. Cancelling
/// the device list raises no route-change notification, so these callbacks are the
/// only signal that the list opened or closed. `AVRoutePickerView.delegate` is weak:
/// the representable's coordinator keeps this object alive.
final class AirPlayRoutePickerPresentationDelegate: NSObject, AVRoutePickerViewDelegate {
  var onWillBegin: (() -> Void)?
  var onDidEnd: (() -> Void)?

  nonisolated func routePickerViewWillBeginPresentingRoutes(_: AVRoutePickerView) {
    Self.runOnMain { [weak self] in self?.onWillBegin?() }
  }

  nonisolated func routePickerViewDidEndPresentingRoutes(_: AVRoutePickerView) {
    Self.runOnMain { [weak self] in self?.onDidEnd?() }
  }

  /// AVKit is expected to call the delegate on the main thread, where forwarding stays
  /// synchronous; the hop only covers an unexpected background delivery, because the
  /// receivers mutate main-thread cast state.
  nonisolated private static func runOnMain(_ work: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
      MainActor.assumeIsolated(work)
    } else {
      DispatchQueue.main.async { work() }
    }
  }
}

/// Görünmez route picker: `trigger` her arttığında sistem cihaz seçici popup'ını
/// programatik açar. UHF akışında remux hazır olduktan sonra kullanılır.
struct HiddenAirPlayRoutePicker: UIViewRepresentable {
  var trigger: Int
  /// Called on the main thread when the system device list is about to appear.
  var onWillBegin: (() -> Void)? = nil
  /// Called on the main thread when the system device list has gone away,
  /// whether a device was picked or the list was cancelled.
  var onDidEnd: (() -> Void)? = nil
  /// Called on the main thread when a trigger could not be turned into a tap because
  /// AVKit's view tree holds no button. Nothing was presented and neither callback
  /// above will follow, so the owner can offer the visible picker at once. It runs
  /// after the view update that handled the trigger has returned, so it may change
  /// view state.
  var onOpenFailed: (() -> Void)? = nil

  final class Coordinator {
    var lastTrigger: Int?
    var onOpenFailed: (() -> Void)?
    let presentation = AirPlayRoutePickerPresentationDelegate()
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> AVRoutePickerView {
    let view = AVRoutePickerView()
    view.prioritizesVideoDevices = true
    view.alpha = 0.02
    view.isUserInteractionEnabled = false
    // SwiftUI's `accessibilityHidden` at the call site does not reach the UIKit tree:
    // the invisible picker's button showed up as an "AirPlay" control in the middle of
    // the picture. The visible `AirPlayRoutePickerButton` stays accessible.
    view.isAccessibilityElement = false
    view.accessibilityElementsHidden = true
    context.coordinator.lastTrigger = trigger
    context.coordinator.presentation.onWillBegin = onWillBegin
    context.coordinator.presentation.onDidEnd = onDidEnd
    context.coordinator.onOpenFailed = onOpenFailed
    view.delegate = context.coordinator.presentation
    return view
  }

  func updateUIView(_ view: AVRoutePickerView, context: Context) {
    // Refreshed before the trigger check, so the tap sent below already reports
    // through the caller's current closures.
    context.coordinator.presentation.onWillBegin = onWillBegin
    context.coordinator.presentation.onDidEnd = onDidEnd
    context.coordinator.onOpenFailed = onOpenFailed
    guard context.coordinator.lastTrigger != trigger else { return }
    context.coordinator.lastTrigger = trigger
    // AVRoutePickerView programatik açma API'si sunmaz; içindeki butona dokunma
    // gönderilir (yaygın, App Store'da kabul gören yaklaşım).
    if let button = Self.firstButton(in: view) {
      button.sendActions(for: .touchUpInside)
    } else {
      // Reported on the next main turn: this is a view update, where the owner must
      // not change state yet. The closure is read when the hop runs, so it is the
      // owner's current one.
      let coordinator = context.coordinator
      DispatchQueue.main.async { [weak coordinator] in
        coordinator?.onOpenFailed?()
      }
    }
  }

  /// The button inside `AVRoutePickerView` that opens the device list. The picker's
  /// view tree is private: a wrapper view between the picker and its button would hide
  /// the button from a one-level search, so the whole tree is walked. Breadth-first, so
  /// a direct child still wins when there is one.
  static func firstButton(in root: UIView) -> UIButton? {
    var level = root.subviews
    while !level.isEmpty {
      for view in level {
        if let button = view as? UIButton { return button }
      }
      level = level.flatMap(\.subviews)
    }
    return nil
  }
}

/// Hosts the KSPlayer video view plus our own bitmap subtitle overlay. While a cast
/// engagement is presenting, the cast player's view is hosted instead and an
/// "AirPlay" placeholder covers the surface when video actually leaves the phone.
struct KSPlayerVideoSurface: View {
  @ObservedObject var engine: KSPlayerEngine
  @ObservedObject var cast: CastController
  var manualPiPTrigger: Int
  var pipEnabled: Bool
  /// Arka plan davranışı `KSOptions.canBackgroundPlay` üzerinden KSPlayerLayer'a
  /// bırakılır (PiP aktifken dokunmaz); burada scenePhase yönetimi yapılmaz.
  var continuePlayingInBackground: Bool
  /// Name of the AirPlay receiver for the placeholder ("Playing on Living Room").
  /// Display only; nil or empty keeps the generic text.
  var routeName: String? = nil

  @State private var lastProcessedPiPTrigger: Int?

  private var isExternallyPlaying: Bool {
    cast.isPresenting ? cast.isExternalPlaybackActive : engine.isExternalPlaybackActive
  }

  var body: some View {
    KSPlayerVideoSurfaceHost(
      engine: engine,
      cast: cast,
      surfaceRevision: engine.surfaceRevision + cast.surfaceRevision,
      castPresenting: cast.isPresenting
    )
    .overlay {
      if isExternallyPlaying {
        AirPlayActivePlaceholder(routeName: routeName)
      }
    }
    .overlay(alignment: .bottom) {
      // Bitmap cues only: they are authored in video space, so they belong on the
      // surface and scale with it. Text cues are drawn by `KSSubtitleTextLayer`, which
      // the player mounts outside the zoom / pan / fill transform.
      KSSubtitleBitmapOverlay(
        image: engine.subtitleImage,
        imageOrigin: engine.subtitleImageOrigin,
        naturalSize: CGSize(width: CGFloat(engine.videoDisplayWidth), height: CGFloat(engine.videoDisplayHeight))
      )
    }
    .onAppear {
      if lastProcessedPiPTrigger == nil { lastProcessedPiPTrigger = manualPiPTrigger }
    }
    .onChange(of: manualPiPTrigger) { _, newValue in
      guard pipEnabled, newValue != lastProcessedPiPTrigger, !cast.isPresenting else { return }
      lastProcessedPiPTrigger = newValue
      engine.togglePictureInPicture()
    }
  }
}

/// Shown over the local surface while video plays on the AirPlay target — the
/// black surface is otherwise indistinguishable from a playback failure.
private struct AirPlayActivePlaceholder: View {
  /// The receiver's name, when the audio route reports one.
  var routeName: String?

  var body: some View {
    ZStack {
      Color.black
      VStack(spacing: 10) {
        Image(systemName: "airplay.video")
          .font(.system(size: 40, weight: .regular))
          .foregroundStyle(.white.opacity(0.85))
        Text(Self.statusText(routeName: routeName))
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.white.opacity(0.7))
          // A receiver name can be long, and the surface is small on the mini card.
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
      }
    }
    .allowsHitTesting(false)
  }

  /// "Playing on <receiver>" when a name is known, the generic text otherwise (the
  /// route name can lag behind the start of external playback, or be blank).
  static func statusText(routeName: String?) -> String {
    let name = routeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return name.isEmpty ? L("player.airplay_active") : L("player.airplay.playing_on", name)
  }
}

private struct KSPlayerVideoSurfaceHost: UIViewRepresentable {
  let engine: KSPlayerEngine
  let cast: CastController
  /// Param olarak geçirilir ki değişim updateUIView'ı tetiklesin (engine fallback'te
  /// KSPlayer yeni bir player/view yaratır; cast devri view'ı değiştirir).
  let surfaceRevision: Int
  let castPresenting: Bool

  private var hostedView: UIView? {
    castPresenting ? cast.castVideoView : engine.videoView
  }

  func makeUIView(context _: Context) -> KSPlayerVideoContainerUIView {
    let view = KSPlayerVideoContainerUIView()
    view.attachIfNeeded(hostedView)
    return view
  }

  func updateUIView(_ uiView: KSPlayerVideoContainerUIView, context _: Context) {
    uiView.attachIfNeeded(hostedView)
  }
}

final class KSPlayerVideoContainerUIView: UIView {
  private weak var hostedView: UIView?

  func attachIfNeeded(_ videoView: UIView?) {
    guard let videoView else { return }
    if hostedView === videoView, videoView.superview === self { return }
    hostedView?.removeFromSuperview()
    hostedView = videoView
    videoView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(videoView)
    NSLayoutConstraint.activate([
      videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
      videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
      videoView.topAnchor.constraint(equalTo: topAnchor),
      videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }
}
