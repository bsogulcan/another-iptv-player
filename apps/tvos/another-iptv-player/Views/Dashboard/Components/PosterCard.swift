import SwiftUI
import NukeUI

/// Portrait poster card (2:3) used for Movies and Series on tvOS.
///
/// Only the poster image is wrapped in `.buttonStyle(.card)` so the tvOS
/// focus lift/glow applies to the poster. The title lives *outside* the
/// button — that way long titles wrap freely and never get clipped by the
/// card's transform or rounded corners.
struct PosterCard: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    var posterWidth: CGFloat = 280
    let action: () -> Void

    private var posterHeight: CGFloat { posterWidth * 1.5 }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Button(action: action) {
                posterImage
                    .frame(width: posterWidth, height: posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.card)

            VStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }
            .frame(width: posterWidth)
        }
    }

    /// Explicit `frame(width:height:)` instead of `aspectRatio` — the iPad
    /// version uses the same pattern and it's the only way to guarantee every
    /// card renders at identical 2:3 dimensions regardless of the source
    /// image's intrinsic size. `scaledToFill` + `.clipped` crops content that
    /// doesn't match 2:3 rather than letting it deform the frame.
    @ViewBuilder
    private var posterImage: some View {
        if let url = imageURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else if state.error != nil {
                    placeholder
                } else {
                    placeholder.overlay { ProgressView() }
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            }
    }
}

/// Landscape card (16:9) used for live channels. Same poster-outside-title
/// structure as `PosterCard` so names never get truncated.
struct ChannelCard: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                channelImage
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var channelImage: some View {
        if let url = imageURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else if state.error != nil {
                    placeholder
                } else {
                    placeholder.overlay { ProgressView() }
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                Image(systemName: "tv")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            }
    }
}
