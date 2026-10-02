import SwiftUI

/// Arithmetic of the relative scrubber, kept free of view state so it can be unit-tested
/// (same idea as `FullscreenPlayerPullDownPolicy`).
nonisolated enum PlayerTimelineScrubPolicy {
    /// Horizontal travel below this is a tap: the thumb stays put and nothing seeks.
    static let minimumTravel: CGFloat = 3
    /// Vertical finger distance from the track centre where half speed begins. The touch
    /// band itself reaches 22 pt, so a drag that stays on the bar is always full speed.
    static let halfSpeedDistance: CGFloat = 60
    /// Vertical finger distance from the track centre where quarter speed begins.
    static let quarterSpeedDistance: CGFloat = 130

    /// How far the thumb moves per point of finger travel, relative to the track width.
    nonisolated enum Rate: Double, CaseIterable {
        case full = 1
        case half = 0.5
        case quarter = 0.25
    }

    /// Fine scrubbing: the further the finger is from the track, the slower the thumb.
    static func rate(verticalDistance: CGFloat) -> Rate {
        let distance = abs(verticalDistance)
        if distance >= quarterSpeedDistance { return .quarter }
        if distance >= halfSpeedDistance { return .half }
        return .full
    }

    /// False for a touch that never really moved sideways (a tap or a resting finger).
    static func isDeliberate(horizontalTravel: CGFloat) -> Bool {
        abs(horizontalTravel) >= minimumTravel
    }

    /// Travel that counts on the event where the drag first becomes deliberate: whatever
    /// lies past the tap slop. A fast first movement is not lost and a slow one starts
    /// from zero, so the thumb never jumps when the slop is crossed.
    static func travelPastSlop(_ horizontalTravel: CGFloat) -> CGFloat {
        let magnitude = abs(horizontalTravel) - minimumTravel
        guard magnitude > 0 else { return 0 }
        return horizontalTravel < 0 ? -magnitude : magnitude
    }

    /// One drag step: moves `value` by the finger's horizontal delta scaled by `rate`.
    /// Applied per event (not `start + translation * rate`), so changing the speed band
    /// mid-drag does not make the thumb jump.
    static func advanced(
        value: Double,
        horizontalDelta: CGFloat,
        trackWidth: CGFloat,
        rate: Rate
    ) -> Double {
        let current = value.isFinite ? min(max(value, 0), 1) : 0
        guard trackWidth > 0, horizontalDelta.isFinite else { return current }
        let moved = current + Double(horizontalDelta / trackWidth) * rate.rawValue
        return min(max(moved, 0), 1)
    }

    /// Buffered stretch of the timeline as fractions of the duration, from the playhead
    /// to the end of the cached media. Nil when there is nothing to draw.
    static func bufferedRange(
        positionSeconds: Double,
        cacheAheadSeconds: Double,
        durationSeconds: Double
    ) -> ClosedRange<Double>? {
        guard durationSeconds.isFinite, durationSeconds > 0,
              positionSeconds.isFinite, cacheAheadSeconds.isFinite,
              cacheAheadSeconds > 0 else { return nil }
        let lower = min(max(positionSeconds / durationSeconds, 0), 1)
        let upper = min(max((positionSeconds + cacheAheadSeconds) / durationSeconds, 0), 1)
        guard upper > lower else { return nil }
        return lower...upper
    }

    /// Remaining time in whole seconds (as milliseconds). Both sides are truncated the way
    /// the labels are, so elapsed + remaining always equals the total that is displayed.
    static func remainingMs(elapsedMs: Int, durationMs: Int) -> Int {
        let total = max(durationMs, 0) / 1000
        let elapsed = min(max(elapsedMs, 0) / 1000, total)
        return (total - elapsed) * 1000
    }
}

