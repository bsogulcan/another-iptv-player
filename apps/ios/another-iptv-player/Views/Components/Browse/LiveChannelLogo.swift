import SwiftUI

/// A channel logo as panels send it: a mark on a transparent background, often wide.
/// It sits whole on a neutral plate instead of being cropped to a square, which cut
/// the edges off wide logos and lost dark ones on a light page.
struct LiveChannelLogo: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    var loadProfile: ImageLoadProfile = .grid

    static let cornerRadius: CGFloat = BrowseMetrics.tileCornerRadius

    /// The size the logo image is drawn and decoded at inside a plate of this size.
    /// Prefetchers ask for the same size, so the bitmap they warm is the one drawn.
    static func imageSize(width: CGFloat, height: CGFloat) -> CGSize {
        let inset = (min(width, height) * 0.14).rounded()
        return CGSize(width: width - inset * 2, height: height - inset * 2)
    }

    var body: some View {
        let image = Self.imageSize(width: width, height: height)
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground))
            .frame(width: width, height: height)
            .overlay {
                CachedImage(
                    url: url,
                    width: image.width,
                    height: image.height,
                    cornerRadius: 0,
                    contentMode: .fit,
                    iconName: "tv",
                    loadProfile: loadProfile
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }
}
