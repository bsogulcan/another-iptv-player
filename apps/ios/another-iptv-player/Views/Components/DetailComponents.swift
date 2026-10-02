import SwiftUI
import Nuke
import NukeUI

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// The poster as the hero shows it. One place builds it, so the request another
    /// screen asks for (`posterRequest`) cannot drift from what is on screen.
    ///
    /// It is decoded at the size of the shelf and grid cards, not at its own smaller
    /// size: the card the user just tapped left that bitmap in memory, so the poster is
    /// there in the first frame of the push instead of loading a second time.
    private static func posterImage(url: URL?, iconName: String, metrics: PosterMetrics) -> CachedImage {
        CachedImage(
            url: url,
            width: metrics.seriesDetailHeroWidth,
            height: metrics.seriesDetailHeroHeight,
            cornerRadius: 14,
            contentMode: .fill,
            iconName: iconName,
            decodeWidth: metrics.categoryGridPosterWidth,
            decodeHeight: metrics.categoryGridPosterHeight,
            // The poster opens the full-screen viewer, so it has to stay reachable
            // for VoiceOver; without artwork there is nothing to open.
            isDecorative: url == nil
        )
    }

    /// The request under which the hero poster of `url` is in memory. Hand it to
    /// `FullscreenImageViewer` so that the viewer opens on the poster.
    static func posterRequest(url: URL, metrics: PosterMetrics) -> ImageRequest {
        posterImage(url: url, iconName: "photo", metrics: metrics).makeRequest(url: url)
    }

    @ViewBuilder
    private var backdropLayer: some View {
        if config.posterURL != nil || config.backdropURL != nil {
            let h = heroHeight
            // `visualEffect` runs off the main actor and cannot read the environment.
            let parallaxFactor: CGFloat = reduceMotion ? 0 : 0.18
            GeometryReader { proxy in
                ZStack {
                    backdropUnderlay(width: proxy.size.width)
                    if let backdropURL = config.backdropURL {
                        HeroBackdropImage(url: backdropURL, width: proxy.size.width, height: h)
                    }
                }
                .frame(width: proxy.size.width, height: h)
                .visualEffect { content, proxy in
                    let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
                    // The stretch follows the finger and stays; the drift against the
                    // page is decoration and goes away with Reduce Motion.
                    let overscroll = max(0, minY)
                    let parallax = min(0, minY * parallaxFactor)
                    return content
                        .scaleEffect(1 + overscroll / h, anchor: .bottom)
                        .offset(y: parallax)
                }
            }
            .frame(height: heroHeight)
        } else {
            fallbackGradient
                .frame(height: heroHeight)
        }
    }

    /// What is behind the real backdrop, and all there is when a title has none: the
    /// poster as a soft colour wash. It stays in place when the backdrop arrives, so the
    /// hero never passes through a placeholder between the two.
    @ViewBuilder
    private func backdropUnderlay(width: CGFloat) -> some View {
        if let posterURL = config.posterURL {
            CachedImage(
                url: posterURL,
                width: width,
                height: heroHeight,
                cornerRadius: 0,
                contentMode: .fill,
                iconName: config.backdropIconName,
                // Blurred beyond recognition, so the card-sized bitmap that is already
                // in memory is enough; it also keeps the request independent of the
                // live width.
                decodeWidth: metrics.categoryGridPosterWidth,
                decodeHeight: metrics.categoryGridPosterHeight
            )
            .blur(radius: 28)
            // The blur spreads past the frame. Without the clip its halo shows below the
            // hero, where the gradient that fades the image out has already ended.
            // Clipping before `visualEffect` leaves the overscroll stretch alone.
            .clipped()
            .opacity(0.55)
        } else {
            fallbackGradient
        }
    }

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.28),
                Color(UIColor.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
            Self.posterImage(url: config.posterURL, iconName: config.posterIconName, metrics: metrics)
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
                .accessibilityLabel(config.title)
                .accessibilityAddTraits(config.posterURL != nil ? .isButton : [])

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

/// The real backdrop, drawn over the blurred poster. It draws nothing until the image is
/// there, so the poster stays visible underneath instead of a placeholder, and a backdrop
/// that arrives from disk or the network fades in over it. A backdrop URL that is dead,
/// which is common on these panels, simply leaves the poster.
///
/// `CachedImage` cannot be used for this layer: it always draws its tile and glyph while
/// it loads.
private struct HeroBackdropImage: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat

    @StateObject private var model = FetchImage()
    /// `ImageHostReopenings.epoch` when the current load started. Never read in `body`.
    @State private var epochAtLoad = 0
    @Environment(\.scenePhase) private var scenePhase

    /// The reopening count while the backdrop is missing because the host breaker
    /// refused its request, nil otherwise, as in `CachedImage`. Backdrops usually live on
    /// another host than the panel's posters, so this one can be blocked on its own.
    private var refusalEpoch: Int? {
        guard case .failure(let error) = model.result, ImageHostBlocked.isCause(of: error) else { return nil }
        return ImageHostReopenings.shared.epoch
    }

    /// Decode width in points. Taken from the screen, not from the live width of the
    /// hero, so a rotation or a resized window keeps drawing the bitmap it has instead of
    /// requesting another one. Capped in pixels: the long side of a large iPad would
    /// otherwise ask for more than any panel artwork holds.
    private static var decodeWidth: CGFloat {
        let bounds = UIScreen.main.bounds
        let cap = (2048 / CachedImage.decodeScale(for: .high)).rounded(.down)
        return min(max(bounds.width, bounds.height), cap)
    }

    var body: some View {
        ZStack {
            if let container = model.imageContainer {
                Image(uiImage: container.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityIgnoresInvertColors()
                    .frame(width: width, height: height)
                    .clipped()
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
        .onAppear {
            model.transaction = Transaction(animation: .easeOut(duration: 0.25))
            // What is already shown is kept, and a request that is still running is not
            // started over.
            guard model.imageContainer == nil, !model.isLoading else { return }
            load()
        }
        .onChange(of: url) { _, _ in
            load()
        }
        .onChange(of: scenePhase) { _, phase in
            // A backdrop that failed while offline would otherwise never be tried again
            // on a screen the user stays on.
            if phase == .active, case .failure = model.result {
                load()
            }
        }
        .onChange(of: refusalEpoch) { _, epoch in
            // A refused request is not queued, so the hero would keep the blurred poster
            // for as long as the screen stays open although the host answers again a
            // few seconds later. Comparing with the count at load time keeps a second
            // refusal from asking in a loop.
            if let epoch, epoch != epochAtLoad {
                load()
            }
        }
    }

    private func load() {
        let epoch = ImageHostReopenings.shared.epoch
        if epochAtLoad != epoch { epochAtLoad = epoch }
        // A memory hit is shown at once, whatever animation happens to run around the
        // hero; only an image that arrives later fades, through the model's transaction.
        var immediate = Transaction(animation: nil)
        immediate.disablesAnimations = true
        withTransaction(immediate) {
            model.load(CachedImage.request(
                url: url,
                width: width,
                height: height,
                contentMode: .fill,
                loadProfile: .high,
                decodeWidth: Self.decodeWidth
            ))
        }
    }
}

private struct DetailHeroMetaRow: View {
    let year: String?
    let runtime: String?
    let rating10: Double?
    let ratingText: String?

    var body: some View {
        // The text the posters show for the same title.
        let ratingValueText = rating10.map(ContentRating.displayText) ?? ""
        HStack(spacing: 10) {
            if !ratingValueText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.yellow)
                    Text(ratingValueText)
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

    /// Dims and disables the primary button alone. Restart and the trailer link stay
    /// live: they do not depend on whatever the primary action is still waiting for.
    var primaryDisabled: Bool = false

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
                }
                // Full width with the content at the leading edge. No trailing chevron
                // on purpose: the button plays, it does not navigate.
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .buttonStyle(DetailPrimaryButtonStyle())
        .accessibilityIdentifier("detail.primaryAction")
        .disabled(primaryDisabled)
        // The label is white on a gradient, so disabling alone would not show.
        .opacity(primaryDisabled ? 0.5 : 1)
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
                        DetailSecondaryLabel(icon: "play.rectangle.on.rectangle", title: L("movie.trailer"))
                    }
                    .buttonStyle(.dimPress)
                }
            }
        }
    }
}

