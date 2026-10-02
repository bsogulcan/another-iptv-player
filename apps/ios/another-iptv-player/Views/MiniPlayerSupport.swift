import Combine
import SwiftUI
import UIKit

/// Intent policy for the fullscreen-player pull-down gesture. Keeping the slop,
/// direction lock, progress mapping, and release decision together prevents small
/// vertical touch drift from visibly moving or minimizing the player.
enum FullscreenPlayerPullDownPolicy {
    static let activationDistance: CGFloat = 44
    static let verticalDominance: CGFloat = 1.25
    static let directCommitProgress: CGFloat = 0.52
    static let minimumFlickProgress: CGFloat = 0.18
    static let projectedCommitProgress: CGFloat = 0.68

    static func shouldActivate(translation: CGSize) -> Bool {
        translation.height > activationDistance
            && translation.height > abs(translation.width) * verticalDominance
    }

    static func activeDistance(fullDistance: CGFloat) -> CGFloat {
        max(fullDistance - activationDistance, 1)
    }

    static func progress(translationHeight: CGFloat, fullDistance: CGFloat) -> CGFloat {
        let traveled = max(0, translationHeight - activationDistance)
        return min(1, traveled / activeDistance(fullDistance: fullDistance))
    }

    /// Progress measured from the translation at which the axis actually locked. A drag
    /// that wanders sideways first only qualifies well past the slop (the dominance rule
    /// needs more height); anchoring at the slop made the morph jump to a third of the
    /// way on that frame. Never anchors earlier than the slop itself.
    static func progress(
        translationHeight: CGFloat,
        activationHeight: CGFloat,
        fullDistance: CGFloat
    ) -> CGFloat {
        let anchor = max(activationHeight, activationDistance)
        let traveled = max(0, translationHeight - anchor)
        return min(1, traveled / activeDistance(fullDistance: fullDistance))
    }

    /// Content offset that keeps the grabbed point under the finger while the content is
    /// scaled by `scale` about `anchor`: the finger travel since the axis locked, plus the
    /// `(1 - scale)` correction that an off-centre grab needs (a centre-anchored scale
    /// alone pulls every other point toward the centre). The content never follows above
    /// the point where the pull-down began.
    static func followOffset(
        translation: CGSize,
        activationTranslation: CGSize,
        grabPoint: CGPoint,
        anchor: CGPoint,
        scale: CGFloat
    ) -> CGSize {
        CGSize(
            width: translation.width - activationTranslation.width
                + (1 - scale) * (grabPoint.x - anchor.x),
            height: max(0, translation.height - activationTranslation.height)
                + (1 - scale) * (grabPoint.y - anchor.y)
        )
    }

    static func shouldCommit(
        progress: CGFloat,
        projectedProgress: CGFloat,
        velocityY: CGFloat
    ) -> Bool {
        progress >= directCommitProgress
            || (
                progress >= minimumFlickProgress
                    && projectedProgress >= projectedCommitProgress
                    && velocityY > 0
            )
    }
}

/// Where a fullscreen dismiss drag may start. Every point is in the player container's
/// own space, whose origin is the safe-area corner rather than the screen corner: a band
/// defined against the container needs no inset, and one defined against the physical
/// screen edge adds the inset exactly once.
enum FullscreenPlayerDismissZonePolicy {
    /// Edge-back start margin, measured from the physical screen edge.
    static let edgeBackMargin: CGFloat = 36
    /// Gap between a brightness / volume capsule and the safe-area edge it sits on.
    static let edgeSliderGap: CGFloat = 16
    static let topChromeHeight: CGFloat = 96
    /// Bottom chrome band, measured from the container (safe-area) bottom, where the
    /// chrome itself is laid out.
    static let bottomChromeHeight: CGFloat = 168

