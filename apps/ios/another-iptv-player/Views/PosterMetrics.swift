import SwiftUI
import UIKit

/// iPad 11" (portrait kısa kenar ~834 pt) tasarım ölçüsü; daha dar ekranlarda posterler orantılı küçülür.
struct PosterMetrics: Equatable, Sendable {
    /// 1.0 = referans cihaz; telefonlarda ~0.5–0.65.
    let layoutScale: CGFloat

    init(windowSize: CGSize) {
        let referenceShortSide: CGFloat = 834
        let short = min(windowSize.width, windowSize.height)
        let raw = short / referenceShortSide
        layoutScale = min(1, max(0.5, raw))
    }

    var shelfPosterWidth: CGFloat { scaled(200) }
    var shelfPosterHeight: CGFloat { scaled(300) }

    var categoryGridPosterWidth: CGFloat { scaled(200) }
    var categoryGridPosterHeight: CGFloat { scaled(300) }

    var searchGridMinWidth: CGFloat { scaled(110) }
    var searchCardWidth: CGFloat { scaled(160) }
    var searchCardHeight: CGFloat { scaled(240) }

    var liveShelfIcon: CGFloat { scaled(112) }
    var liveShelfLabelWidth: CGFloat { scaled(116) }
    var liveGridIconSize: CGFloat { scaled(180) }


    var searchLiveRowIcon: CGFloat { scaled(50) }
    var searchLiveRowLeadingInset: CGFloat { scaled(50) + 20 }

    var seriesDetailHeroWidth: CGFloat { scaled(118) }
    var seriesDetailHeroHeight: CGFloat { scaled(176) }

    var seasonStripWidth: CGFloat { scaled(120) }
    var seasonStripHeight: CGFloat { scaled(180) }

    var episodeThumbWidth: CGFloat { scaled(100) }
    var episodeThumbHeight: CGFloat { scaled(150) }
    var episodeRowDividerLeading: CGFloat { scaled(100) + 28 }

    var gridSpacing: CGFloat { scaled(16) }
    var gridRowSpacing: CGFloat { scaled(20) }
    var searchGridSpacing: CGFloat { scaled(12) }
    var searchSectionRowSpacing: CGFloat { scaled(16) }

    /// Raf satırı: poster + başlık alanı (yaklaşık 2 satır caption).
    var shelfRowTotalHeight: CGFloat { shelfPosterHeight + scaled(64) }

    /// Shelf row height for a caption block the caller measures in text units (for example
    /// with `@ScaledMetric(relativeTo: .caption)`). The poster shrinks with the screen, the
    /// title under it does not, so the two parts cannot share one scale factor.
    func shelfRowHeight(captionBlock: CGFloat) -> CGFloat {
        shelfPosterHeight + captionBlock
    }

    /// Cap for the decoded side of a channel logo, in pixels.
    static let logoDecodePixelCap: CGFloat = 256

    /// One decode side, in points, for channel logos wherever they are drawn (pass it as
    /// `decodeWidth` / `decodeHeight` and as the prefetch size). A logo decoded once is
    /// then a memory hit on every screen instead of one bitmap per display size. It follows
    /// the largest logo tile but is capped in pixels, so an iPad does not hold 360 px
    /// bitmaps for 32 pt cells. Meant for the profiles that decode at up to 2x.
    var logoDecodeSide: CGFloat {
        let cap = (Self.logoDecodePixelCap / CachedImage.decodeScale(for: .grid)).rounded(.down)
        return min(liveGridIconSize, cap)
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        (base * layoutScale).rounded(.toNearestOrAwayFromZero)
    }
}

private struct PosterMetricsKey: EnvironmentKey {
    static var defaultValue: PosterMetrics {
        PosterMetrics(windowSize: UIScreen.main.bounds.size)
    }
}

extension EnvironmentValues {
    var posterMetrics: PosterMetrics {
        get { self[PosterMetricsKey.self] }
        set { self[PosterMetricsKey.self] = newValue }
    }
}