/// The primary button's gradient, shape and glow, as a style so that it can answer a
/// press: `.plain` only dims foreground styles, and every colour here is explicit, which
/// left the button without any feedback until the player appeared.
private struct DetailPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        configuration.label
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(shape)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 6)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
        .buttonStyle(.dimPress)
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
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    Text(expanded ? L("detail.show_less") : L("detail.show_more"))
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

    /// Counts taps that changed the season; the selection also moves on its own when
    /// playback crosses into another season, which must stay silent.
    @State private var selectionTapCount = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        FilterChip(
                            season.name ?? L("series.season_format", season.seasonNumber),
                            isSelected: selectedId == season.id
                        ) {
                            guard selectedId != season.id else { return }
                            selectionTapCount += 1
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedId = season.id
                            }
                        }
                        .accessibilityIdentifier("series.season.\(season.seasonNumber)")
                        .id(season.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .sensoryFeedback(.selection, trigger: selectionTapCount)
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

    /// The language picked in the app with the device's region, so digits follow the
    /// device as everywhere else in the app.
    private static var appLocale: Locale {
        AppLocale.current
    }

    /// Width of the units in a runtime: "45 min", "1 hr, 45 min", "45 dk.". The narrow
    /// width is shorter in English ("45m") but unreadable in Turkish ("45d").
    private nonisolated static let runtimeUnitWidth: Duration.UnitsFormatStyle.UnitWidth = .abbreviated

    /// A playback position: "12:34", or "1:02:03" from one hour on.
    static func formatMs(_ ms: Int) -> String {
        formatMs(ms, locale: appLocale)
    }

    nonisolated static func formatMs(_ ms: Int, locale: Locale) -> String {
        // Whole seconds go in: the format style rounds, and a resume point must not
        // read a second ahead of where playback starts.
        let totalSeconds = max(ms, 0) / 1000
        let duration = Duration.seconds(totalSeconds)
        return totalSeconds >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond).locale(locale))
            : duration.formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// Panels send the episode runtime as a bare number of minutes, or as text of their
    /// own ("45 min", "1h 20m"), which is passed through.
    static func seriesRuntime(_ raw: String?) -> String? {
        seriesRuntime(raw, locale: appLocale)
    }

    nonisolated static func seriesRuntime(_ raw: String?, locale: Locale) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty, r != "0" else { return nil }
        if r.contains("m") || r.contains("h") { return r }
        guard let minutes = Int(r) else { return r }
        guard minutes > 0 else { return nil }
        // Not a runtime any more, and far enough from overflowing the seconds below.
        guard minutes <= 24 * 60 else { return r }
        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: runtimeUnitWidth).locale(locale)
        )
    }

    /// A fraction as a whole percentage, written the way the app language writes it
    /// ("45%", "%45", "45 %"). Truncated, not rounded: a download at 99.6 % must not
    /// read 100 % while it is still running.
    static func percent(_ fraction: Double) -> String {
        percent(fraction, locale: appLocale)
    }

    nonisolated static func percent(_ fraction: Double, locale: Locale) -> String {
        let clamped = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        let whole = Int((clamped * 100).rounded(.down))
        return whole.formatted(.percent.locale(locale))
    }

    static func genreList(_ raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return [] }
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
