import Combine
import SwiftUI

/// Display arithmetic of the scrubber row, free of view state so it can be unit-tested
/// (same idea as `PlayerTimelineScrubPolicy`).
nonisolated enum PlayerScrubBarPolicy {
    /// A seek target counts as reached once playback reports a position this close to it
    /// (as a fraction of the duration).
    static let lockReleaseTolerance: Double = 0.035

    /// Where the thumb is drawn: the scrub target while dragging, the pinned seek target
    /// while a seek settles, the playback position otherwise.
    static func sliderPosition(
        isScrubbing: Bool,
        scrubValue: Double,
        lockedValue: Double?,
        clockPosition: Float
    ) -> Double {
        if isScrubbing { return scrubValue }
        if let lockedValue { return lockedValue }
        guard clockPosition.isFinite else { return 0 }
        return Double(min(max(clockPosition, 0), 1))
    }

    /// Elapsed time for the leading label. Follows the thumb, so label and thumb never
    /// disagree; without a duration there is nothing to scale and the clock is shown.
    static func elapsedMs(
        isScrubbing: Bool,
        scrubValue: Double,
        lockedValue: Double?,
        timeMs: Int64,
        durationMs: Int64
    ) -> Int {
        let duration = Double(durationMs)
        if duration > 0 {
            if isScrubbing { return Int(scrubValue * duration) }
            if let lockedValue { return Int(lockedValue * duration) }
        }
        return Int(timeMs)
    }

    /// True when the pinned seek target can be let go: playback has caught up with it.
    /// Never during a scrub, which owns the thumb.
    static func releasesLock(position: Float, lockedValue: Double?, isScrubbing: Bool) -> Bool {
        guard position.isFinite, !isScrubbing, let lockedValue else { return false }
        return abs(Double(position) - lockedValue) < lockReleaseTolerance
    }

    /// "m:ss", or "h:mm:ss" from one hour on.
    static func clockText(ms: Int) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Scrubber row of the fullscreen player: elapsed label, timeline and the duration /
/// remaining label.
///
/// It is the one view that observes the playback clock, and it keeps the live scrub
/// value to itself. A time tick and a scrub touch-move therefore re-evaluate this row
/// only, never the player body. On the FFmpeg path the main thread also presents the
/// video frames, so work saved there is picture smoothness.
///
/// The player keeps what it has to know and reset itself: the discrete `isScrubbing`
/// (it gates gestures and the chrome's auto-hide) and the pinned seek target.
struct PlayerScrubBar: View {
    @ObservedObject var clock: PlaybackClock
    let isSeekable: Bool
    /// A scrub is in progress. Owned by the player.
    let isScrubbing: Bool
    /// Seek target the thumb stays on until playback reports it. Owned by the player.
    let lockedValue: Double?
    /// False while the picture is on an AirPlay receiver: the engine's buffer says
    /// nothing about what the receiver holds.
    var showsBufferedRange: Bool = true
    /// The finger went down on the timeline.
    let onScrubBegan: () -> Void
    /// The scrub ended on a target (fraction of the duration): seek there.
    let onScrubEnded: (Double) -> Void
    /// The scrub ended without a target (a tap, a cancelled touch): do not seek.
    let onScrubCancelled: () -> Void
    /// Playback reached the pinned seek target.
    let onLockReleased: () -> Void
    /// VoiceOver adjustment, in seconds (positive is forward).
    let onAccessibilityJump: (Int) -> Void
    /// A control of this row was used: keep the chrome up.
    let onInteraction: () -> Void

    /// Trailing label: total duration, or time remaining after a tap on it.
    @AppStorage("player.showRemainingTime") private var showsRemainingTime = false
    /// Live scrub target. Local on purpose: it changes on every touch-move.
    @State private var scrubValue: Double = 0

    private var displayedSliderPosition: Double {
        PlayerScrubBarPolicy.sliderPosition(
            isScrubbing: isScrubbing,
            scrubValue: scrubValue,
            lockedValue: lockedValue,
            clockPosition: clock.position
        )
    }

    private var displayedElapsedMs: Int {
        PlayerScrubBarPolicy.elapsedMs(
            isScrubbing: isScrubbing,
            scrubValue: scrubValue,
            lockedValue: lockedValue,
            timeMs: clock.timeMs,
            durationMs: clock.durationMs
        )
    }

    /// Cached media ahead of the playhead, for the lighter stretch on the scrubber.
    private var bufferedRange: ClosedRange<Double>? {
        guard showsBufferedRange else { return nil }
        return PlayerTimelineScrubPolicy.bufferedRange(
            positionSeconds: Double(clock.timeMs) / 1000,
            cacheAheadSeconds: clock.cacheAheadSeconds,
            durationSeconds: Double(clock.durationMs) / 1000
        )
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { displayedSliderPosition },
            set: { scrubValue = $0 }
        )
    }

    private var totalDurationLabel: String {
        if clock.durationMs > 500 { return PlayerScrubBarPolicy.clockText(ms: Int(clock.durationMs)) }
        return "--:--"
    }

    /// The remaining-time preference only applies once a duration is known.
    private var isShowingRemainingTime: Bool {
        showsRemainingTime && clock.durationMs > 500
    }

    /// Follows the scrub target like the elapsed label, so both move together.
    private var displayedRemainingMs: Int {
        PlayerTimelineScrubPolicy.remainingMs(
            elapsedMs: displayedElapsedMs,
            durationMs: Int(clock.durationMs)
        )
    }

    private var trailingTimeLabel: String {
        isShowingRemainingTime
            ? "-" + PlayerScrubBarPolicy.clockText(ms: displayedRemainingMs)
            : totalDurationLabel
    }

    /// Spoken form of the trailing label ("1:23 remaining" / "Duration, 1:45:00"); the
    /// bare "-1:23" would be read as a negative number.
    private var trailingTimeAccessibilityLabel: String {
        if isShowingRemainingTime {
            return L("detail.remaining_format", PlayerScrubBarPolicy.clockText(ms: displayedRemainingMs))
        }
        return "\(L("movie.duration")), \(totalDurationLabel)"
    }

    /// iOS native player stili: kartsız, düz düzen; okunabilirlik alt gradient'ten gelir.
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(PlayerScrubBarPolicy.clockText(ms: displayedElapsedMs))
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
                .frame(minWidth: 52, alignment: .leading)

            PlayerTimeline(
                value: sliderBinding,
                isSeekable: isSeekable,
                onEditingChanged: { editing in
                    if editing {
                        // Taken before the player flips `isScrubbing`: from then on the
                        // displayed position IS the scrub value.
                        scrubValue = displayedSliderPosition
                        onScrubBegan()
                    } else {
                        onScrubEnded(scrubValue)
                    }
                },
                // The drag value stays in this row. The auto-hide timer is not re-armed
                // per touch-move: it waits by itself while a scrub is in progress.
                onDragValue: { scrubValue = $0 },
                // Also the exit for a touch that never moved: a tap on the track no
                // longer seeks.
                onEditingCancelled: { onScrubCancelled() },
                bufferedRange: bufferedRange,
                scrubLabel: { fraction in
                    PlayerScrubBarPolicy.clockText(ms: Int(fraction * Double(clock.durationMs)))
                }
            )
            .layoutPriority(1)
            // DragGesture VoiceOver altında erişilemez; kaydırıcıyı ayarlanabilir öğe
            // olarak sun (yan parlaklık/ses slider'larıyla aynı desen). ±15 sn adım,
            // mevcut goforward/gobackward.15 butonlarıyla tutarlı.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("player.a11y.playback_position"))
            .accessibilityIdentifier("player.timeline")
            .accessibilityValue(
                "\(PlayerScrubBarPolicy.clockText(ms: displayedElapsedMs)) / \(totalDurationLabel)"
            )
            .accessibilityAdjustableAction { direction in
                guard isSeekable else { return }
                switch direction {
                case .increment: onAccessibilityJump(15)
                case .decrement: onAccessibilityJump(-15)
                @unknown default: break
                }
            }

            // Tap switches between the total duration and the time remaining.
            Button {
                showsRemainingTime.toggle()
                onInteraction()
            } label: {
                Text(trailingTimeLabel)
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
                    // Full row height, so the small label is a comfortable tap target.
                    .frame(minWidth: 52, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(trailingTimeAccessibilityLabel)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        // Playback position is not mirrored in right-to-left languages (the system player
        // does the same). It also keeps the scrubber consistent: its fill and thumb are
        // drawn from the leading edge while the drag reads a left-origin x, so a mirrored
        // layout sent the thumb to the opposite side of the finger.
        .environment(\.layoutDirection, .leftToRight)
        // Lets go of the pinned seek target once playback has caught up with it. Lives
        // here because it follows the clock; the player's own timeout releases the pin
        // when this row is not on screen.
        .onReceive(clock.$position.removeDuplicates()) { newPosition in
            guard PlayerScrubBarPolicy.releasesLock(
                position: newPosition, lockedValue: lockedValue, isScrubbing: isScrubbing
            ) else { return }
            DispatchQueue.main.async { onLockReleased() }
        }
    }
}