    /// `leadingInset` is the safe-area inset on the side the swipe starts from. In
    /// landscape that inset is about 59 pt; measuring the margin from the safe-area edge
    /// made the start zone 95 pt wide there.
    static func startsEdgeBack(
        startX: CGFloat,
        containerWidth: CGFloat,
        leadingInset: CGFloat,
        isRightToLeft: Bool
    ) -> Bool {
        if isRightToLeft {
            return startX > containerWidth + leadingInset - edgeBackMargin
        }
        return startX + leadingInset < edgeBackMargin
    }

    /// Position only, like `MiniPlayerDismissPolicy`: a fast flick that has not carried
    /// the player far enough springs back instead of closing it.
    static func edgeBackShouldCommit(progressed: CGFloat, containerWidth: CGFloat) -> Bool {
        progressed > min(containerWidth * 0.28, 130)
    }

    /// True when a pull-down starts in the band of the top row or of the bottom
    /// transport and must not move the player. The sides are not bands: the only
    /// controls there are the brightness and volume capsules, which `startsOnEdgeSlider`
    /// covers by their frames. Full-height side strips of 110 pt left about a quarter of
    /// a portrait screen for the pull-down while the controls were showing.
    static func startsOnChrome(start: CGPoint, container: CGSize) -> Bool {
        let h = max(container.height, 1)
        if start.y <= topChromeHeight { return true }
        return start.y >= h - bottomChromeHeight
    }

    /// True when a dismiss drag starts on a brightness or volume capsule (or within its
    /// hit slop). The capsule's own drag owns that touch: it must neither pull the
    /// player down nor, drifting sideways next to the screen edge, slide it away as an
    /// edge-back swipe.
    ///
    /// `screen` is the whole screen in the container's space (see
    /// `MiniPlayerMetrics.screenFrame`); the capsules are laid out in it, centred
    /// vertically, `edgeSliderGap` inside the safe area. `leftInset` / `rightInset` are
    /// the safe-area insets of the physical sides.
    static func startsOnEdgeSlider(
        start: CGPoint,
        screen: CGRect,
        trackSize: CGSize,
        leftInset: CGFloat,
        rightInset: CGFloat
    ) -> Bool {
        PlayerEdgeSliderGestureExclusion.contains(
            start,
            in: screen,
            trackSize: trackSize,
            leadingInset: edgeSliderGap + leftInset,
            trailingInset: edgeSliderGap + rightInset
        )
    }

    /// Height of the band under the physical top edge that belongs to Control Center /
    /// Notification Center, measured from the screen top.
    static func topSystemGestureBandHeight(
        safeAreaTop: CGFloat,
        containerHeight: CGFloat
    ) -> CGFloat {
        let h = max(containerHeight, 1)
        let minBand: CGFloat = 72
        let fromSafe = safeAreaTop + 40
        return min(max(fromSafe, minBand), h * 0.28)
    }

    /// `startY` is measured from the safe-area top, the band from the screen top.
    static func startsInTopSystemGestureBand(
        startY: CGFloat,
        safeAreaTop: CGFloat,
        containerHeight: CGFloat
    ) -> Bool {
        startY + safeAreaTop <= topSystemGestureBandHeight(
            safeAreaTop: safeAreaTop,
            containerHeight: containerHeight
        )
    }
}

/// Linear interpolation between `a` and `b` by `t` (unclamped).
func miniLerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// Holds the live drag translation of the docked mini card plus its drag-to-dismiss fade.
/// Observed ONLY by `MiniCardDragLayer`, never by the PlayerView body — so repositioning the card
/// is a cheap pure translation and does not re-render the heavy player subtree (which would re-run
/// the video surface update and make the picture visibly glitch while dragging). PlayerView holds
/// it via `@State` (which does not subscribe), and the drag gesture mutates these directly.
final class MiniCardDragModel: ObservableObject {
    @Published var offset: CGSize = .zero
    /// Live dismiss fade, driven from the card's off-screen fraction while dragging toward any
    /// edge (1 = fully opaque, ~0.2 = about to be released off-screen). Kept on the model so the
    /// fade and the offset update in the same re-render as the card moves — no lockstep drift.
    @Published var dismissOpacity: Double = 1
}