/// Premium, özel yapım video timeline (scrubber).
/// SwiftUI Slider yerine kullanılarak v2 projesindeki o zarif görünümü sağlar.
///
/// The scrub is relative: a touch never moves the thumb to the finger. The thumb moves by
/// the finger's horizontal travel, slowed down the further the finger is from the track.
/// A touch that does not move ends through `onEditingCancelled`, so the owner must pass
/// it to close the scrub that `onEditingChanged(true)` opened.
struct PlayerTimeline: View {
    @Binding var value: Double
    var isSeekable: Bool = true
    var onEditingChanged: (Bool) -> Void
    var onDragValue: ((Double) -> Void)? = nil
    /// The drag was interrupted (touch cancelled by the system, timeline removed mid-drag,
    /// seekability lost): the scrub is over and must NOT seek. SwiftUI never calls
    /// `onEnded` for a cancelled gesture, so without this the owner's scrub state leaks.
    /// Also sent for a touch that never moved: a tap on the track does not seek.
    var onEditingCancelled: (() -> Void)? = nil
    /// Buffered stretch (playhead to end of cache) as fractions, drawn under the fill.
    var bufferedRange: ClosedRange<Double>? = nil
    /// Text for the bubble above the thumb while scrubbing, given the target fraction.
    /// No bubble when nil.
    var scrubLabel: ((Double) -> String)? = nil

    @State private var localValue: Double = 0
    @State private var isDragging: Bool = false
    /// Falls back to `false` on cancellation as well as on end — the only signal SwiftUI
    /// gives for a cancelled drag.
    @GestureState private var isTouchActive: Bool = false
    /// Identifies the drag in flight, so the deferred cancellation check cannot close a
    /// newer drag that began in the meantime.
    @State private var dragGeneration: Int = 0
    /// Finger x at the previous drag event; the thumb advances by the difference.
    @State private var lastDragX: CGFloat = 0
    /// True once the finger travelled past the tap slop. Until then the thumb is frozen,
    /// and a drag that ends without it is a tap (no seek).
    @State private var hasMoved: Bool = false
    @State private var scrubRate: PlayerTimelineScrubPolicy.Rate = .full
    /// Reduce Motion: the thumb and bar change size with a short ease instead of the
    /// bouncy spring, and the bubble only fades.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackCenterY = geometry.size.height / 2
            let currentDisplayValue = isDragging ? localValue : value
            let barHeight: CGFloat = isDragging ? 6 : 4
            let thumbSize: CGFloat = isDragging ? 20 : 13

            ZStack(alignment: .leading) {
                // 1. Arka plan hattı — iOS native ince + açık ton.
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: barHeight)

                // Buffered media ahead of the playhead, between the track and the fill.
                if let bufferedRange {
                    Capsule()
                        .fill(Color.white.opacity(0.34))
                        .frame(
                            width: max(0, width * CGFloat(bufferedRange.upperBound - bufferedRange.lowerBound)),
                            height: barHeight
                        )
                        .offset(x: width * CGFloat(bufferedRange.lowerBound))
                }

