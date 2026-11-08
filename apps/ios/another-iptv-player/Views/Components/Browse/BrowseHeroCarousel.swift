import SwiftUI

/// One title of the featured carousel at the top of the Movies and Series tabs.
struct BrowseHeroItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let posterURL: URL?
    let backdropURL: URL?
    /// "2024 · Action · ★ 8.1"; nil when the catalog row has none of it.
    let meta: String?
}

/// The featured titles at the top of a tab: wide cards that page sideways and move on
/// by themselves. A card opens the title's page; the last card opens the whole list the
/// titles come from. Panels rarely send a backdrop with the list, so a card without one
/// shows the poster over a blur of itself.
struct BrowseHeroCarousel<Destination: View, More: View>: View {
    let items: [BrowseHeroItem]
    /// Width of the list the carousel sits in; the cards keep a wide aspect from it.
    let containerWidth: CGFloat
    let eyebrow: String
    @ViewBuilder let destination: (BrowseHeroItem) -> Destination
    /// The full list behind the featured titles, opened by the "See All" card at the end.
    @ViewBuilder let more: () -> More

    /// Selection tag of the "See All" card; catalog ids are positive.
    private static var moreId: Int { Int.min }

    /// The page ids in order: every title, then the "See All" card.
    private var pageIds: [Int] { items.map(\.id) + [Self.moreId] }