/// Repositions the docked mini-card group by the live drag offset and applies the drag-to-dismiss
/// fade — the ONLY thing that re-renders while the card is being dragged. Everything expensive
/// (the masked/scaled video) lives in `content`, which is evaluated once by the parent and merely
/// re-offset here, so playback is untouched.
struct MiniCardDragLayer<Content: View>: View {
    @ObservedObject var model: MiniCardDragModel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .offset(model.offset)
            .opacity(model.dismissOpacity)
    }
}

// MARK: - Full ↔ mini morph

/// Live state of the fullscreen ↔ mini-card morph. Like `MiniCardDragModel`, PlayerView
/// holds it via `@State` (which does not subscribe) and only the thin layers below
/// observe it: a pull-down writes it on every touch-move, and re-evaluating the whole
/// player body at that rate is what made the morph (and FFmpeg video, which is presented
/// from the main thread) stutter under the finger.
final class MiniMorphModel: ObservableObject {
    /// 0 = fullscreen, 1 = docked mini card.
    @Published var progress: CGFloat = 0
    /// Finger-follow offset of a pull-down, or the sideways travel of an edge-back swipe.
    @Published var dismissOffset: CGSize = .zero
    /// What `dismissOffset` currently is: the sideways travel of an edge-back swipe dims
    /// the player, while a pull-down's offset (which also has a sideways part, since it
    /// follows the finger) must not. Set when a drag locks its axis and kept through the
    /// release, so the offset springing back does not start to dim half-way. Not
    /// published: it is written before the offset that announces the change.
    var dismissOffsetDims = false
}

/// Geometry and fades of the morph as functions of its progress, free of view state.
enum MiniMorphGeometry {
    struct Transform: Equatable {
        var scale: CGFloat
        /// Relative to the screen centre, which is also the scale anchor and mask centre.
        var offset: CGSize
        /// In pre-scale points.
        var maskSize: CGSize
        /// Applied pre-scale.
        var cornerRadius: CGFloat
    }

    /// The mask starts this much larger than the screen on every side, so the fullscreen
    /// state never clips.
    static let maskBleed: CGFloat = 160
    /// Progress above which the docked-card pieces (shadow, card chrome) can be on
    /// screen at all.
    static let cardPiecesProgress: CGFloat = 0.01
    /// Progress below which the player counts as fullscreen for code that acts on a
    /// tap, a timer or a task.
    static let fullscreenProgress: CGFloat = 0.02

    /// Scale that lands the fitted picture on the card. Never above 1: minimizing must
    /// not scale the content up (the `.center` aspect mode reports a 1×1 fitted size
    /// until the stream's dimensions arrive).
    static func targetScale(cardHeight: CGFloat, fittedHeight: CGFloat) -> CGFloat {
        min(cardHeight / max(fittedHeight, 1), 1)
    }

    /// Scale / offset / mask / corner radius of the player content at progress `p`. The
    /// transform lands the picture (not the letterboxed screen) on the card. `screen` is
    /// the frame the content is laid out in; `card` is in the same space.
    static func transform(
        progress p: CGFloat, card: CGRect, screen: CGRect, targetScale: CGFloat
    ) -> Transform {
        let scale = miniLerp(1, targetScale, p)
        // Oversized at p=0 (no clip); shrinks to the card slot (in pre-scale points) at p=1.
        let maskSize = CGSize(
            width: miniLerp(screen.width + maskBleed * 2, card.width / max(targetScale, 0.01), p),
            height: miniLerp(screen.height + maskBleed * 2, card.height / max(targetScale, 0.01), p)
        )
        let offset = CGSize(
            width: miniLerp(0, card.midX - screen.midX, p),
            height: miniLerp(0, card.midY - screen.midY, p)
        )
        // Corner radius is applied pre-scale, so divide by scale to keep it visually constant.
        let cornerRadius = MiniPlayerMetrics.cornerRadius * min(p * 2.5, 1) / max(scale, 0.01)
        return Transform(scale: scale, offset: offset, maskSize: maskSize, cornerRadius: cornerRadius)
    }

