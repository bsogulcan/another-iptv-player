import SwiftUI
import GRDBQuery
import GRDB

// MARK: - Playlist row

/// Sidebar'da bir playlist'i temsil eden disclosure row.
///
/// Davranış:
/// - Chevron'a basmak `isExpanded` bağlayıcısını toggle eder ve dış tarafta
///   `activatePlaylist` / `deactivate` çağrılır.
/// - Satır gövdesine basmak List(selection:) üzerinden `SidebarSelection.playlist`'i seçer.
///   Aktif playlist'in altındaki child label'ları da kendi tag'leriyle seçilebilir.
struct PlaylistRow: View {
    let playlist: Playlist
    @Binding var isExpanded: Bool
    let isActive: Bool
    @Binding var expandedSections: Set<PlaylistSection>
    @Binding var expandedCategories: Set<CategoryExpansionKey>
    @Binding var expandedSeriesItems: Set<SeriesItemExpansionKey>
    @Binding var expandedSeasonItems: Set<SeasonExpansionKey>
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var m3uStore = M3UContentStore.shared

    private var isLoading: Bool {
        guard isActive else { return false }
        if playlist.kind == .m3u {
            return m3uStore.isLoading && m3uStore.activePlaylistId == playlist.id
        }
        return contentStore.isLoading && contentStore.activePlaylistId == playlist.id
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if isActive {
                childRows
            }
        } label: {
            // Finder/Music tarzı: tek tık selection (List native), çift tık expand toggle.
            // Çift tıklama SwiftUI TapGesture yerine NSEvent monitor üzerinden çözülür
            // (SidebarDoubleClick.swift). Hover ile tüm satır boyu hit area sağlanır.
            label
                .help(playlist.name)
                .accessibilityLabel(playlist.name)
                .accessibilityIdentifier("sidebar.playlist.\(playlist.id.uuidString)")
                .tag(SidebarSelection.playlist(playlist.id))
                .sidebarDoubleClickToggle(id: SidebarSelection.playlist(playlist.id)) {
                    isExpanded.toggle()
                }
        }
        .contextMenu {
            Button("Edit…") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: playlist.kind == .m3u ? "list.bullet.rectangle.portrait" : "server.rack")
                .foregroundStyle(.tint)
            Text(playlist.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
        }
    }

    @ViewBuilder
    private var childRows: some View {
        if playlist.kind == .m3u {
            // M3U'da Live/Movies/Series ara seviyesi yok — gruplar doğrudan playlist'in altında.
            // Xtream'de Channels yerine 3 ayrı section olduğu için orada disclosure ara seviyesi
            // korunuyor; burada doğrudan kategori (group) listesine düşer.
            ForEach(m3uStore.groupNames, id: \.self) { group in
                categoryDisclosure(section: .channels, categoryId: group, name: group, itemCount: m3uStore.channelsByGroup[group]?.count ?? 0) {
                    ForEach(m3uStore.channelsByGroup[group] ?? [], id: \.id) { channel in
                        Label(channel.name, systemImage: "play.circle")
                            .lineLimit(1)
                            .help(channel.name)
                            .accessibilityLabel(channel.name)
                            .accessibilityIdentifier("sidebar.item.\(playlist.id.uuidString).channels.\(group).\(channel.id)")
                            .tag(SidebarSelection.item(playlist.id, .channels, group, channel.id))
                    }
                }
            }
            Label(L("favorites.title"), systemImage: "star")
                .help(L("favorites.title"))
                .accessibilityLabel(L("favorites.title"))
                .accessibilityIdentifier("sidebar.section.\(playlist.id.uuidString).favorites")
                .tag(SidebarSelection.section(playlist.id, .favorites))
            Label(L("sidebar.playlist_settings"), systemImage: "slider.horizontal.3")
                .help(L("sidebar.playlist_settings"))
                .accessibilityLabel(L("sidebar.playlist_settings"))
                .accessibilityIdentifier("sidebar.playlist.settings.\(playlist.id.uuidString)")
                .tag(SidebarSelection.playlistSettings(playlist.id))
        } else {
            sectionDisclosure(
                .live,
                title: L("dashboard.live"),
                icon: "tv",
                count: contentStore.liveStreams.count
            ) {
                ForEach(contentStore.liveCategories, id: \.id) { cat in
                    categoryDisclosure(section: .live, categoryId: cat.id, name: cat.name, itemCount: contentStore.liveStreamsByCategoryId[cat.id]?.count ?? 0) {
                        ForEach(contentStore.liveStreamsByCategoryId[cat.id] ?? [], id: \.stream.streamId) { item in
                            Label(item.stream.name, systemImage: "play.circle")
                                .lineLimit(1)
                                .help(item.stream.name)
                                .accessibilityLabel(item.stream.name)
                                .accessibilityIdentifier("sidebar.item.\(playlist.id.uuidString).live.\(cat.id).\(item.stream.streamId)")
                                .tag(SidebarSelection.item(playlist.id, .live, cat.id, String(item.stream.streamId)))
                        }
                    }
                }
            }
            sectionDisclosure(
                .movies,
                title: L("dashboard.movies"),
                icon: "film",
                count: contentStore.vodStreams.count
            ) {
                ForEach(contentStore.vodCategories, id: \.id) { cat in
                    categoryDisclosure(section: .movies, categoryId: cat.id, name: cat.name, itemCount: contentStore.vodStreamsByCategoryId[cat.id]?.count ?? 0) {
                        ForEach(contentStore.vodStreamsByCategoryId[cat.id] ?? [], id: \.stream.streamId) { item in
                            Label(item.stream.name, systemImage: "film")
                                .lineLimit(1)
                                .help(item.stream.name)
                                .accessibilityLabel(item.stream.name)
                                .accessibilityIdentifier("sidebar.item.\(playlist.id.uuidString).movies.\(cat.id).\(item.stream.streamId)")
                                .tag(SidebarSelection.item(playlist.id, .movies, cat.id, String(item.stream.streamId)))
                        }
                    }
                }
            }
            sectionDisclosure(
                .series,
                title: L("dashboard.series"),
                icon: "play.tv",
                count: contentStore.seriesItems.count
            ) {
                ForEach(contentStore.seriesCategories, id: \.id) { cat in
                    categoryDisclosure(section: .series, categoryId: cat.id, name: cat.name, itemCount: contentStore.seriesItemsByCategoryId[cat.id]?.count ?? 0) {
                        ForEach(contentStore.seriesItemsByCategoryId[cat.id] ?? [], id: \.series.seriesId) { item in
                            SeriesItemSidebarRow(
                                playlist: playlist,
                                series: item.series,
                                categoryId: cat.id,
                                expandedSeriesItems: $expandedSeriesItems,
                                expandedSeasonItems: $expandedSeasonItems
                            )
                        }
                    }
                }
            }
            Label(L("favorites.title"), systemImage: "star")
                .help(L("favorites.title"))
                .accessibilityLabel(L("favorites.title"))
                .accessibilityIdentifier("sidebar.section.\(playlist.id.uuidString).favorites")
                .tag(SidebarSelection.section(playlist.id, .favorites))
            Label(L("sidebar.playlist_settings"), systemImage: "slider.horizontal.3")
                .help(L("sidebar.playlist_settings"))
                .accessibilityLabel(L("sidebar.playlist_settings"))
                .accessibilityIdentifier("sidebar.playlist.settings.\(playlist.id.uuidString)")
                .tag(SidebarSelection.playlistSettings(playlist.id))
        }
    }

    /// Bir kategori row'unu disclosure olarak çizer. Chevron item listesini expand/collapse eder.
    /// Label tıklaması `.category` selection'ı tetikler.
    @ViewBuilder
    private func categoryDisclosure<Items: View>(
        section: PlaylistSection,
        categoryId: String,
        name: String,
        itemCount: Int,
        @ViewBuilder items: @escaping () -> Items
    ) -> some View {
        let expansion = categoryExpansionBinding(section: section, categoryId: categoryId)
        DisclosureGroup(isExpanded: expansion) {
            items()
        } label: {
            Label(name, systemImage: "folder")
                .badge(itemCount)
                .help("\(name) — \(itemCount) items")
                .accessibilityLabel(name)
                .accessibilityIdentifier("sidebar.category.\(playlist.id.uuidString).\(sectionToken(section)).\(categoryId)")
                .tag(SidebarSelection.category(playlist.id, section, categoryId))
                .sidebarDoubleClickToggle(id: SidebarSelection.category(playlist.id, section, categoryId)) {
                    expansion.wrappedValue.toggle()
                }
        }
    }

    private func categoryExpansionBinding(section: PlaylistSection, categoryId: String) -> Binding<Bool> {
        let key = CategoryExpansionKey(playlistId: playlist.id, section: section, categoryId: categoryId)
        return Binding(
            get: { expandedCategories.contains(key) },
            set: { newValue in
                if newValue {
                    expandedCategories.insert(key)
                } else {
                    expandedCategories.remove(key)
                }
            }
        )
    }

    /// Bir section row'unu disclosure olarak çizer. Chevron expand/collapse, label tıklama
    /// `SidebarSelection.section` üzerinden detail panel'i besler.
    @ViewBuilder
    private func sectionDisclosure<Children: View>(
        _ section: PlaylistSection,
        title: String,
        icon: String,
        count: Int,
        @ViewBuilder children: @escaping () -> Children
    ) -> some View {
        let expansion = sectionExpansionBinding(section)
        DisclosureGroup(isExpanded: expansion) {
            children()
        } label: {
            Label(title, systemImage: icon)
                .badge(count)
                .help("\(title) — \(count) items")
                .accessibilityLabel(title)
                .accessibilityIdentifier("sidebar.section.\(playlist.id.uuidString).\(sectionToken(section))")
                .tag(SidebarSelection.section(playlist.id, section))
                .sidebarDoubleClickToggle(id: SidebarSelection.section(playlist.id, section)) {
                    expansion.wrappedValue.toggle()
                }
        }
    }

    /// PlaylistSection enum case'ini stable string token'a çevirir (accessibility identifier için).
    private func sectionToken(_ s: PlaylistSection) -> String {
        switch s {
        case .live:        return "live"
        case .movies:      return "movies"
        case .series:      return "series"
        case .channels:    return "channels"
        case .favorites:   return "favorites"
        }
    }

    private func sectionExpansionBinding(_ section: PlaylistSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { newValue in
                if newValue {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }
}


// MARK: - Series item sidebar row (seasons + episodes lazy)

/// Bir serinin sidebar row'u — chevron sezonları açar, sezon chevron'u bölümleri açar.
/// Sezonlar/bölümler DB'den `@Query` ile reaktif okunur; sezonlar henüz yüklenmediyse
/// (seasonsLoaded == false) expand anında `SeriesSeasonLoader` API çağrısıyla doldurulur.
private struct SeriesItemSidebarRow: View {
    let playlist: Playlist
    let series: DBSeries
    let categoryId: String
    @Binding var expandedSeriesItems: Set<SeriesItemExpansionKey>
    @Binding var expandedSeasonItems: Set<SeasonExpansionKey>

    private var expansionKey: SeriesItemExpansionKey {
        SeriesItemExpansionKey(playlistId: playlist.id, seriesId: series.seriesId)
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedSeriesItems.contains(expansionKey) },
            set: { newValue in
                if newValue {
                    expandedSeriesItems.insert(expansionKey)
                } else {
                    expandedSeriesItems.remove(expansionKey)
                }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: expansionBinding) {
            SeasonsSidebarList(
                playlist: playlist,
                series: series,
                expandedSeasonItems: $expandedSeasonItems
            )
        } label: {
            Label(series.name, systemImage: "tv")
                .lineLimit(1)
                .help(series.name)
                .accessibilityLabel(series.name)
                .accessibilityIdentifier("sidebar.item.\(playlist.id.uuidString).series.\(categoryId).\(series.seriesId)")
                .tag(SidebarSelection.item(playlist.id, .series, categoryId, String(series.seriesId)))
                .sidebarDoubleClickToggle(id: SidebarSelection.item(playlist.id, .series, categoryId, String(series.seriesId))) {
                    expansionBinding.wrappedValue.toggle()
                }
        }
        .task(id: expansionBinding.wrappedValue) {
            guard expansionBinding.wrappedValue, !series.seasonsLoaded else { return }
            await SeriesSeasonLoader.shared.loadIgnoringErrors(series, playlist: playlist)
        }
    }
}