                // 2. İlerleme fill.
                Capsule()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: max(0, width * CGFloat(currentDisplayValue)), height: barHeight)

                // 3. Thumb — sürüklerken büyür.
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1.5)
                    .offset(x: (width * CGFloat(currentDisplayValue)) - thumbSize / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if isDragging, let scrubLabel {
                    scrubBubble(text: scrubLabel(localValue))
                        .fixedSize()
                        // Zero-size anchor: the bubble's bottom centre sits on the point,
                        // so it stays centred on the thumb whatever its width.
                        .frame(width: 0, height: 0, alignment: .bottom)
                        // Clear of the fingertip that usually rests on the thumb.
                        .offset(x: width * CGFloat(localValue), y: -10)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.85, anchor: .bottom))
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.12)
                    : .spring(response: 0.32, dampingFraction: 0.72),
                value: isDragging
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouchActive) { _, state, _ in
                        state = true
                    }
                    .onChanged { gesture in
                        if !isDragging {
                            guard isSeekable else { return }
                            isDragging = true
                            hasMoved = false
                            // Relative scrub: start from the value on screen, never from
                            // the touched point.
                            localValue = value.isFinite ? min(max(value, 0), 1) : 0
                            lastDragX = gesture.startLocation.x
                            dragGeneration &+= 1
                            onEditingChanged(true)
                        }
                        // Seekability lost mid-drag: stop tracking, the end path cleans up.
                        guard isSeekable else { return }
                        track(gesture, width: width, trackCenterY: trackCenterY)
                    }
                    .onEnded { gesture in
                        // Cleanup keys off "a drag began", not off `isSeekable`: if
                        // seekability flips mid-drag the scrub must still be closed.
                        guard isDragging else { return }
                        guard isSeekable else {
                            finishDrag()
                            onEditingCancelled?()
                            return
                        }
                        let final = track(gesture, width: width, trackCenterY: trackCenterY)
                        finishDrag()
                        // A touch that never moved is a tap, and a tap must not seek.
                        guard let final else {
                            onEditingCancelled?()
                            return
                        }
                        value = final
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 44) // HIG minimum dokunma hedefi; görsel bar ince kalır.
        // Light tick when the scrub grab begins/releases, like the native scrubber.
        .sensoryFeedback(.selection, trigger: isDragging)
        // And one when the fine-scrubbing band changes, the only cue besides the bubble.
        .sensoryFeedback(trigger: scrubRate) { _, _ in
            isDragging ? .selection : nil
        }
        .onChange(of: isTouchActive) { _, active in
            guard !active, isDragging else { return }
            // The relative order of this reset and `onEnded` is undocumented. Give
            // `onEnded` one runloop turn; a drag of the same generation that is still
            // open after that was cancelled (second finger, lock button, interruption).
            let generation = dragGeneration
            DispatchQueue.main.async {
                guard isDragging, generation == dragGeneration else { return }
                finishDrag()
                onEditingCancelled?()
            }
        }
        // @GestureState cannot report anything once the view is gone; a timeline removed
        // under the finger (chrome hidden mid-drag) is a cancellation too.
        .onDisappear {
            guard isDragging else { return }
            finishDrag()
            onEditingCancelled?()
        }
    }

    /// Applies one drag event: picks the speed band from the finger's vertical distance
    /// and advances the thumb by the horizontal delta since the previous event.
    /// Returns the scrub target, or nil while the touch has not moved past the tap slop.
    @discardableResult
    private func track(
        _ gesture: DragGesture.Value, width: CGFloat, trackCenterY: CGFloat
    ) -> Double? {
        let x = gesture.location.x
        var delta = x - lastDragX
        lastDragX = x

        let rate = PlayerTimelineScrubPolicy.rate(verticalDistance: gesture.location.y - trackCenterY)
        if rate != scrubRate { scrubRate = rate }

        if !hasMoved {
            let travel = gesture.translation.width
            guard PlayerTimelineScrubPolicy.isDeliberate(horizontalTravel: travel) else { return nil }
            hasMoved = true
            delta = PlayerTimelineScrubPolicy.travelPastSlop(travel)
        }
        let target = PlayerTimelineScrubPolicy.advanced(
            value: localValue,
            horizontalDelta: delta,
            trackWidth: width,
            rate: rate
        )
        localValue = target
        onDragValue?(target)
        return target
    }

    /// Single exit for the drag state; the rate is reset with it so the band haptic does
    /// not fire on release.
    private func finishDrag() {
        isDragging = false
        hasMoved = false
        if scrubRate != .full { scrubRate = .full }
    }

    private func scrubBubble(text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.subheadline.monospacedDigit().weight(.semibold))
            if let rateText = scrubRateText {
                Text(rateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
    }

    /// Language-neutral tag for the slow bands; nothing at full speed.
    private var scrubRateText: String? {
        switch scrubRate {
        case .full: return nil
        case .half: return "½×"
        case .quarter: return "¼×"
        }
    }
}

#Preview {
    ZStack {
        Color.black
        PlayerTimeline(
            value: .constant(0.42),
            onEditingChanged: { _ in },
            bufferedRange: 0.42...0.6,
            scrubLabel: { String(format: "%.0f%%", $0 * 100) }
        )
        .padding()
    }
}