    /// Fullscreen chrome fades out over the first quarter of the minimize morph so the
    /// controls don't ride the shrinking card.
    static func fullscreenChromeOpacity(progress: CGFloat) -> Double {
        Double(1 - min(max(progress, 0) / 0.25, 1))
    }

    /// Mini card chrome fades in over the last third of the morph.
    static func cardChromeOpacity(progress: CGFloat) -> Double {
        Double(max(0, min(1, (progress - 0.65) / 0.35)))
    }

    /// Dim of the horizontal edge-back swipe, from its sideways travel.
    static func edgeBackOpacity(offsetWidth: CGFloat, containerWidth: CGFloat) -> Double {
        let w = max(containerWidth, 1)
        let vx = Double(abs(offsetWidth)) / Double(w)
        let combined = min(0.55, vx * 0.32)
        return max(0.38, 1.0 - combined)
    }
}

/// Transforms the player content toward the floating mini card and draws the card's
/// shadow under it. Together with the two fades and the progress reader below it is all
/// that re-evaluates while the morph moves: `content` is built once by the parent and
/// only re-transformed here, so the player subtree (video surface, chrome) is left alone.
///
/// The content gets an explicit full-screen frame built from the outer insets instead of
/// ignoring the safe area from inside: SwiftUI resolves `ignoresSafeArea` through the
/// scale/offset below, so the surface used to change size on the first frame of a
/// pull-down and again when an expand settled. With a fixed frame, mask, scale anchor and
/// offset all share the true screen centre and only the transform changes.
struct MiniMorphLayer<Content: View>: View {
    @ObservedObject var model: MiniMorphModel
    /// Rest frame of the docked card, in the container's (safe-area) space.
    let card: CGRect
    /// The whole screen in the same space; the content is laid out in it.
    let screen: CGRect
    let containerWidth: CGFloat
    /// See `MiniMorphGeometry.targetScale`.
    let targetScale: CGFloat
    /// The morph is engaged or the card is docked. Discrete on purpose: it mounts the
    /// shadow, and a mount that followed the progress would need this body's parent to
    /// read the progress.
    let showsCardShadow: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let progress = min(max(model.progress, 0), 1)
        let t = MiniMorphGeometry.transform(
            progress: progress, card: card, screen: screen, targetScale: targetScale
        )
        let offset = model.dismissOffset
        ZStack {
            // Card shadow, a cheap standalone rounded rect tracking the visible video
            // card through the whole morph. The masked video layer never carries a
            // shadow itself — re-shadowing that full-screen layer each frame as the
            // mask animates caused judder/tremble. The opaque video lands on top of
            // this fill; only the shadow spills out.
            if showsCardShadow {
                RoundedRectangle(
                    cornerRadius: MiniPlayerMetrics.cornerRadius * min(progress * 2.5, 1),
                    style: .continuous
                )
                .fill(Color.black)
                .frame(width: t.maskSize.width * t.scale, height: t.maskSize.height * t.scale)
                .shadow(color: .black.opacity(0.38 * Double(progress)),
                        radius: 22 * progress, x: 0, y: 8 * progress)
                .position(
                    x: screen.midX + t.offset.width + offset.width,
                    y: screen.midY + t.offset.height + offset.height
                )
                .allowsHitTesting(false)
            }

            // The mask crops the letterbox down to the card; scale/offset land the video
            // on the card center. View identity is stable so playback never restarts.
            content
                .frame(width: screen.width, height: screen.height)
                .mask(
                    RoundedRectangle(cornerRadius: t.cornerRadius, style: .continuous)
                        .frame(width: t.maskSize.width, height: t.maskSize.height)
                )
                .scaleEffect(t.scale)
                // Layout position, not a render offset: the frame sits on the screen
                // rect, while the owner's gesture keeps measuring in the container's
                // (safe-area) space the dismiss bands and the card rect are defined in.
                .position(x: screen.midX, y: screen.midY)
                .offset(
                    x: t.offset.width + offset.width,
                    y: t.offset.height + offset.height
                )
                // Fade only for the horizontal edge-back swipe; the pull-down morphs into
                // the mini card instead.
                .opacity(
                    model.dismissOffsetDims
                        ? MiniMorphGeometry.edgeBackOpacity(
                            offsetWidth: offset.width, containerWidth: containerWidth
                        )
                        : 1
                )
        }
    }
}