private struct SeasonsSidebarList: View {
    let playlist: Playlist
    let series: DBSeries
    @Binding var expandedSeasonItems: Set<SeasonExpansionKey>
    @Query<SeasonsRequest> private var seasons: [DBSeason]

    init(playlist: Playlist, series: DBSeries, expandedSeasonItems: Binding<Set<SeasonExpansionKey>>) {
        self.playlist = playlist
        self.series = series
        self._expandedSeasonItems = expandedSeasonItems
        _seasons = Query(SeasonsRequest(seriesId: series.seriesId, playlistId: playlist.id), in: \.appDatabase)
    }

    var body: some View {
        if seasons.isEmpty {
            Label(series.seasonsLoaded ? L("series.no_seasons_info") : L("series.loading_seasons"), systemImage: "ellipsis")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            ForEach(seasons) { season in
                SeasonSidebarRow(
                    playlist: playlist,
                    series: series,
                    season: season,
                    expandedSeasonItems: $expandedSeasonItems
                )
            }
        }
    }
}

private struct SeasonSidebarRow: View {
    let playlist: Playlist
    let series: DBSeries
    let season: DBSeason
    @Binding var expandedSeasonItems: Set<SeasonExpansionKey>

    private var expansionKey: SeasonExpansionKey {
        SeasonExpansionKey(playlistId: playlist.id, seriesId: series.seriesId, seasonId: season.id)
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { expandedSeasonItems.contains(expansionKey) },
            set: { newValue in
                if newValue {
                    expandedSeasonItems.insert(expansionKey)
                } else {
                    expandedSeasonItems.remove(expansionKey)
                }
            }
        )
    }

    var body: some View {
        let title = season.name ?? "Sezon \(season.seasonNumber)"
        DisclosureGroup(isExpanded: expansionBinding) {
            EpisodesSidebarList(playlist: playlist, series: series, season: season)
        } label: {
            Label(title, systemImage: "rectangle.stack")
                .badge(season.episodeCount ?? 0)
                .lineLimit(1)
                .help("\(title) — \(season.episodeCount ?? 0) episodes")
                .accessibilityLabel(title)
                .accessibilityIdentifier("sidebar.season.\(playlist.id.uuidString).\(series.seriesId).\(season.id)")
                .tag(SidebarSelection.season(playlist.id, series.seriesId, season.id))
                .sidebarDoubleClickToggle(id: SidebarSelection.season(playlist.id, series.seriesId, season.id)) {
                    expansionBinding.wrappedValue.toggle()
                }
        }
    }
}

private struct EpisodesSidebarList: View {
    let playlist: Playlist
    let series: DBSeries
    let season: DBSeason
    @Query<EpisodesRequest> private var episodes: [DBEpisode]

    init(playlist: Playlist, series: DBSeries, season: DBSeason) {
        self.playlist = playlist
        self.series = series
        self.season = season
        _episodes = Query(EpisodesRequest(seasonId: season.id), in: \.appDatabase)
    }

    var body: some View {
        if episodes.isEmpty {
            Label("—", systemImage: "ellipsis")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            ForEach(episodes) { ep in
                let title = ep.title ?? "Bölüm \(ep.episodeNum ?? 0)"
                Label(title, systemImage: "play.circle")
                    .lineLimit(1)
                    .help(title)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("sidebar.episode.\(playlist.id.uuidString).\(series.seriesId).\(season.id).\(ep.id)")
                    .tag(SidebarSelection.episode(playlist.id, series.seriesId, season.id, ep.id))
            }
        }
    }
}
