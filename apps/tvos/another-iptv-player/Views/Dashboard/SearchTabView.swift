import SwiftUI

struct SearchTabView: View {
    let playlist: Playlist
    @EnvironmentObject private var contentStore: PlaylistContentStore
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var debounceTask: Task<Void, Never>?

    @State private var liveResults: [LiveStreamWithCategory] = []
    @State private var vodResults: [VODWithCategory] = []
    @State private var seriesResults: [SeriesWithCategory] = []
    @State private var isSearching: Bool = false

    @State private var playingChannel: PlayableChannel?
    @State private var selectedMovie: DBVODStream?
    @State private var selectedSeries: DBSeries?

    private var hasQuery: Bool { !debouncedQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasResults: Bool { !liveResults.isEmpty || !vodResults.isEmpty || !seriesResults.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if !hasQuery {
                    placeholder
                } else if isSearching && !hasResults {
                    searchingIndicator
                } else if !hasResults {
                    noResults
                } else {
                    if !liveResults.isEmpty {
                        section(title: L("dashboard.live"),
                                items: liveResults,
                                idKey: \.id) { item in
                            ChannelCard(
                                title: item.stream.name,
                                subtitle: item.categoryName,
                                imageURL: item.stream.streamIcon.flatMap(URL.init(string:))
                            ) {
                                playLive(item.stream)
                            }
                        }
                    }
                    if !vodResults.isEmpty {
                        section(title: L("dashboard.movies"),
                                items: vodResults,
                                idKey: \.id) { item in
                            PosterCard(
                                title: item.stream.name,
                                subtitle: item.categoryName,
                                imageURL: item.stream.streamIcon.flatMap(URL.init(string:))
                            ) {
                                selectedMovie = item.stream
                            }
                        }
                    }
                    if !seriesResults.isEmpty {
                        section(title: L("dashboard.series"),
                                items: seriesResults,
                                idKey: \.id) { item in
                            PosterCard(
                                title: item.series.name,
                                subtitle: item.categoryName,
                                imageURL: item.series.cover.flatMap(URL.init(string:))
                            ) {
                                selectedSeries = item.series
                            }
                        }
                    }
                }
            }
            .padding(40)
        }
        .searchable(text: $searchText, prompt: L("dashboard.search"))
        .navigationTitle(L("dashboard.search"))
        .onChange(of: searchText) { _, new in
            scheduleDebounce(new)
        }
        .task(id: debouncedQuery) {
            await runSearch()
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
        }
        .fullScreenCover(item: $playingChannel) { channel in
            PlayerView(url: channel.url, title: channel.title)
        }
        .fullScreenCover(item: $selectedMovie) { movie in
            NavigationStack {
                MovieDetailView(playlist: playlist, movie: movie)
            }
        }
        .fullScreenCover(item: $selectedSeries) { series in
            NavigationStack {
                SeriesDetailView(playlist: playlist, series: series)
            }
        }
    }

    // MARK: - Search pipeline

    private func scheduleDebounce(_ text: String) {
        debounceTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            debouncedQuery = ""
            liveResults = []
            vodResults = []
            seriesResults = []
            isSearching = false
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { debouncedQuery = text }
        }
    }

    private func runSearch() async {
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            liveResults = []
            vodResults = []
            seriesResults = []
            isSearching = false
            return
        }

        isSearching = true

        let live = contentStore.liveStreams
        let vod = contentStore.vodStreams
        let series = contentStore.seriesItems
        let resultLimit = 24

        let result = await Task.detached(priority: .userInitiated) { () -> (
            [LiveStreamWithCategory],
            [VODWithCategory],
            [SeriesWithCategory]
        ) in
            let l = live
                .filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            let v = vod
                .filter { CatalogTextSearch.matches(search: q, text: $0.stream.name) }
            let s = series
                .filter { CatalogTextSearch.matches(search: q, text: $0.series.name) }

            let lSorted = CatalogTextSearch.sortLiveByRelevance(Array(l.prefix(300)), search: q)
            let vSorted = CatalogTextSearch.sortVODByRelevance(Array(v.prefix(300)), search: q)
            let sSorted = CatalogTextSearch.sortSeriesByRelevance(Array(s.prefix(300)), search: q)

            return (
                Array(lSorted.prefix(resultLimit)),
                Array(vSorted.prefix(resultLimit)),
                Array(sSorted.prefix(resultLimit))
            )
        }.value

        guard !Task.isCancelled, q == debouncedQuery.trimmingCharacters(in: .whitespaces) else { return }
        liveResults = result.0
        vodResults = result.1
        seriesResults = result.2
        isSearching = false
    }

    private func playLive(_ stream: DBLiveStream) {
        guard let url = XtreamURLBuilder.liveStream(playlist: playlist, stream: stream) else { return }
        playingChannel = PlayableChannel(url: url, title: stream.name)
    }

    // MARK: - Sections & states

    @ViewBuilder
    private func section<Item: Identifiable, Card: View>(
        title: String,
        items: [Item],
        idKey: KeyPath<Item, Item.ID>,
        @ViewBuilder card: @escaping (Item) -> Card
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title2.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(items) { item in
                        card(item)
                            .frame(width: 260)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .focusSection()
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(L("search.placeholder"))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
    }

    private var searchingIndicator: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
    }

    private var noResults: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(L("search.no_results"))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
    }
}