/// Fades everything that belongs to the fullscreen presentation only (chrome, pills,
/// banners) out over the first part of the morph. One wrapper around one container: the
/// elements inside no longer read the progress themselves.
struct MiniMorphFullscreenFade<Content: View>: View {
    @ObservedObject var model: MiniMorphModel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .opacity(MiniMorphGeometry.fullscreenChromeOpacity(progress: model.progress))
    }
}

/// Places the mini card's own chrome on the card and fades it in over the last part of
/// the morph. It rides the finger-follow offset of a pull-down, so the chrome fades in
/// on the card rather than at the dock corner.
struct MiniMorphCardChromeLayer<Content: View>: View {
    @ObservedObject var model: MiniMorphModel
    /// Rest frame of the docked card, in the container's space.
    let card: CGRect
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: card.width, height: card.height)
            .position(
                x: card.midX + model.dismissOffset.width,
                y: card.midY + model.dismissOffset.height
            )
            .opacity(MiniMorphGeometry.cardChromeOpacity(progress: model.progress))
    }
}

/// Rebuilds a small piece of the player whose layout (not just its opacity) follows the
/// morph: the subtitle frame. `content` receives the progress clamped to 0...1.
struct MiniMorphProgressReader<Content: View>: View {
    @ObservedObject var model: MiniMorphModel
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        content(min(max(model.progress, 0), 1))
    }
}

/// Off-screen / dismiss geometry for the floating mini card. Kept next to the metrics so the live
/// drag fade and the release decision agree on when a card is "heading off the edge". Dismissal is
/// deliberately POSITION-only (how far the card has actually left the app), never velocity/flick —
/// a quick reposition swipe must re-dock, only physically dragging the card out closes it.
enum MiniPlayerDismissPolicy {
    /// Fraction of the card that must clear a screen edge (left, right, or bottom) at release for a
    /// dismiss. 0.5 = the card's center has reached the screen edge (half the card outside).
    static let releaseFraction: CGFloat = 0.5
    /// Opacity floor while dragging toward an edge, so the card stays faintly visible pre-release.
    static let minLiveOpacity: Double = 0.28

    /// How far the card (centered at `center`, size `card`) pokes past the nearest of the left,
    /// right, or bottom screen edges, expressed as a fraction of the card's own extent on that
    /// axis. 0 = fully on-screen; 1 = fully cleared. The top edge is intentionally excluded — the
    /// card docks under the status bar there and an upward drag should re-dock, not dismiss.
    static func offscreenFraction(center: CGPoint, card: CGSize, container: CGSize) -> CGFloat {
        let halfW = card.width / 2
        let halfH = card.height / 2
        let offLeft = max(0, halfW - center.x)
        let offRight = max(0, center.x + halfW - container.width)
        let offBottom = max(0, center.y + halfH - container.height)
        let hFrac = max(offLeft, offRight) / max(card.width, 1)
        let vFrac = offBottom / max(card.height, 1)
        return min(1, max(hFrac, vFrac))
    }

