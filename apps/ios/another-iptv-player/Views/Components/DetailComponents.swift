import SwiftUI

// MARK: - Hero Config

struct DetailHeroConfig {
    var title: String
    var backdropURL: URL?
    var posterURL: URL?
    var year: String?
    var runtime: String?
    var rating10: Double?
    var ratingText: String?
    var posterIconName: String
    var backdropIconName: String
}

// MARK: - Cinematic Hero

struct DetailHero: View {
    let config: DetailHeroConfig
    var heroHeight: CGFloat = 380
    var onPosterTap: ((URL) -> Void)? = nil

    @Environment(\.posterMetrics) private var metrics

    private var resolvedBackdropURL: URL? {
        config.backdropURL ?? config.posterURL
    }

    private var backdropIsFallback: Bool {
        config.backdropURL == nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdropLayer
            gradientLayer
            overlayLayer
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private var backdropLayer: some View {
        if let url = resolvedBackdropURL {
            let h = heroHeight
            GeometryReader { proxy in
                CachedImage(
                    url: url,
                    width: proxy.size.width,
                    height: h,
                    cornerRadius: 0,
                    contentMode: .fill,
                    iconName: config.backdropIconName,
                    loadProfile: .high
                )
                .frame(width: proxy.size.width, height: h)
                .blur(radius: backdropIsFallback ? 28 : 0)
                .opacity(backdropIsFallback ? 0.55 : 1)
                .visualEffect { content, proxy in
                    let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
                    let overscroll = max(0, minY)
                    let parallax = min(0, minY * 0.18)
                    return content
                        .scaleEffect(1 + overscroll / h, anchor: .bottom)
                        .offset(y: parallax)
                }
            }
            .frame(height: heroHeight)
        } else {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.28),
                    Color(UIColor.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight)
        }
    }

    private var gradientLayer: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.5),
                .init(color: Color(UIColor.systemBackground).opacity(0.78), location: 0.85),
                .init(color: Color(UIColor.systemBackground), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: heroHeight)
        .allowsHitTesting(false)
    }

    private var overlayLayer: some View {
        HStack(alignment: .bottom, spacing: 16) {
            CachedImage(
                url: config.posterURL,
                width: metrics.seriesDetailHeroWidth,
                height: metrics.seriesDetailHeroHeight,
                cornerRadius: 14,
                contentMode: .fill,
                iconName: config.posterIconName
            )
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = config.posterURL {
                    onPosterTap?(url)
                }
            }
            .allowsHitTesting(config.posterURL != nil)

            VStack(alignment: .leading, spacing: 10) {
                Text(config.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                DetailHeroMetaRow(
                    year: config.year,
                    runtime: config.runtime,
                    rating10: config.rating10,
                    ratingText: config.ratingText
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }
}

private struct DetailHeroMetaRow: View {
    let year: String?
    let runtime: String?
    let rating10: Double?
    let ratingText: String?

    var body: some View {
        HStack(spacing: 10) {
            if let rating10, rating10 > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating10))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
            } else if let ratingText, !ratingText.isEmpty {
                RatingLabel(rating: ratingText, style: .standard)
            }

            if let year, !year.isEmpty {
                Text(year)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let runtime, !runtime.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(runtime)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Action Bar

struct DetailActionBar: View {
    let primaryTitle: String
    var primarySubtitle: String? = nil
    var primaryIcon: String = "play.fill"
    var progress: Double? = nil
    let onPrimary: () -> Void

    var restartTitle: String? = nil
    var onRestart: (() -> Void)? = nil

    var trailerURL: URL? = nil

    var body: some View {
        VStack(spacing: 10) {
            primaryCTA
            secondaryRow
        }
        .padding(.horizontal, 16)
    }

    private var primaryCTA: some View {
        Button(action: onPrimary) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: primaryIcon)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(primaryTitle)
                            .font(.subheadline.weight(.bold))
                        if let sub = primarySubtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.caption2)
                                .opacity(0.82)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(.white)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }
            }
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var secondaryRow: some View {
        let hasRestart = onRestart != nil && restartTitle != nil
        let hasTrailer = trailerURL != nil
        if hasRestart || hasTrailer {
            HStack(spacing: 10) {
                if let onRestart, let restartTitle {
                    DetailSecondaryButton(icon: "arrow.counterclockwise", title: restartTitle, action: onRestart)
                }
                if let trailerURL {
                    Link(destination: trailerURL) {
                        DetailSecondaryLabel(icon: "play.rectangle.on.rectangle", title: "Fragman")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DetailSecondaryButton: View {
    let icon: String
    let title: String
    var tinted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DetailSecondaryLabel(icon: icon, title: title, tinted: tinted)
        }
        .buttonStyle(.plain)
    }
}

private struct DetailSecondaryLabel: View {
    let icon: String
    let title: String
    var tinted: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tinted ? Color.yellow : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Genre chips

struct GenreChipRow: View {
    let genres: [String]

    var body: some View {
        if !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(genres, id: \.self) { g in
                        Text(g)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Plot block

struct DetailPlotBlock: View {
    let plot: String
    private static let collapsedLineLimit = 5

    @State private var expanded = false
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool {
        fullHeight > limitedHeight + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("movie.plot"))
                .font(.headline)
                .foregroundStyle(.primary)

            Text(plot)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : Self.collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: expanded)
                .background(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Text(plot)
                            .font(.subheadline)
                            .lineLimit(Self.collapsedLineLimit)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newValue in
                                limitedHeight = newValue
                            }
                        Text(plot)
                            .font(.subheadline)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newValue in
                                fullHeight = newValue
                            }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }

            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Daha az" : "Daha fazla")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

// MARK: - Info text block (director, cast, etc.)

struct DetailInfoTextBlock: View {
    let label: String
    let value: String
    var lineLimit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

// MARK: - Season tab bar

struct DetailSeasonTabBar: View {
    let seasons: [DBSeason]
    @Binding var selectedId: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        let isSelected = selectedId == season.id
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedId = season.id
                            }
                        } label: {
                            Text(season.name ?? "Sezon \(season.seasonNumber)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor : Color.clear)
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? Color.clear : Color.primary.opacity(0.14),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .id(season.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedId) { _, new in
                guard let new else { return }
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }
}

// MARK: - Formatting helpers

enum DetailFormatting {
    static func year(from releaseDate: String?) -> String? {
        guard let raw = releaseDate?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let prefix = raw.prefix(4)
        return prefix.count == 4 && prefix.allSatisfy({ $0.isNumber }) ? String(prefix) : raw
    }

    static func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(ms, 0) / 1000
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func seriesRuntime(_ raw: String?) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty, r != "0" else { return nil }
        if r.contains("m") || r.contains("h") { return r }
        if let minutes = Int(r) {
            if minutes >= 60 {
                let h = minutes / 60
                let m = minutes % 60
                return m > 0 ? "\(h)s \(m)dk" : "\(h)s"
            }
            return "\(minutes) dk"
        }
        return r
    }

    static func genreList(_ raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return [] }
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
