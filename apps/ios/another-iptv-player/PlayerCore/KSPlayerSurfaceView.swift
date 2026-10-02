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

/// Bitmap (PGS / DVB) cue rendering on the video surface. The bitmap is positioned in
/// the video's own pixel space, so it is part of the picture and follows its transform.
private struct KSSubtitleBitmapOverlay: View {
  let image: UIImage?
  /// Native-frame pixel position of `image` (top-left origin), from `SubtitlePart.origin`.
  let imageOrigin: CGPoint
  /// Video's native pixel size, used to scale `image`/`imageOrigin` down to the
  /// overlay's displayed point size instead of stretching the bitmap to fill it.
  let naturalSize: CGSize

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        if let image {
          let scale = naturalSize.width > 0 ? proxy.size.width / naturalSize.width : 1
          Image(uiImage: image)
            .resizable()
            .frame(width: image.size.width * scale, height: image.size.height * scale)
            .position(
              x: (imageOrigin.x + image.size.width / 2) * scale,
              y: (imageOrigin.y + image.size.height / 2) * scale
            )
        }
      }
      // The ZStack must fill the whole surface: that gives `.position()` the
      // full-surface coordinate space it expects.
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .allowsHitTesting(false)
  }
}

/// Text cues, drawn in a layer of their own that the player mounts next to the video
/// surface instead of inside it. Inside the surface they were scaled, panned and cropped
/// together with the picture: Fill cut the bottom line off and a pinch zoomed them away.
///
/// The owner frames this view to the visible picture and says how far the cue has to
/// stay from the bottom edge of that frame. The view observes the engine itself, and the
/// cue keeps arriving during a cast, where the cast clock drives `updateSubtitleCue`.
struct KSSubtitleTextLayer: View {
  @ObservedObject var engine: KSPlayerEngine
  /// Added below the user's own vertical offset (for example the part of the bottom
  /// safe area that reaches into the picture).
  var bottomInset: CGFloat = 0
  /// The cue's bottom edge is never closer than this to the layer's bottom edge,
  /// whatever the offset is (for example to clear a visible scrubber). It lifts the cue
  /// only by what the offset and `bottomInset` do not already cover.
  var minimumBottomClearance: CGFloat = 0

  var body: some View {
    let appearance = engine.subtitleAppearance
    ZStack {
      // A bitmap cue wins, as it always did: the surface draws that one.
      if engine.subtitleImage == nil, let text = engine.subtitleText, !text.string.isEmpty {
        KSSubtitleCueText(text: text.string, appearance: appearance)
          // Skips the outline pass (many glyph stamps) on engine ticks that leave the
          // cue and its style unchanged.
          .equatable()
          .padding(.bottom, bottomPadding(for: appearance))
          // A cue cuts in and out; it must not fade because some other animation
          // (the chrome cross-fade, the mini morph) happens to be in flight.
          .transition(.identity)
      }
    }
    // The alignment places the text block: `multilineTextAlignment` alone only aligns
    // the lines inside the block, so Left/Right never moved a real cue.
    .frame(
      maxWidth: .infinity, maxHeight: .infinity,
      alignment: KSSubtitleCueText.blockAlignment(for: appearance)
    )
    .allowsHitTesting(false)
  }

  private func bottomPadding(for appearance: SubtitleAppearanceSettings) -> CGFloat {
    let own = max(CGFloat(appearance.verticalOffset) + 12, 0) + max(bottomInset, 0)
    return max(own, minimumBottomClearance)
  }
}

/// One text cue with the user's subtitle appearance settings applied. ASS-styled
/// attributed strings are flattened to plain text — same behavior as the mpv engine's
/// `sub-ass-override=force`.
private struct KSSubtitleCueText: View, Equatable {
  let text: String
  let appearance: SubtitleAppearanceSettings

  var body: some View {
    Text(appearance.applyingWordSpacing(to: text))
      .font(styledFont)
      .italic(appearance.italic)
      .kerning(appearance.letterSpacing)
      .lineSpacing(max(appearance.lineHeight - 1, 0) * CGFloat(appearance.renderedFontPointSize))
      .multilineTextAlignment(textAlignment)
      .foregroundStyle(Color(hex6: appearance.textColorHex6))
      .textRenderer(appearance.outlineRenderer)
      .padding(.horizontal, CGFloat(appearance.padding) + 8)
      .padding(.vertical, 4)
      .background(backgroundFill)
      .padding(.horizontal, blockEdgeInset)
  }

  /// System font with the chosen weight. The former `SFProDisplay-*` PostScript names
  /// are not addressable on the device, so every weight resolved to one fallback face;
  /// `system(size:weight:)` is also a fixed size, where `custom(_:size:)` grew with
  /// Dynamic Type on top of the user's subtitle size.
  private var styledFont: Font {
    Font.system(size: CGFloat(appearance.renderedFontPointSize), weight: styledWeight)
  }

  private var styledWeight: Font.Weight {
    switch appearance.fontWeight {
    case .thin: return .thin
    case .normal: return .regular
    case .medium: return .medium
    case .bold: return .bold
    case .extraBold: return .heavy
    }
  }