    /// Live card opacity for an off-screen fraction. Fades toward `minLiveOpacity` over the run-up
    /// to `releaseFraction` (not the full 0→1 travel) so the "about to close" dim is obvious well
    /// before the card is fully out — the release point already reads as nearly dismissed.
    static func liveOpacity(offscreenFraction frac: CGFloat) -> Double {
        let progress = min(1, Double(frac) / Double(releaseFraction))
        return minLiveOpacity + (1 - minLiveOpacity) * (1 - progress)
    }
}

/// The four screen corners the floating mini player can dock to.
enum MiniPlayerCorner: Equatable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

/// Geometry for the in-app floating mini player card.
///
/// The card floats in a screen corner above the tab bar. Its aspect ratio follows the
/// currently displayed video (clamped) so the frame hugs the picture like system PiP,
/// instead of forcing a fixed 16:9 slot that would letterbox or crop odd streams.
enum MiniPlayerMetrics {
    /// Gap between the card and the screen / safe-area edge.
    static let margin: CGFloat = 12
    static let cornerRadius: CGFloat = 16
    /// Extra bottom space reserved for the bottom tab bar on compact widths so the
    /// card floats *above* it and the tabs stay tappable. iPad `.sidebarAdaptable`
    /// has no bottom bar, so callers pass 0 there. Standard UITabBar height.
    static let tabBarAllowance: CGFloat = 49

    static func cardWidth(container: CGSize) -> CGFloat {
        min(container.width * 0.48, 240)
    }

    /// The whole screen expressed in the player container's space, whose origin is the
    /// safe-area corner: the container grown by its own insets. `left` / `right` are
    /// physical sides (already resolved for the layout direction).
    static func screenFrame(
        container: CGSize,
        top: CGFloat,
        left: CGFloat,
        bottom: CGFloat,
        right: CGFloat
    ) -> CGRect {
        CGRect(
            x: -left,
            y: -top,
            width: container.width + left + right,
            height: container.height + top + bottom
        )
    }

    /// Card size honoring the video's displayed aspect (clamped so extreme streams still
    /// yield a sensible card). Height is bounded by `maxHeight` (derived from the available
    /// vertical space) so a portrait video in a short/landscape container can't produce a
    /// card taller than the screen or one that barely shrinks — width is then re-derived from
    /// the clamped height to keep the aspect.
    static func cardSize(container: CGSize, videoAspect: CGFloat, maxHeight: CGFloat) -> CGSize {
        let aspect = min(max(videoAspect, 0.62), 2.4)
        var w = cardWidth(container: container)
        var h = w / aspect
        if h > maxHeight {
            h = maxHeight
            w = h * aspect
        }
        return CGSize(width: w, height: h)
    }

    static func cardOrigin(
        corner: MiniPlayerCorner,
        size: CGSize,
        container: CGSize,
        safeArea: EdgeInsets,
        bottomInset: CGFloat
    ) -> CGPoint {
        // Rest the card against the physical screen edges. In landscape the leading/trailing
        // safe-area insets (notch / camera housing) are large (~50pt each on iPhone); honoring
        // them left a wide empty strip on both sides. The user wants the card flush to the edge,
        // so we inset horizontally by only `margin` from the real container edge.
        let leftX = margin
        let rightX = container.width - margin - size.width
        let topY = safeArea.top + margin
        // Leave a small `margin` gap above the reserved bottom navigation/tab-bar region so the
        // card doesn't crowd the bar (sitting perfectly flush read as too close on device).
        let bottomY = container.height - bottomInset - margin - size.height
        switch corner {
        case .topLeading: return CGPoint(x: leftX, y: topY)
        case .topTrailing: return CGPoint(x: rightX, y: topY)
        case .bottomLeading: return CGPoint(x: leftX, y: bottomY)
        case .bottomTrailing: return CGPoint(x: rightX, y: bottomY)
        }
    }
}

