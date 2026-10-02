import CoreGraphics

/// Layout constants the browse screens (Live TV, Movies, Series, M3U, Favorites,
/// History) share. Sizes that follow the window live in `PosterMetrics`; these are
/// the ones that stay the same on every device.
///
/// `nonisolated`: plain numbers, also read where prefetch sizes are computed off the
/// main actor.
nonisolated enum BrowseMetrics {
    /// Leading and trailing inset of shelf headers, shelf content and grids. It is
    /// the inset of the large navigation title on iPhone, so a header, its first
    /// card and the title above them share one edge.
    static let pageMargin: CGFloat = 16

    /// Corner radius of poster artwork (movies, series).
    static let posterCornerRadius: CGFloat = 8
    /// Corner radius of channel tiles and landscape cards.
    static let tileCornerRadius: CGFloat = 12

    /// Space between two posters of a shelf.
    static let posterShelfSpacing: CGFloat = 14
    /// Space between two channel tiles of a shelf.
    static let tileShelfSpacing: CGFloat = 12

    /// Height a poster shelf has to keep free under the artwork for a title styled
    /// with `posterTitleStyle(width:)`: the 8 pt gap of the card's stack plus two
    /// caption lines at the default text size. Scale it with the text before use
    /// (`@ScaledMetric(relativeTo: .caption)`), then pass it to
    /// `PosterMetrics.shelfRowHeight(captionBlock:)`.
    static let posterCaptionBlock: CGFloat = 40
}