    @State private var selection: Int?
    /// False while the carousel is scrolled out of view; the timer waits meanwhile.
    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.posterMetrics) private var posterMetrics

    private static var advanceInterval: Duration { .seconds(7) }

    private var cardWidth: CGFloat {
        max(0, containerWidth - BrowseMetrics.pageMargin * 2)
    }

    private var cardHeight: CGFloat {
        // 16:10 on a phone; capped on wide windows where that would fill the screen.
        min((cardWidth * 0.62).rounded(), 380)
    }

    var body: some View {
        if !items.isEmpty, cardWidth > 0 {
            VStack(spacing: 10) {
                TabView(selection: $selection) {
                    ForEach(items) { item in
                        NavigationLink {
                            destination(item)
                        } label: {
                            card(item)
                        }
                        .buttonStyle(.cardPress)
                        .padding(.horizontal, BrowseMetrics.pageMargin)
                        .tag(Optional(item.id))
                        .accessibilityIdentifier("hero.card.\(item.id)")
                    }

                    NavigationLink {
                        more()
                    } label: {
                        moreCard
                    }
                    .buttonStyle(.cardPress)
                    .padding(.horizontal, BrowseMetrics.pageMargin)
                    .tag(Optional(Self.moreId))
                    .accessibilityIdentifier("hero.card.more")
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: cardHeight)
                .onScrollVisibilityChange(threshold: 0.3) { isVisible = $0 }

                pageDots
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
            .onAppear {
                if selection == nil || !pageIds.contains(where: { $0 == selection }) {
                    selection = items.first?.id
                }
            }
            .onChange(of: items.map(\.id)) { _, ids in
                if let selection, selection == Self.moreId || ids.contains(selection) { return }
                self.selection = ids.first
            }
            // Restarts with every page change, the user's swipes included, so a card
            // always stays up for the whole interval.
            .task(id: AdvanceKey(ids: pageIds, selection: selection, isVisible: isVisible)) {
                await advanceAfterInterval()
            }
        }
    }

    private func card(_ item: BrowseHeroItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            artwork(item)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.78), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.75))
                Text(item.title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let meta = item.meta {
                    Text(meta)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, item.meta].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    /// The last card: the first few posters fanned out over a blur of the first one,
    /// and "See All" with the name of the list.
    private var moreCard: some View {
        let posters = items.prefix(3).compactMap(\.posterURL)
        let posterHeight = (cardHeight * 0.62).rounded()
        let posterWidth = (posterHeight * 2 / 3).rounded()
        return ZStack(alignment: .bottomLeading) {
            CachedImage(
                url: items.first?.posterURL,
                width: cardWidth,
                height: cardHeight,
                cornerRadius: 0,
                contentMode: .fill,
                iconName: "film",
                decodeWidth: posterMetrics.categoryGridPosterWidth,
                decodeHeight: posterMetrics.categoryGridPosterHeight
            )
            .blur(radius: 28)
            .opacity(0.7)
            .clipped()
            Color.black.opacity(0.35)

            HStack(spacing: -posterWidth * 0.55) {
                ForEach(Array(posters.enumerated()), id: \.offset) { index, url in
                    CachedImage(
                        url: url,
                        width: posterWidth,
                        height: posterHeight,
                        cornerRadius: 10,
                        contentMode: .fill,
                        iconName: "film",
                        decodeWidth: posterMetrics.categoryGridPosterWidth,
                        decodeHeight: posterMetrics.categoryGridPosterHeight
                    )
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                    .rotationEffect(.degrees((Double(index) - Double(posters.count - 1) / 2) * 6))
                    .zIndex(Double(posters.count - index))
                }
            }
            .padding(.trailing, 28)
            .frame(width: cardWidth, height: cardHeight, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 6) {
                    Text(L("category.see_all"))
                        .font(.title2.weight(.heavy))
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(eyebrow), \(L("category.see_all"))")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func artwork(_ item: BrowseHeroItem) -> some View {
        ZStack {
            // The poster as a wash: all there is without a backdrop, and what stays
            // underneath while one loads or when its link is dead.
            CachedImage(
                url: item.posterURL,
                width: cardWidth,
                height: cardHeight,
                cornerRadius: 0,
                contentMode: .fill,
                iconName: "film",
                decodeWidth: posterMetrics.categoryGridPosterWidth,
                decodeHeight: posterMetrics.categoryGridPosterHeight
            )
            .blur(radius: 24)
            .opacity(0.9)
            .clipped()

            if let backdropURL = item.backdropURL {
                HeroBackdropImage(url: backdropURL, width: cardWidth, height: cardHeight)
            } else if item.posterURL != nil {
                // No backdrop: the poster itself, whole, at the trailing side.
                HStack {
                    Spacer()
                    CachedImage(
                        url: item.posterURL,
                        width: (cardHeight * 0.78 * 2 / 3).rounded(),
                        height: (cardHeight * 0.78).rounded(),
                        cornerRadius: 10,
                        contentMode: .fill,
                        iconName: "film",
                        decodeWidth: posterMetrics.categoryGridPosterWidth,
                        decodeHeight: posterMetrics.categoryGridPosterHeight
                    )
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    .padding(.trailing, 18)
                }
                .frame(width: cardWidth, height: cardHeight)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(pageIds, id: \.self) { id in
                Capsule()
                    .fill(id == selection ? Color.primary : Color.primary.opacity(0.25))
                    .frame(width: id == selection ? 16 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: selection)
        .accessibilityHidden(true)
    }

    private struct AdvanceKey: Equatable {
        var ids: [Int]
        var selection: Int?
        var isVisible: Bool
    }

    /// Moves to the next page once the current one has been up for the interval; the
    /// last page goes back to the first.
    private func advanceAfterInterval() async {
        // Reduce Motion: the cards stay where the user leaves them.
        guard !items.isEmpty, !reduceMotion, isVisible else { return }
        try? await Task.sleep(for: Self.advanceInterval)
        guard !Task.isCancelled else { return }
        let ids = pageIds
        guard let current = selection, let index = ids.firstIndex(of: current) else {
            selection = ids.first
            return
        }
        withAnimation(.easeInOut(duration: 0.5)) {
            selection = ids[(index + 1) % ids.count]
        }
    }
}

extension BrowseHeroItem {
    /// "2024 · Action · ★ 8.1" from what a catalog row may hold.
    static func metaLine(year: String?, genre: String?, rating: String?) -> String? {
        var parts: [String] = []
        if let year, !year.isEmpty { parts.append(year) }
        if let first = DetailFormatting.genreList(genre).first { parts.append(first) }
        if let text = ContentRating.displayText(rating) { parts.append("★ \(text)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