/// Interactive chrome drawn on top of the shrunk video card: tap-to-expand, play/pause,
/// close, and a drag handle for moving between corners / swiping away. Rendered unscaled
/// at the card's position; the live video shows through from the transformed player below.
struct MiniPlayerChrome: View {
    @ObservedObject var player: VideoPlayerController
    let cornerRadius: CGFloat
    /// Visual (debounced) loading state from PlayerView, so a short post-seek rebuffer
    /// does not flash a spinner on the card.
    let isLoading: Bool
    let onExpand: () -> Void
    let onClose: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (_ translation: CGSize, _ velocity: CGSize) -> Void
    /// The card drag was cancelled (second finger, system interruption): SwiftUI never
    /// calls `onEnded` then, so the owner re-docks the card here.
    var onDragCancelled: (() -> Void)? = nil

    /// Reset by SwiftUI when the drag ends or is cancelled.
    @GestureState private var isDragInFlight = false
    /// True from the first drag event until `onEnded`; still set once the in-flight flag
    /// has dropped means the drag was cancelled.
    @State private var dragAwaitsEnd = false

    /// Buttons keep their small discs but take a 44 pt target, so a near miss no longer
    /// lands on the tap-to-expand layer behind them.
    private static let buttonHitSize: CGFloat = 44

    /// Failed playback, or a live stream that ran into end-of-stream, has nothing to
    /// resume: play/pause would be a dead control, so the card offers a reload instead.
    private var needsPlaybackRetry: Bool {
        !(player.playbackFailureMessage ?? "").isEmpty
            || (player.isLiveStream && player.state == .ended)
    }

    private var transportSymbolName: String {
        if needsPlaybackRetry { return "arrow.clockwise" }
        return player.isPlaying ? "pause.fill" : "play.fill"
    }

    private var transportAccessibilityLabel: String {
        if needsPlaybackRetry { return L("common.try_again") }
        return player.isPlaying ? L("player.a11y.pause") : L("player.a11y.play")
    }

