import SwiftUI

// MARK: - Environment distribution

private struct EPGSnapshotKey: EnvironmentKey {
    static let defaultValue: EPGSnapshot? = nil
}

extension EnvironmentValues {
    /// Now/next index for the active playlist, published once per minute by
    /// `EPGStore`. Injected once at the dashboard root so every card and the player
    /// overlay read it without per-card store observation. Its `Equatable` is a
    /// version compare, so environment invalidation is O(1).
    var epgSnapshot: EPGSnapshot? {
        get { self[EPGSnapshotKey.self] }
        set { self[EPGSnapshotKey.self] = newValue }
    }
}

// MARK: - Channel key resolution

/// Resolves a playlist channel to the key used to look up EPG now/next in the
/// snapshot. Prefers the explicit EPG id, falling back to the channel name (the
/// store publishes both id and name aliases for display-name-matched channels).
/// `nonisolated` so the M3U player-panel builders (which are `nonisolated`) can
/// call it.
nonisolated enum EPGChannelKey {
    static func forXtream(_ stream: DBLiveStream) -> String? {
        EPGConstants.normalizeChannelKey(stream.epgChannelId) ?? EPGConstants.normalizeChannelKey(stream.name)
    }

    static func forM3U(_ channel: DBM3UChannel) -> String? {
        EPGConstants.normalizeChannelKey(channel.tvgId) ?? EPGConstants.normalizeChannelKey(channel.tvgName ?? channel.name)
    }
}

// MARK: - Now/Next line (channel cards, side panel)

/// One compact line: current programme title + a thin progress capsule. Renders
/// nothing (or reserved blank space) when there's no now-playing programme.
struct EPGNowNextLine: View {
    let nowNext: EPGNowNext?
    let width: CGFloat
    var reserveSpace: Bool = false
    var tint: Color = .accentColor
    var textColor: Color = .secondary

    /// Keep the placeholder and populated state exactly the same height. The old
    /// 16pt placeholder was shorter than caption + spacing + bar, so shelves that
    /// were laid out before EPG arrived could clip the progress capsule.
    private var reservedHeight: CGFloat { 22 }

    var body: some View {
        if let now = nowNext?.now {
            VStack(alignment: .leading, spacing: 3) {
                Text(now.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(textColor)
                    .frame(width: width, alignment: .leading)
                progressCapsule(for: now)
            }
            .frame(width: width, height: reservedHeight, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("epg.a11y.now_playing_format", now.title))
        } else if reserveSpace {
            Color.clear.frame(width: width, height: reservedHeight)
        }
    }

    @ViewBuilder
    private func progressCapsule(for programme: EPGProgramme) -> some View {
        let fraction = programme.progress(at: Date()) ?? 0
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.18)).frame(width: width, height: 3)
            Capsule().fill(tint).frame(width: max(0, width * fraction), height: 3)
        }
        .frame(width: width, height: 3)
    }
}

// MARK: - Player programme strip (top chrome)

/// Programme title stacked above its "HH:mm – HH:mm" range and a progress capsule,
/// shown while watching a live channel.
struct PlayerProgrammeStrip: View {
    let programme: EPGProgramme
    /// Programme after `programme`, shown as a "Next: …" line when known.
    var next: EPGProgramme? = nil
    var tint: Color = .white

    /// Width the progress capsule fills within the strip. The player passes a smaller
    /// one when the strip itself is capped below it, so the capsule's end is not cut.
    var barWidth: CGFloat = PlayerProgrammeStripLayout.defaultBarWidth

    /// "Next: 21:00 Title". Shared with the player's channel banner.
    static func nextLine(_ programme: EPGProgramme) -> String {
        L("epg.next_format", "\(EPGTimeFormat.time(programme.start)) \(programme.title)")
    }

    var body: some View {
        let fraction = programme.progress(at: Date()) ?? 0

        VStack(alignment: .leading, spacing: 5) {
            Text(programme.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                // One title line when the "next" line is shown: the strip keeps its
                // height, which the failure banner and the brightness capsule above
                // this corner are laid out around.
                .lineLimit(next == nil ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)

            Text(EPGTimeFormat.range(programme.start, programme.stop))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.72))

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22)).frame(width: barWidth, height: 3)
                Capsule().fill(tint).frame(width: max(0, barWidth * fraction), height: 3)
            }
            .frame(width: barWidth, height: 3)

            if let next {
                Text(Self.nextLine(next))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

/// Width of the player's programme strip, kept free of view state so it can be
/// unit-tested. The strip sits in the bottom leading corner of the chrome and the live
/// channel row (skip, channel list, ...) in the bottom trailing one, at the same height:
/// on a narrow screen the strip has to end before the row begins.
nonisolated enum PlayerProgrammeStripLayout {
    /// Width the strip may take when nothing is in its way.
    static let defaultMaxWidth: CGFloat = 240
    /// Never narrower than this; the title is truncated rather than squeezed away.
    static let minimumMaxWidth: CGFloat = 120
    static let defaultBarWidth: CGFloat = 188

    /// Side of one round chrome button and the spacing between two of them.
    static let rowButtonSide: CGFloat = 44
    static let rowButtonSpacing: CGFloat = 8
    /// From the container's trailing safe-area edge to the row's last button: the
    /// chrome's 12 pt padding plus the row's own 12 pt.
    static let rowTrailingInset: CGFloat = 24
    /// From the container's leading safe-area edge to the strip.
    static let stripLeadingInset: CGFloat = 20
    /// Clear space kept between the strip and the first button of the row.
    static let gapToRow: CGFloat = 12

    /// - Parameters:
    ///   - containerWidth: full width of the player, safe-area insets included.
    ///   - rowButtonCount: buttons in the live channel row; 0 when the row is not shown.
    static func maxWidth(
        containerWidth: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        rowButtonCount: Int
    ) -> CGFloat {
        guard rowButtonCount > 0, containerWidth.isFinite else { return defaultMaxWidth }
        let count = CGFloat(rowButtonCount)
        let rowWidth = count * rowButtonSide + (count - 1) * rowButtonSpacing
        let rowLeading = containerWidth - trailingInset - rowTrailingInset - rowWidth
        let available = rowLeading - gapToRow - (stripLeadingInset + leadingInset)
        return min(defaultMaxWidth, max(minimumMaxWidth, available))
    }

    /// The progress capsule never outgrows the strip it sits in.
    static func barWidth(stripMaxWidth: CGFloat) -> CGFloat {
        min(defaultBarWidth, max(0, stripMaxWidth))
    }
}

// MARK: - Time formatting

enum EPGTimeFormat {
    /// "20:30" in the device locale/timezone (24h or 12h per locale).
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "20:30 – 21:00"
    static func range(_ start: Date, _ stop: Date) -> String {
        "\(time(start)) – \(time(stop))"
    }
}

// MARK: - Guide layout metrics

struct EPGGuideMetrics: Equatable {
    var hourWidth: CGFloat
    var rowHeight: CGFloat
    var channelColumnWidth: CGFloat
    var axisHeight: CGFloat
    var headerHeight: CGFloat

    var dayWidth: CGFloat { hourWidth * 24 }

    init(compact: Bool) {
        hourWidth = compact ? 150 : 180
        rowHeight = 56
        channelColumnWidth = compact ? 104 : 172
        axisHeight = 28
        headerHeight = 34
    }

    /// X offset (points from midnight) for a given instant on the selected day.
    func x(for date: Date, dayStart: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * hourWidth
    }
}
