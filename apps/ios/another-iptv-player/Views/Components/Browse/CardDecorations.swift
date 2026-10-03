import SwiftUI

/// Watch progress drawn over the artwork of a card: a thin capsule track with the
/// watched part filled in the tint colour.
///
/// Meant for an overlay on the artwork, with the caller's inset:
///
///     CachedImage(...)
///         .overlay(alignment: .bottom) {
///             CardProgressBar(fraction: progress).padding(6)
///         }
///
/// The bar takes the width it is offered and a fixed height, so as an overlay it can
/// never change the size of the card. A bar that sat next to the artwork in a stack,
/// with its own width and padding, made a watched poster wider than an unwatched one
/// and pushed it out of line with its neighbours.
///
/// No `GeometryReader`: the fill is a full-width rectangle scaled from the leading
/// edge and clipped by the track, which costs nothing per card while scrolling.
struct CardProgressBar: View {
    private let fraction: CGFloat

    static let height: CGFloat = 3

    /// - Parameter fraction: watched share, clamped to 0...1. Anything that is not a
    ///   number (a duration of zero divided through) counts as nothing watched.
    init(fraction: Double) {
        self.fraction = fraction.isFinite ? CGFloat(min(max(fraction, 0), 1)) : 0
    }

    var body: some View {
        Capsule()
            .fill(Color.black.opacity(0.45))
            .frame(height: Self.height)
            .overlay {
                Rectangle()
                    .fill(.tint)
                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
            }
            .clipShape(Capsule())
            // A scale anchor is a point of the view, not of the layout, so it stays
            // on the left in a right-to-left layout. Mirroring the finished bar
            // makes it fill from the leading edge there too, as the bars it
            // replaces did.
            .flipsForRightToLeftLayoutDirection(true)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Title under a poster (movies, series): caption, medium, leading-aligned under
    /// the artwork's leading edge.
    ///
    /// Two lines are always reserved. Cards with a short and a long title then have
    /// the same height, so posters in one grid row or shelf stay on one line and a
    /// shelf can know its height before its items arrive.
    func posterTitleStyle(width: CGFloat) -> some View {
        cardTitleStyle(width: width, alignment: .leading)
    }

    /// Title under a channel tile: as `posterTitleStyle(width:)`, but centred under
    /// the square logo.
    func tileTitleStyle(width: CGFloat) -> some View {
        cardTitleStyle(width: width, alignment: .center)
    }

    private func cardTitleStyle(width: CGFloat, alignment: HorizontalAlignment) -> some View {
        self
            .font(.caption)
            .fontWeight(.medium)
            // Explicit, so the title keeps the label colour inside a link that
            // still has the default (tinting) button style.
            .foregroundStyle(Color.primary)
            .lineLimit(2, reservesSpace: true)
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .frame(width: width, alignment: Alignment(horizontal: alignment, vertical: .top))
    }
}

/// Shelf artwork follows the window; its caption allowance follows Dynamic Type.
private struct PosterShelfFrame: ViewModifier {
    @Environment(\.posterMetrics) private var metrics
    @ScaledMetric(relativeTo: .caption) private var captionBlock: CGFloat = 40

    func body(content: Content) -> some View {
        content.frame(height: metrics.shelfRowHeight(captionBlock: captionBlock))
    }
}

extension View {
    func posterShelfFrame() -> some View { modifier(PosterShelfFrame()) }
}