  private var textAlignment: TextAlignment {
    switch appearance.textAlignment {
    case .left: return .leading
    case .right: return .trailing
    case .center, .justify: return .center
    }
  }

  /// Where the cue block sits inside the layer that hosts it.
  static func blockAlignment(for appearance: SubtitleAppearanceSettings) -> Alignment {
    switch appearance.textAlignment {
    case .left: return .bottomLeading
    case .right: return .bottomTrailing
    case .center, .justify: return .bottom
    }
  }

  /// Keeps a side-aligned block (and its background box) off the screen edge and the
  /// rounded display corners. Centered cues keep their previous full-width layout.
  private var blockEdgeInset: CGFloat {
    switch appearance.textAlignment {
    case .left, .right: return 12
    case .center, .justify: return 0
    }
  }

  @ViewBuilder private var backgroundFill: some View {
    if appearance.backgroundEnabled {
      RoundedRectangle(cornerRadius: 4)
        .fill(Color(hex6: appearance.backgroundColorHex6).opacity(appearance.backgroundOpacity))
    }
  }
}

/// Draws a subtitle `Text` with a hard outline: the glyphs are stamped at offsets that
/// cover a disc of `width` points, the union is filled with the outline color, and the
/// normal text is drawn on top. A blurred shadow (the previous approach) is a soft halo
/// that washes out on bright scenes. Not private, so the appearance preview can apply
/// the same renderer through `SubtitleAppearanceSettings.outlineRenderer`.
/// `nonisolated`: SwiftUI's `TextRenderer` requirements are not main-actor isolated.
nonisolated struct KSSubtitleOutlineRenderer: TextRenderer {
  let color: Color
  /// Outline thickness in points; 0 draws the text without an outline.
  let width: CGFloat
  private let offsets: [CGSize]

  init(color: Color, width: CGFloat) {
    self.color = color
    self.width = max(width, 0)
    offsets = Self.stampOffsets(radius: max(width, 0))
  }

  /// The outline is drawn outside the text's layout bounds; without this it is clipped.
  var displayPadding: EdgeInsets {
    let inset = width.rounded(.up)
    return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    if !offsets.isEmpty {
      var bounds = CGRect.null
      for line in layout {
        bounds = bounds.union(line.typographicBounds.rect)
      }
      if !bounds.isNull {
        // The stamps only build an alpha mask; filling through it gives one flat
        // outline color whatever the text color is, and overlapping stamps cannot
        // darken each other.
        var outline = context
        outline.clipToLayer { mask in
          for offset in offsets {
            var stamp = mask
            stamp.translateBy(x: offset.width, y: offset.height)
            for line in layout {
              stamp.draw(line)
            }
          }
        }
        // Glyph ink (italics, descenders) can leave the typographic bounds, so the
        // fill is generously larger than them; the mask does the real clipping.
        let slop = width + bounds.height
        outline.fill(Path(bounds.insetBy(dx: -slop, dy: -slop)), with: .color(color))
      }
    }
    for line in layout {
      context.draw(line)
    }
  }

  /// Stamp positions covering a disc of `radius`. The outer ring is dense because it
  /// forms the visible edge (a fixed eight stamps look scalloped on wide outlines);
  /// the inner rings only fill the gap between a thin stem and the outer ring. The
  /// number of stamps therefore grows with the outline width.
  private static func stampOffsets(radius: CGFloat) -> [CGSize] {
    guard radius > 0.01 else { return [] }
    let ringStep: CGFloat = 0.75
    let ringCount = max(Int((radius / ringStep).rounded(.up)), 1)
    var result: [CGSize] = []
    for ring in 1...ringCount {
      let ringRadius = radius * CGFloat(ring) / CGFloat(ringCount)
      let isOuterRing = ring == ringCount
      let arcStep: CGFloat = isOuterRing ? 0.35 : 0.75
      let count = max(isOuterRing ? 12 : 8, Int((2 * CGFloat.pi * ringRadius / arcStep).rounded(.up)))
      for index in 0..<count {
        let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(count)
        result.append(CGSize(width: cos(angle) * ringRadius, height: sin(angle) * ringRadius))
      }
    }
    return result
  }
}

extension SubtitleAppearanceSettings {
  /// Outline renderer for a subtitle `Text` drawn with these settings. The stored
  /// outline size goes through the same `renderPointScale` as the font size, so the
  /// outline keeps its proportion to the glyphs (the default 2 is a 1 pt stroke on
  /// the default 20 pt text).
  var outlineRenderer: KSSubtitleOutlineRenderer {
    KSSubtitleOutlineRenderer(
      color: Color(hex6: outlineColorHex6),
      width: CGFloat(outlineSize * Self.renderPointScale)
    )
  }
}

private extension Color {
  init(hex6: UInt32) {
    self.init(
      red: Double((hex6 >> 16) & 0xFF) / 255.0,
      green: Double((hex6 >> 8) & 0xFF) / 255.0,
      blue: Double(hex6 & 0xFF) / 255.0
    )
  }
}
