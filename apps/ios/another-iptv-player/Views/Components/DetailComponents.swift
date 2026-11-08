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
    /// Shown as one line under the metadata, in the hero. Arrives with the metadata
    /// request on films; the hero grows upwards, so nothing below it moves.
    var genres: [String] = []
}

// MARK: - Cinematic Hero

struct DetailHero: View {
    let config: DetailHeroConfig
    var heroHeight: CGFloat = 380
    /// The page colour the hero fades into. The detail pages pass their ambient colour.
    var pageBackground: Color = Color(UIColor.systemBackground)
    var onPosterTap: ((URL) -> Void)? = nil

    @Environment(\.posterMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                backdropLayer
                if config.posterURL == nil && config.backdropURL == nil {
                    gradientLayer
                }
                if dynamicTypeSize.isAccessibilitySize {
                    posterButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                } else {
                    overlayLayer
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)

            if dynamicTypeSize.isAccessibilitySize {
                titleAndMetadata
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
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
                    // Inside the stretched layer, so pulling the page down stretches the
                    // scrim with the artwork instead of uncovering artwork above it.
                    gradientLayer
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
                pageBackground
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var gradientLayer: some View {
        LinearGradient(
            stops: [
                // A light scrim at the top keeps the status bar and the bar buttons
                // readable over bright artwork.
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.42),
                .init(color: pageBackground.opacity(0.82), location: 0.8),
                .init(color: pageBackground, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: heroHeight)
        .allowsHitTesting(false)
    }

    private var posterButton: some View {
        Button {
            if let url = config.posterURL { onPosterTap?(url) }
        } label: {
            Self.posterImage(url: config.posterURL, iconName: config.posterIconName, metrics: metrics)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(config.posterURL == nil || onPosterTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(config.title)
        .accessibilityRemoveTraits(.isImage)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("detail.poster")
        .accessibilityHidden(config.posterURL == nil || onPosterTap == nil)
    }

    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(config.title)
                .accessibilityAddTraits(.isHeader)
                .font(.title.weight(.heavy))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            DetailHeroMetaRow(year: config.year, runtime: config.runtime,
                              rating10: config.rating10, ratingText: config.ratingText)

            if !config.genres.isEmpty {
                Text(config.genres.joined(separator: " · "))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var overlayLayer: some View {
        HStack(alignment: .bottom, spacing: 16) {
            posterButton
            titleAndMetadata
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
struct HeroBackdropImage: View {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let year: String?
    let runtime: String?
    let rating10: Double?
    let ratingText: String?

    var body: some View {
        // The text the posters show for the same title.
        let ratingValueText = rating10.map { ContentRating.displayText($0) } ?? ""
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            if !ratingValueText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.yellow)
                    Text(ratingValueText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
            } else if let ratingText, !ratingText.isEmpty {
                RatingLabel(rating: ratingText, style: .standard)
            }

            if let year, !year.isEmpty {
                Text(year)
                    .fixedSize()
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let runtime, !runtime.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(runtime)
                        .fixedSize()
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            BrowseAccessibility.ratingLabel(ratingValueText.isEmpty ? ContentRating.displayText(ratingText) : ratingValueText),
            year, runtime
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
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

    /// More round actions after restart and trailer (the film's download button).
    var accessory: AnyView? = nil

    var body: some View {
        VStack(spacing: 14) {
            primaryCTA
            secondaryRow
        }
        .padding(.horizontal, 16)
    }

    private var primaryCTA: some View {
        Button(action: onPrimary) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: primaryIcon)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(primaryTitle)
                            .font(.headline)
                        if let sub = primarySubtitle, !sub.isEmpty {
                            Text(sub)
                                .font(.caption)
                                .opacity(0.7)
                                .lineLimit(1)
                        }
                    }
                }
                // Centred, the way the system's media apps draw their play button.
                // No trailing chevron on purpose: the button plays, it does not navigate.
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)

                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(Color(UIColor.systemBackground))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }
            }
        }
        .buttonStyle(DetailPrimaryButtonStyle())
        .accessibilityIdentifier("detail.primaryAction")
        .disabled(primaryDisabled)
        .opacity(primaryDisabled ? 0.5 : 1)
    }

    @ViewBuilder
    private var secondaryRow: some View {
        let hasRestart = onRestart != nil && restartTitle != nil
        let hasTrailer = trailerURL != nil
        if hasRestart || hasTrailer || accessory != nil {
            HStack(alignment: .top, spacing: 18) {
                if let onRestart, let restartTitle {
                    Button(action: onRestart) {
                        DetailRoundAction(icon: "arrow.counterclockwise", title: restartTitle)
                    }
                    .buttonStyle(.dimPress)
                    .accessibilityIdentifier("detail.restart")
                }
                if let trailerURL {
                    Link(destination: trailerURL) {
                        DetailRoundAction(icon: "play.rectangle.on.rectangle", title: L("movie.trailer"))
                    }
                    .buttonStyle(.dimPress)
                    .accessibilityIdentifier("detail.trailer")
                }
                if let accessory {
                    accessory
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// The primary button: filled with the text colour of the page and lettered with its
/// background, so it is white with black text on the dark detail pages. A style so that
/// it can answer a press.
private struct DetailPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .foregroundStyle(Color(UIColor.systemBackground))
            .background(Color.primary)
            .clipShape(shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A secondary action on the detail pages: a glyph in a circle with its name under it.
struct DetailRoundAction: View {
    static let circleSide: CGFloat = 48
    static let minWidth: CGFloat = 64

    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: Self.circleSide, height: Self.circleSide)
                .background(Circle().fill(Color.primary.opacity(0.12)))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: Self.minWidth)
        .contentShape(Rectangle())
    }
}

// MARK: - Cast

/// One cast member: the panel sends names only; a role and photo are optional.
struct DetailCastMember: Equatable, Hashable, Sendable {
    let name: String
    var character: String? = nil
    var photoURL: URL? = nil
}

/// The cast as round photos or initials avatars (panel names only), with the
/// name and the role under each. Every member of the list is kept; the row scrolls.
struct DetailCastRow: View {
    let label: String
    let members: [DetailCastMember]

    init(label: String, members: [DetailCastMember]) {
        self.label = label
        self.members = members
    }

    /// Panel cast: a comma-separated list of names.
    init(label: String, cast: String) {
        self.label = label
        self.members = cast.split(whereSeparator: { $0 == "," || $0 == "|" || $0 == "/" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { DetailCastMember(name: $0) }
    }

    private static let side: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                        VStack(spacing: 6) {
                            avatar(member)
                            VStack(spacing: 1) {
                                Text(member.name)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                if let character = member.character {
                                    Text(character)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(members.map { [$0.name, $0.character].compactMap { $0 }.joined(separator: ", ") }.joined(separator: "; "))")
    }

    @ViewBuilder
    private func avatar(_ member: DetailCastMember) -> some View {
        ZStack {
            Circle().fill(Self.color(for: member.name).gradient)
            Text(Self.initials(member.name))
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
            if let url = member.photoURL {
                CachedImage(
                    url: url,
                    width: Self.side,
                    height: Self.side,
                    cornerRadius: Self.side / 2,
                    contentMode: .fill,
                    iconName: "person.fill",
                    loadProfile: .grid
                )
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(Circle())
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        let letters = [parts.first, parts.count > 1 ? parts.last : nil]
            .compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// A muted colour that stays the same for a name on every page.
    static func color(for name: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in name.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.35, brightness: 0.55)
    }
}

// MARK: - Ambient colour

/// The detail pages' background: a dark tone taken from the poster, so every page has
/// the colour of its title. Computed once per poster and kept for the session.
enum DetailAmbient {
    static let fallback = Color(red: 0.07, green: 0.07, blue: 0.08)

    private static let cache = NSCache<NSURL, UIColor>()

    static func cached(for url: URL?) -> Color? {
        guard let url, let color = cache.object(forKey: url as NSURL) else { return nil }
        return Color(uiColor: color)
    }

    /// Reads the poster through the image pipeline, so the card's bitmap that is already
    /// in memory or on disk is used, and returns the darkened average colour.
    static func color(for url: URL?, request: ImageRequest?) async -> Color? {
        guard let url, let request else { return nil }
        if let hit = cache.object(forKey: url as NSURL) { return Color(uiColor: hit) }
        guard let image = try? await ImagePipeline.shared.image(for: request) else { return nil }
        guard let tone = await Task.detached(priority: .utility, operation: { averageTone(of: image) }).value else {
            return nil
        }
        cache.setObject(tone, forKey: url as NSURL)
        return Color(uiColor: tone)
    }

    private nonisolated static func averageTone(of image: UIImage) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        // Drawn into a 1×1 bitmap: the scaler averages the whole image.
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let average = UIColor(
            red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Dark enough for white text at every saturation, never a flat black.
        return UIColor(hue: hue, saturation: min(saturation, 0.6), brightness: 0.17, alpha: 1)
    }
}

extension View {
    /// The detail pages' look: dark whatever the system appearance, on the ambient colour.
    func detailPageStyle(background: Color) -> some View {
        self
            .environment(\.colorScheme, .dark)
            .background(background.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
            .animation(.easeInOut(duration: 0.35), value: background)
    }

    /// Gives the top bar a background once the hero has scrolled away, so the page no
    /// longer runs under the status bar and the bar's title. The soft edge effect stays
    /// off while the hero is in view, where it would wash the artwork out.
    @ViewBuilder
    func detailTopBarBackground(visible: Bool) -> some View {
        if #available(iOS 26, *) {
            self.scrollEdgeEffectHidden(!visible, for: .top)
        } else {
            self.toolbarBackground(visible ? .visible : .hidden, for: .navigationBar)
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
                .accessibilityAddTraits(.isHeader)
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
                .foregroundStyle(.secondary)
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

    /// Above this many seasons a row of chips no longer fits on a phone and scrolling it
    /// to find a season is slower than a menu.
    static let menuThreshold = 5

    private func title(_ season: DBSeason) -> String {
        season.name ?? L("series.season_format", season.seasonNumber)
    }

    var body: some View {
        if seasons.count > Self.menuThreshold {
            seasonMenu
        } else {
            chipRow
        }
    }

    private var seasonMenu: some View {
        Menu {
            ForEach(seasons) { season in
                Button {
                    guard selectedId != season.id else { return }
                    selectionTapCount += 1
                    selectedId = season.id
                } label: {
                    if selectedId == season.id {
                        Label(title(season), systemImage: "checkmark")
                    } else {
                        Text(title(season))
                    }
                }
                .accessibilityIdentifier("series.season.\(season.seasonNumber)")
            }
        } label: {
            HStack(spacing: 6) {
                Text(seasons.first(where: { $0.id == selectedId }).map(title) ?? L("series.seasons"))
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primary.opacity(0.12)))
        }
        .accessibilityIdentifier("series.season.menu")
        .sensoryFeedback(.selection, trigger: selectionTapCount)
        .padding(.horizontal, 16)
    }

    private var chipRow: some View {
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

extension String {
    /// nil for an empty string, so a blank field falls through to the next source.
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
