import Foundation

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

    /// The metrics the guide lays itself out with. Only the channel column
    /// follows the width class. The hour width is the same in both: the view
    /// model bakes it into the cell frames it precomputes, and the width class
    /// flips on rotation and on window resizes, which must not invalidate them.
    static func guide(regularWidth: Bool, textScale: CGFloat = 1) -> EPGGuideMetrics {
        var metrics = EPGGuideMetrics(compact: true)
        if regularWidth {
            metrics.channelColumnWidth = EPGGuideMetrics(compact: false).channelColumnWidth
        }
        // Keep the precomputed horizontal programme positions unchanged.
        let scale = min(max(textScale, 1), 1.5)
        metrics.rowHeight *= scale
        metrics.channelColumnWidth *= scale
        metrics.axisHeight *= scale
        metrics.headerHeight *= scale
        return metrics
    }

    /// X offset (points from midnight) for a given instant on the selected day.
    func x(for date: Date, dayStart: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * hourWidth
    }
}
