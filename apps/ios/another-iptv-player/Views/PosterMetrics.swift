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

    /// Kategori detay grid'i için prefetch boyutu (.grid profiliyle eşleşir)
    func prefetchCategoryDecodePixelSize() -> CGSize {
        let s = min(UIScreen.main.scale, 2)
        return CGSize(
            width: ceil(categoryGridPosterWidth * s),
            height: ceil(categoryGridPosterHeight * s)
        )
    }

    /// Yatay raf önizlemesi için prefetch boyutu (.shelf profiliyle eşleşir)
    func prefetchShelfDecodePixelSize() -> CGSize {
        let s = min(UIScreen.main.scale, 2)
        return CGSize(
            width: ceil(shelfPosterWidth * s),
            height: ceil(shelfPosterHeight * s)
        )
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