    var body: some View {
        ZStack {
            // Tap-to-expand hit layer, behind the buttons so the buttons win their taps.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onExpand() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(L("player.a11y.expand_mini_player"))
                .accessibilityIdentifier("miniPlayer.expand")

            // Top row: play/pause on the leading (top-left, YouTube-style), close on the trailing.
            VStack {
                HStack(alignment: .top) {
                    // Spinner and transport button share one fixed slot, so the row
                    // never reflows when buffering starts or ends.
                    ZStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .accessibilityLabel(L("common.loading"))
                        } else {
                            Button {
                                if needsPlaybackRetry {
                                    player.retryCurrentLoad()
                                } else {
                                    player.togglePlayPause()
                                }
                            } label: {
                                Image(systemName: transportSymbolName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(.black.opacity(0.4), in: Circle())
                                    // The disc stays where it was (6 pt from the card's
                                    // corner edges); only the target grows around it.
                                    .frame(width: Self.buttonHitSize, height: Self.buttonHitSize)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(transportAccessibilityLabel)
                            .accessibilityIdentifier("miniPlayer.playPause")
                        }
                    }
                    .frame(width: Self.buttonHitSize, height: Self.buttonHitSize)

                    Spacer(minLength: 0)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(.black.opacity(0.45), in: Circle())
                            // Same 6 pt inset from the top and trailing edges as before,
                            // inside a 44 pt target that reaches into the corner.
                            .padding(6)
                            .frame(
                                width: Self.buttonHitSize,
                                height: Self.buttonHitSize,
                                alignment: .topTrailing
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("common.close"))
                    .accessibilityIdentifier("miniPlayer.close")
                }
                Spacer()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .simultaneousGesture(
            // Measure in the GLOBAL (fixed) space, not `.local`: the card is repositioned by this
            // very drag, so a `.local` translation would be measured against a frame that moves
            // with the finger — a feedback loop that makes the card judder back and forth.
            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .updating($isDragInFlight) { _, state, _ in state = true }
                .onChanged {
                    if !dragAwaitsEnd { dragAwaitsEnd = true }
                    onDragChanged($0.translation)
                }
                .onEnded {
                    dragAwaitsEnd = false
                    onDragEnded($0.translation, CGSize(width: $0.velocity.width, height: $0.velocity.height))
                }
        )
        .onChange(of: isDragInFlight) { _, active in
            guard !active, dragAwaitsEnd else { return }
            // The relative order of this reset and `onEnded` is undocumented. Give
            // `onEnded` one runloop turn; a drag that is still open after that was
            // cancelled, and the card would otherwise stay stranded where the finger
            // left it.
            DispatchQueue.main.async {
                guard dragAwaitsEnd, !isDragInFlight else { return }
                dragAwaitsEnd = false
                onDragCancelled?()
            }
        }
    }
}

// MARK: - Landscape lock

/// Applies the app delegate's orientation lock for the fullscreen player. The lock is
/// process-wide by nature (`AppDelegate.orientationLock`); the window passed in is the
/// one the player is mounted in, so the request goes to its own scene even when an
/// AirPlay or external-display scene is connected as well.
enum PlayerOrientationLock {
    static let defaultMask: UIInterfaceOrientationMask = .allButUpsideDown

    /// Leaving a forced landscape asks for portrait only when the app did the forcing
    /// and the phone is not being held sideways: with rotation unlocked, a user holding
    /// it in landscape must stay in landscape. Under Portrait Orientation Lock the system
    /// keeps reporting portrait, so the player returns to portrait there.
    static func shouldRequestPortrait(
        appForcedLandscape: Bool,
        deviceIsPhysicallyLandscape: Bool
    ) -> Bool {
        appForcedLandscape && !deviceIsPhysicallyLandscape
    }

    static func forceLandscape(in window: UIWindow?) {
        // The physical orientation is read again on release; UIKit only reports it
        // while these notifications are being generated.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        AppDelegate.orientationLock = .landscape
        apply(.landscape, in: window)
    }

    static func release(in window: UIWindow?) {
        let wasForced = AppDelegate.orientationLock == .landscape
        let requestPortrait = shouldRequestPortrait(
            appForcedLandscape: wasForced,
            deviceIsPhysicallyLandscape: UIDevice.current.orientation.isLandscape
        )
        // Balances the `begin` in `forceLandscape`.
        if wasForced { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        AppDelegate.orientationLock = defaultMask
        apply(requestPortrait ? .portrait : nil, in: window)
    }

    /// Re-reads the supported orientations first: a geometry request for an orientation
    /// the root view controller does not (yet) report as supported is rejected.
    private static func apply(_ orientations: UIInterfaceOrientationMask?, in window: UIWindow?) {
        guard let window = window ?? fallbackWindow else { return }
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        guard let orientations, let scene = window.windowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { @Sendable error in
            Log.error("PlayerOrientation", "geometry update failed: \(error.localizedDescription)")
        }
    }

    /// Only when the player's own window is unknown (the reader view never attached).
    private static var fallbackWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }
}

/// Weak handle on the window the player is mounted in. Held via `@State` and never
/// observed.
final class PlayerWindowBox {
    weak var window: UIWindow?
}

/// Invisible view that records the window it sits in.
struct PlayerWindowReader: UIViewRepresentable {
    let box: PlayerWindowBox

    func makeUIView(context: Context) -> PlayerWindowReaderView {
        let view = PlayerWindowReaderView()
        view.box = box
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: PlayerWindowReaderView, context: Context) {
        uiView.box = box
    }
}

final class PlayerWindowReaderView: UIView {
    var box: PlayerWindowBox? {
        didSet { if let window { box?.window = window } }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Keep the last window after removal: the player still restores the orientation
        // from `onDisappear`, when this view is already detached.
        if let window { box?.window = window }
    }
}
