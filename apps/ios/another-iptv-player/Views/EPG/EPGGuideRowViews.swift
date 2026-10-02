import SwiftUI

/// One channel's programme strip. `Equatable` on (channelKey, layout version) so
/// cells never re-render during scroll — only the four synced overlays in the
/// parent move.
struct EPGChannelRowView: View, Equatable {
    let channelKey: String
    let layout: EPGRowLayout
    let metrics: EPGGuideMetrics
    let onTap: (EPGProgramme) -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    static func == (lhs: EPGChannelRowView, rhs: EPGChannelRowView) -> Bool {
        lhs.channelKey == rhs.channelKey
            && lhs.layout.version == rhs.layout.version
            && lhs.metrics == rhs.metrics
    }

    var body: some View {
        // Cell labels stay clear of the pinned channel column. The cells are placed
        // with offsets that do not mirror, so right-to-left keeps the plain layout.
        let pinnedLeading: CGFloat? = layoutDirection == .leftToRight ? metrics.channelColumnWidth : nil
        ZStack(alignment: .topLeading) {
            ForEach(layout.cells) { cell in
                EPGProgrammeCell(cell: cell, height: metrics.rowHeight, pinnedLeading: pinnedLeading)
                    .frame(width: cell.width, height: metrics.rowHeight)
                    .offset(x: cell.x)
                    .onTapGesture {
                        if let programme = cell.programme { onTap(programme) }
                    }
            }
        }
        .frame(width: metrics.dayWidth, height: metrics.rowHeight, alignment: .topLeading)
    }
}

struct EPGProgrammeCell: View {
    let cell: EPGCellLayout
    let height: CGFloat
    /// X of the visible leading edge inside the horizontal scroller (the width of
    /// the pinned channel column). Nil leaves the label at the start of the cell.
    var pinnedLeading: CGFloat? = nil

    /// Narrower cells keep their label where it is: there is no room to move it in.
    /// Same width from which a cell shows its time line.
    private static let pinnedLabelMinWidth: CGFloat = 64
    /// What a pinned label always keeps of its cell, so it leaves with the cell
    /// instead of sliding out of it.
    private static let pinnedLabelMinVisible: CGFloat = 44

    /// The label follows the visible edge only in cells that can hold it there.
    private var labelPin: CGFloat? {
        guard let pinnedLeading, cell.width >= Self.pinnedLabelMinWidth else { return nil }
        return pinnedLeading
    }

    var body: some View {
        Group {
            if let programme = cell.programme {
                VStack(alignment: .leading, spacing: 2) {
                    Text(programme.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if cell.width >= 64 {
                        Text(EPGTimeFormat.time(programme.start))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .pinnedToVisibleLeading(labelPin, minVisible: Self.pinnedLabelMinVisible)
                .background(Color(.secondarySystemFill))
            } else {
                Text(L("epg.no_data.programme_cell"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .pinnedToVisibleLeading(labelPin, minVisible: Self.pinnedLabelMinVisible)
                    .background(Color(.tertiarySystemFill).opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        .padding(.horizontal, 1)
    }
}

private extension View {
    /// Keeps a cell's label readable while the cell's start is scrolled out of
    /// view: a programme that began hours ago, or a channel without data, would
    /// otherwise be a blank bar at the current time.
    ///
    /// Applied to the label at the cell's full size and before the background, so
    /// the geometry is the cell's and only the label moves. The shift is a render
    /// effect computed from the scroll geometry: no state, no body pass, and the
    /// row around it stays skipped by its `Equatable`. The cell's clip shape cuts
    /// what the shifted label pushes past the trailing edge.
    @ViewBuilder
    func pinnedToVisibleLeading(_ pinnedLeading: CGFloat?, minVisible: CGFloat) -> some View {
        if let pinnedLeading {
            visualEffect { [pinnedLeading, minVisible] content, proxy in
                let hidden = pinnedLeading - proxy.frame(in: .scrollView(axis: .horizontal)).minX
                return content.offset(x: min(max(0, hidden), max(0, proxy.size.width - minVisible)))
            }
        } else {
            self
        }
    }
}

/// The day chips above the grid. `Equatable` on its two inputs: the guide's body
/// runs on every horizontal scroll frame, and the chips (calendar checks and date
/// formatting per chip) have nothing to do with that.
struct EPGDayPicker: View, Equatable {
    let days: [Date]
    let selectedDay: Date
    let onSelect: (Date) -> Void

    /// Counts the user's day changes, so the haptic plays for a tap and not for
    /// the guide moving on to a new day by itself.
    @State private var dayChanges = 0

    static func == (lhs: EPGDayPicker, rhs: EPGDayPicker) -> Bool {
        lhs.days == rhs.days && lhs.selectedDay == rhs.selectedDay
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    FilterChip(EPGTimeFormat.dayLabel(day, wide: false), isSelected: isSelected, compact: true) {
                        guard !isSelected else { return }
                        dayChanges += 1
                        onSelect(day)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .sensoryFeedback(.selection, trigger: dayChanges)
    }
}

/// Hour ticks + labels across the selected day.
struct EPGTimeAxisView: View {
    let dayStart: Date
    let metrics: EPGGuideMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { hour in
                let date = dayStart.addingTimeInterval(Double(hour) * 3600)
                Text(EPGTimeFormat.time(date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: metrics.hourWidth, alignment: .leading)
                    .padding(.leading, 4)
                    .offset(x: CGFloat(hour) * metrics.hourWidth)
            }
        }
        .frame(width: metrics.dayWidth, height: metrics.axisHeight, alignment: .leading)
    }
}

/// Collapsible category header spanning the guide's visible width. Tapping toggles
/// the category's channels. `width` is the current viewport width so the header
/// stays pinned to the left edge while the body scrolls horizontally.
struct EPGCategoryHeader: View {
    let title: String
    let channelCount: Int
    let collapsed: Bool
    let width: CGFloat
    let height: CGFloat
    let onToggle: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                // Collapsed, the chevron points forward: right, or left in a
                // right-to-left language.
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(collapsed ? (layoutDirection == .rightToLeft ? 90 : -90) : 0))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(channelCount)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: width, height: height, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            // A hairline with an explicit height: inside the button's label a
            // `Divider` takes the vertical orientation and runs down the middle.
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(.separator)).frame(height: 1 / displayScale)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(collapsed ? L("epg.categories.collapsed_a11y") : L("epg.categories.expanded_a11y"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Channel column cell (sticky leading, per row). `Equatable` (on row + metrics,
/// ignoring closures) so the sticky `.offset(x:)` can update during scroll without
/// rebuilding the cell — critical for large playlists.
///
/// A tap plays the channel; the context menu offers the same and the channel's
/// schedule. A button rather than gesture recognisers, so the scroller's pans win
/// over it the way they do over any other control.
struct EPGChannelColumnCell: View, Equatable {
    let row: EPGGuideRow
    let metrics: EPGGuideMetrics
    let onPlay: () -> Void
    let onSchedule: () -> Void

    static func == (lhs: EPGChannelColumnCell, rhs: EPGChannelColumnCell) -> Bool {
        lhs.row == rhs.row && lhs.metrics == rhs.metrics
    }

    var body: some View {
        Button(action: onPlay) {
            label
        }
        .buttonStyle(.dimPress)
        .contextMenu {
            PlayMenuButton(action: onPlay)
            ScheduleMenuButton(action: onSchedule)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            // `.grid` profile: the request survives cell recycling (the default
            // `.standard` cancels on disappear, which starves logos as rows and
            // sticky labels churn during scroll/virtualization).
            CachedImage(url: row.iconURL, width: 32, height: 32, cornerRadius: 6, iconName: "tv", loadProfile: .grid)
            Text(row.displayName)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: metrics.channelColumnWidth, height: metrics.rowHeight, alignment: .leading)
        .background(.regularMaterial)
        .contentShape(Rectangle())
    }
}
