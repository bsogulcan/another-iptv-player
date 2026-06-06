import SwiftUI
import GRDBQuery
import GRDB
import UniformTypeIdentifiers
import AppKit

// MARK: - Root

struct ContentView: View {
    @Query<PlaylistRequest> private var playlists: [Playlist]?
    @Environment(\.appDatabase) private var appDatabase
    @EnvironmentObject private var menuSignal: MenuSignal

    init() {
        _playlists = Query(PlaylistRequest(), in: \.appDatabase)
    }

    @State private var selection: SidebarSelection = .empty
    @State private var activePlaylistId: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Fullscreen'e girerken mevcut sidebar görünürlüğü hatırlanır, çıkışta geri yüklenir.
    @State private var preFullscreenColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var hasAttemptedAutoLoad = false
    /// Sidebar disclosure çift-tık toggle'ı için NSEvent monitor referansı (cleanup için).
    @State private var doubleClickMonitor: Any?

    /// Browser/Finder tarzı geri-ileri navigasyon yığınları.
    @State private var backStack: [SidebarSelection] = []
    @State private var forwardStack: [SidebarSelection] = []
    /// goBack/goForward selection'ı değiştirirken history'ye yeniden push edilmesin diye flag.
    @State private var skipNextHistoryPush = false
    /// Aşırı uzun history'lerin bellek tüketmesini engellemek için soft cap.
    private static let historyLimit = 50
    /// Her playlist'in altındaki hangi section disclosure'larının açık olduğunu tutar.
    /// Detail panel'den kategori seçilince ilgili section auto-expand edilir.
    @State private var expandedSections: [UUID: Set<PlaylistSection>] = [:]
    /// Hangi kategori disclosure'larının açık olduğunu tutar (item listesi göstermek için).
    @State private var expandedCategories: Set<CategoryExpansionKey> = []
    /// Hangi series item'ının disclosure'ı açık (sezonlar göstermek için).
    @State private var expandedSeriesItems: Set<SeriesItemExpansionKey> = []
    /// Hangi sezonun disclosure'ı açık (bölümler göstermek için).
    @State private var expandedSeasonItems: Set<SeasonExpansionKey> = []

    @State private var showingTypePicker = false
    @State private var showingAddXtreamPlaylist = false
    @State private var showingAddM3UPlaylist = false
    @State private var playlistToEdit: Playlist?
    @State private var deleteCandidate: Playlist?
    @State private var droppedFileURL: URL?

    @State private var searchText: String = ""
    @State private var windowSize = (NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900))

    @ObservedObject private var contentStore = PlaylistContentStore.shared
    @ObservedObject private var m3uStore = M3UContentStore.shared
    @ObservedObject private var playerOverlay = PlayerOverlayController.shared

    private let lastPlaylistKey = "lastPlaylistId"

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            // Player overlay artık dış ZStack'te değil; detail panel içinde render ediliyor ki
            // sidebar görünür kalsın ve kullanıcı oynatılan içerik dururken başka bir kanal/film
            // seçebilsin. Tam ekran için macOS'un native sidebar toggle'ı yeterli (toolbar'daki
            // chevron) veya Cmd+Ctrl+F full-screen modu.
            // Player overlay aktifken sadece player render edilir, detailContent değil.
            // ZStack'te ikisini birden tutmak NavigationStack'in iç katmanlama davranışı
            // sebebiyle player'ı arkada gösteriyordu (Watch Now → MovieDetailView'in üstüne
            // overlay olarak gelmesi gerekirken altında kalıyordu). Single-branch render
            // bu görsel z-order karışıklığını eliminate eder. Player dismiss edildiğinde
            // detail panel selection'a göre yeniden mount edilir.
            Group {
                if let item = playerOverlay.presentation {
                    item.root
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.playerOverlayDismiss) {
                            playerOverlay.dismiss(animated: false)
                        }
                        // .id(item.id) → her present() çağrısında SwiftUI taze view instance
                        // yaratır; aksi halde AnyView wrapper state'i koruyup yeni stream
                        // bilgisini ignore eder (kanal değiştirme player'a yansımaz).
                        .id(item.id)
                        // Top safe area'yı ignore et → player şeffaflaşan titlebar'ın altına da
                        // uzanır, gri header şeridi kaybolur. Yatay safe area dokunmadan
                        // (.leading/.trailing) bırakıyoruz ki sidebar'a taşmasın.
                        .ignoresSafeArea(edges: .top)
                } else {
                    detailContent
                }
            }
            .environment(\.posterMetrics, PosterMetrics(windowSize: windowSize))
            .environment(\.sidebarCategorySelector, SidebarCategorySelector(
                select: { section, categoryId in
                    selectCategoryFromDetail(section: section, categoryId: categoryId)
                },
                navigate: { newSelection in
                    selection = newSelection
                }
            ))
            .environmentObject(playerOverlay)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BreadcrumbBar(crumbs: breadcrumbCrumbs) { crumb in
                if let target = crumb.target { selection = target }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(activePlaylistTitle)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!canGoBack)
                .help("Go back (⌘[)")

                Button {
                    goForward()
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!canGoForward)
                .help("Go forward (⌘])")
            }
        }
        // Player aktifken header'ı tamamen gizle: toolbar item'ları kapat + titlebar'ı
        // şeffaflaştır + content'i tepeye yay. Traffic light'lar (NSWindow native chrome)
        // görünür kalır. Player kapanınca eski hâl restore edilir.
        .toolbar(playerOverlay.presentation != nil ? .hidden : .visible, for: .windowToolbar)
        .background(
            PlayerWindowChrome(immersive: playerOverlay.presentation != nil)
                .frame(width: 0, height: 0)
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { windowSize = geo.size }
                    .onChange(of: geo.size) { _, size in windowSize = size }
            }
        )
        .sheet(isPresented: $showingTypePicker) {
            PlaylistTypeSelectionView(
                onSelectXtream: {
                    showingTypePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showingAddXtreamPlaylist = true
                    }
                },
                onSelectM3U: {
                    showingTypePicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showingAddM3UPlaylist = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingAddXtreamPlaylist) {
            AddPlaylistView()
                .frame(minWidth: 540, minHeight: 480)
        }
        .sheet(isPresented: $showingAddM3UPlaylist) {
            AddM3UPlaylistView()
                .frame(minWidth: 540, minHeight: 460)
        }
        .sheet(item: $playlistToEdit) { playlist in
            Group {
                if playlist.kind == .m3u {
                    AddM3UPlaylistView(editingPlaylist: playlist)
                } else {
                    AddPlaylistView(editingPlaylist: playlist)
                }
            }
            .frame(minWidth: 540, minHeight: 480)
        }
        .sheet(isPresented: Binding(
            get: { droppedFileURL != nil },
            set: { if !$0 { droppedFileURL = nil } }
        )) {
            if let url = droppedFileURL {
                AddM3UPlaylistView(prefilledFileURL: url)
                    .frame(minWidth: 540, minHeight: 460)
            }
        }
        // Downloads artık sidebar App section'da bir sayfa olarak yaşıyor — sheet kaldırıldı.
        .alert(L("playlists.delete.title"), isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        )) {
            Button(L("common.delete"), role: .destructive) {
                if let p = deleteCandidate { performDelete(p) }
            }
            Button(L("common.cancel"), role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            Text(L("playlists.delete.message"))
        }
        .alert(L("loading.error.title"), isPresented: Binding(
            get: {
                if let id = activePlaylistId, contentStore.activePlaylistId == id {
                    return contentStore.loadError != nil && !contentStore.isLoading
                }
                return false
            },
            set: { if !$0 { contentStore.loadError = nil } }
        )) {
            Button(L("common.ok")) { contentStore.loadError = nil }
            Button(L("common.try_again")) {
                contentStore.loadError = nil
                if let playlist = activePlaylist {
                    Task { await contentStore.loadPlaylist(playlist) }
                }
            }
        } message: {
            Text(contentStore.loadError ?? "")
        }
        .alert(L("download.player_warning.title"), isPresented: Binding(
            get: { playerOverlay.pendingPresentation != nil },
            set: { if !$0 { playerOverlay.cancelPending() } }
        )) {
            Button(L("common.cancel"), role: .cancel) { playerOverlay.cancelPending() }
            Button(L("download.player_warning.go_to_downloads")) {
                playerOverlay.cancelPending()
                selection = .appDownloads
            }
            Button(L("download.player_warning.continue")) { playerOverlay.confirmPending() }
        } message: {
            Text(L("download.player_warning.message"))
        }
        .onAppear {
            attemptAutoLoad()
            installDoubleClickMonitorIfNeeded()
        }
        .onDisappear {
            if let m = doubleClickMonitor {
                NSEvent.removeMonitor(m)
                doubleClickMonitor = nil
            }
        }
        .onChange(of: playlists) { _, _ in attemptAutoLoad() }
        .onChange(of: selection) { old, new in
            // History push — eski seçimi back stack'e koy, forward'ı temizle. goBack/goForward
            // bu push'u atlamak için skipNextHistoryPush'u true yapar.
            if !skipNextHistoryPush, old != new, old != .empty {
                backStack.append(old)
                if backStack.count > Self.historyLimit {
                    backStack.removeFirst(backStack.count - Self.historyLimit)
                }
                forwardStack.removeAll()
            }
            skipNextHistoryPush = false

            searchText = ""
            autoExpandAncestors(for: new)
            // Selection değişti; yeni seçim kendi player'ını sunmayacaksa eski player'ı kapat
            // (yoksa eski player overlay yeni detail view'in üstünde kalır, kanal/film değişimi
            // görsel olarak yansımaz). Live, M3U ve series .episode kendi player'ını present eder
            // → presentation replace olduğu için dismiss gereksiz.
            let willPresentNewPlayer: Bool = {
                if case .item(_, let section, _, _) = new {
                    return section == .live || section == .channels
                }
                if case .episode = new { return true }
                return false
            }()
            if !willPresentNewPlayer && playerOverlay.presentation != nil {
                playerOverlay.dismiss(animated: false)
            }
            if case .item(let pid, let section, let catId, let itemId) = new {
                handleItemSelection(pid: pid, section: section, catId: catId, itemId: itemId)
            }
            if case .episode(let pid, let seriesId, let seasonId, let episodeId) = new {
                Task { await handleEpisodeSelection(pid: pid, seriesId: seriesId, seasonId: seasonId, episodeId: episodeId) }
            }
        }
        .onChange(of: menuSignal.newPlaylistRequested) { _, _ in showingTypePicker = true }
        .onChange(of: menuSignal.openPlaylistFileRequested) { _, _ in presentOpenPanel() }
        .onChange(of: menuSignal.closePlaylistRequested) { _, _ in collapseActivePlaylist() }
        .onChange(of: menuSignal.refreshContentRequested) { _, _ in
            guard let playlist = activePlaylist else { return }
            Task {
                if playlist.kind == .m3u {
                    await m3uStore.reloadIfActive(playlist: playlist)
                } else {
                    try? await PlaylistContentStore.shared.syncFromNetworkReplacingLocal(playlist: playlist) { _ in }
                }
            }
        }
        .onChange(of: menuSignal.openDownloadsRequested) { _, _ in
            // Sheet yerine sidebar selection — Downloads artık üst seviye App section'ın bir öğesi.
            selection = .appDownloads
        }
        .onChange(of: menuSignal.navigateBackRequested) { _, _ in goBack() }
        .onChange(of: menuSignal.navigateForwardRequested) { _, _ in goForward() }
        .onChange(of: menuSignal.openSearchRequested) { _, _ in selection = .appSearch }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        // Window fullscreen olunca sidebar otomatik gizlenir — kullanıcı player'a tam ekranda
        // baksın. Çıkışta önceki görünürlük geri yüklenir. Toolbar'daki sidebar toggle hâlâ
        // çalıştığı için kullanıcı manuel olarak da değiştirebilir.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            preFullscreenColumnVisibility = columnVisibility
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = preFullscreenColumnVisibility
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: bindingSelection) {
            // Üst seviye App section — Finder'ın "Locations" / Mac Music'in "Library" gibi
            // sabit global menüsü. Playlist'ten bağımsız erişim.
            Section(L("sidebar.app_section")) {
                Label(L("sidebar.settings"), systemImage: "gear")
                    .help(L("sidebar.settings"))
                    .accessibilityLabel(L("sidebar.settings"))
                    .accessibilityIdentifier("sidebar.app.settings")
                    .tag(SidebarSelection.appSettings)
                Label(L("sidebar.downloads"), systemImage: "arrow.down.circle")
                    .help(L("sidebar.downloads"))
                    .accessibilityLabel(L("sidebar.downloads"))
                    .accessibilityIdentifier("sidebar.app.downloads")
                    .tag(SidebarSelection.appDownloads)
                Label(L("sidebar.history"), systemImage: "clock.arrow.circlepath")
                    .help(L("sidebar.history"))
                    .accessibilityLabel(L("sidebar.history"))
                    .accessibilityIdentifier("sidebar.app.history")
                    .tag(SidebarSelection.appHistory)
                Label(L("sidebar.search"), systemImage: "magnifyingglass")
                    .help("\(L("sidebar.search")) (⌘F)")
                    .accessibilityLabel(L("sidebar.search"))
                    .accessibilityIdentifier("sidebar.app.search")
                    .tag(SidebarSelection.appSearch)
            }
            if let list = playlists, !list.isEmpty {
                Section(L("playlists.title")) {
                    ForEach(list) { playlist in
                        PlaylistRow(
                            playlist: playlist,
                            isExpanded: expansionBinding(for: playlist),
                            isActive: activePlaylistId == playlist.id,
                            expandedSections: expandedSectionsBinding(for: playlist.id),
                            expandedCategories: $expandedCategories,
                            expandedSeriesItems: $expandedSeriesItems,
                            expandedSeasonItems: $expandedSeasonItems,
                            onEdit: { playlistToEdit = playlist },
                            onDelete: { deleteCandidate = playlist }
                        )
                    }
                }
            } else if playlists != nil {
                // Veritabanı yüklü ama playlist yok — sidebar'da "Add" CTA.
                Section {
                    Button {
                        showingTypePicker = true
                    } label: {
                        Label(L("playlists.empty.add_button"), systemImage: "plus.circle")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var bindingSelection: Binding<SidebarSelection?> {
        Binding(
            get: { selection == .empty ? nil : selection },
            set: { selection = $0 ?? .empty }
        )
    }

    private func expansionBinding(for playlist: Playlist) -> Binding<Bool> {
        Binding(
            get: { activePlaylistId == playlist.id },
            set: { newValue in
                if newValue {
                    activatePlaylist(playlist)
                } else if activePlaylistId == playlist.id {
                    deactivateCurrentPlaylist()
                }
            }
        )
    }

    private func expandedSectionsBinding(for playlistId: UUID) -> Binding<Set<PlaylistSection>> {
        Binding(
            get: { expandedSections[playlistId] ?? [] },
            set: { expandedSections[playlistId] = $0 }
        )
    }

    /// Detail panel'deki shelf'ten kategori başlığına tıklandığında çağrılır:
    /// sidebar selection'ı kategoriye çevirir ve içeren section disclosure'ını auto-expand eder.
    /// Özel `__recently_added__` id'si için `.recentlyAdded` selection'ına yönlendirir
    /// (Recently Added shelf header bunu kullanır → inner NavigationStack push olmaz,
    /// ek back butonu görünmez).
    private func selectCategoryFromDetail(section: PlaylistSection, categoryId: String) {
        guard let id = activePlaylistId else { return }
        if categoryId == Self.recentlyAddedToken {
            selection = .recentlyAdded(id, section)
            return
        }
        var current = expandedSections[id] ?? []
        current.insert(section)
        expandedSections[id] = current
        selection = .category(id, section, categoryId)
    }

    static let recentlyAddedToken = "__recently_added__"

    private var activePlaylist: Playlist? {
        guard let id = activePlaylistId else { return nil }
        return (playlists ?? []).first(where: { $0.id == id })
    }

    private var activePlaylistTitle: String {
        activePlaylist?.name ?? L("playlists.title")
    }

    private var isContentSection: Bool {
        if case .section(_, let s) = selection {
            return s == .live || s == .movies || s == .series || s == .channels
        }
        return false
    }

    private var searchPrompt: String {
        guard case .section(_, let s) = selection else { return L("search.placeholder") }
        switch s {
        case .live:     return L("live.search_placeholder")
        case .movies:   return L("vod.search_placeholder")
        case .series:   return L("series.search_placeholder")
        case .channels: return L("m3u.search_placeholder")
        case .favorites: return L("favorites.search_placeholder")
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .empty:
            emptyDetail
        case .appSettings:
            NavigationStack {
                AppSettingsView()
                    .navigationTitle(L("sidebar.settings"))
            }
        case .appDownloads:
            appDownloadsDetail
        case .appHistory:
            appHistoryDetail
        case .appSearch:
            appSearchDetail
        case .playlist:
            playlistRootDetail
        case .section(let id, let section):
            sectionDetail(playlistId: id, section: section)
        case .category(let id, let section, let categoryId):
            categoryDetail(playlistId: id, section: section, categoryId: categoryId)
        case .item(let id, let section, let categoryId, let itemId):
            itemDetail(playlistId: id, section: section, categoryId: categoryId, itemId: itemId)
        case .season(let id, let seriesId, _):
            seriesDetailForSeason(playlistId: id, seriesId: seriesId)
        case .episode(let id, let seriesId, _, _):
            // Bölüm oynarken arkada serinin detayı (info, season picker) görünsün.
            seriesDetailForSeason(playlistId: id, seriesId: seriesId)
        case .recentlyAdded(let id, let section):
            recentlyAddedDetail(playlistId: id, section: section)
        case .playlistSettings(let id):
            playlistSettingsDetail(playlistId: id)
        }
    }

    /// Settings sayfası — playlist tipine göre PlaylistSettingsView (Xtream) veya
    /// M3UPlaylistSettingsView (M3U) sunulur. `onDismiss` callback'i selection'ı playlist'in
    /// birincil içerik section'ına geri çevirir (Xtream: .live, M3U: .channels).
    @ViewBuilder
    private func playlistSettingsDetail(playlistId: UUID) -> some View {
        if let playlist = (playlists ?? []).first(where: { $0.id == playlistId }) {
            NavigationStack {
                Group {
                    if playlist.kind == .m3u {
                        M3UPlaylistSettingsView(playlist: playlist) {
                            selection = .section(playlist.id, .channels)
                        }
                    } else {
                        PlaylistSettingsView(playlist: playlist) {
                            selection = .section(playlist.id, .live)
                        }
                    }
                }
                .navigationTitle(L("sidebar.playlist_settings"))
            }
        } else {
            emptyDetail
        }
    }

    @ViewBuilder
    private func recentlyAddedDetail(playlistId: UUID, section: PlaylistSection) -> some View {
        if let playlist = (playlists ?? []).first(where: { $0.id == playlistId }) {
            NavigationStack {
                switch section {
                case .movies:
                    RecentlyAddedVODDetailView(playlist: playlist, items: recentlyAddedVODs(playlistId: playlistId))
                        .navigationTitle(L("recently_added.title"))
                case .series:
                    RecentlyAddedSeriesDetailView(playlist: playlist, items: recentlyAddedSeries(playlistId: playlistId))
                        .navigationTitle(L("recently_added.title"))
                default:
                    emptyDetail
                }
            }
        } else {
            emptyDetail
        }
    }

    private func recentlyAddedVODs(playlistId: UUID) -> [DBVODStream] {
        let hidden = HiddenCategoryStore.shared.hiddenIds(playlistId: playlistId, type: "vod")
        let visibleCatIds = Set(contentStore.vodCategories.filter { !hidden.contains($0.id) }.map(\.id))
        return contentStore.vodStreams
            .lazy
            .filter { visibleCatIds.contains($0.stream.categoryId ?? "") }
            .compactMap { vod -> (DBVODStream, Int)? in
                guard let ts = vod.stream.added.flatMap(Int.init) else { return nil }
                return (vod.stream, ts)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map(\.0)
    }

    private func recentlyAddedSeries(playlistId: UUID) -> [DBSeries] {
        let hidden = HiddenCategoryStore.shared.hiddenIds(playlistId: playlistId, type: "series")
        let visibleCatIds = Set(contentStore.seriesCategories.filter { !hidden.contains($0.id) }.map(\.id))
        return contentStore.seriesItems
            .lazy
            .filter { visibleCatIds.contains($0.series.categoryId ?? "") }
            .compactMap { item -> (DBSeries, Int)? in
                guard let ts = item.series.lastModified.flatMap(Int.init) else { return nil }
                return (item.series, ts)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map(\.0)
    }

    /// Aktif playlist üzerinde çok tipli arama. Aktif playlist yoksa empty-state göster.
    @ViewBuilder
    private var appSearchDetail: some View {
        if let playlist = activePlaylist {
            NavigationStack {
                SearchView(playlist: playlist, searchText: $searchText)
                    .navigationTitle(L("sidebar.search"))
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(L("sidebar.no_active_playlist"))
                    .font(.title3.weight(.semibold))
                Text(L("sidebar.empty.search_message"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Aktif playlist'in izleme geçmişi (cross-type — VOD + episode + live hepsi).
    /// Aktif playlist yoksa empty-state göster (Downloads ile aynı pattern).
    @ViewBuilder
    private var appHistoryDetail: some View {
        if let playlist = activePlaylist {
            NavigationStack {
                WatchHistoryListView(playlist: playlist, typeFilter: nil) { item in
                    // Tap → uygun selection'a yönlendir. VOD/episode kendi detail panel'lerine
                    // gider; live için kategori bilinmediği için en azından section'a yönlendir.
                    Task { await navigateToHistoryItem(playlist: playlist, item: item) }
                }
                .navigationTitle(L("sidebar.history"))
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(L("sidebar.no_active_playlist"))
                    .font(.title3.weight(.semibold))
                Text(L("sidebar.empty.history_message"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// History item'a tap → uygun playable selection. VOD ve series için MovieDetail/SeriesDetail
    /// yolu izlenir (iOS davranışı); live için section'a yönlendir.
    private func navigateToHistoryItem(playlist: Playlist, item: DBWatchHistory) async {
        switch item.type {
        case "vod":
            // VODStream'i contentStore'da bul, item selection'ı yap.
            if let target = contentStore.vodStreams.first(where: { String($0.stream.streamId) == item.streamId }) {
                let catId = target.stream.categoryId ?? ""
                selection = .item(playlist.id, .movies, catId, item.streamId)
            }
        case "series":
            // Series episode → SeriesPlayerShell yerine series detail'e yönlendir (kullanıcı
            // istediği bölümü orada seçer). iOS davranışı: doğrudan oynatma; macOS'ta tek tıkla
            // detail panel sade kalsın diye selection .item olarak set ediliyor.
            if let sid = item.seriesId, let seriesId = Int(sid),
               let target = contentStore.seriesItems.first(where: { $0.series.seriesId == seriesId }) {
                let catId = target.series.categoryId ?? ""
                selection = .item(playlist.id, .series, catId, String(seriesId))
            }
        case "live":
            selection = .section(playlist.id, .live)
        default:
            break
        }
    }

    @ViewBuilder
    private var appDownloadsDetail: some View {
        if let playlist = activePlaylist {
            NavigationStack {
                DownloadsView(playlist: playlist)
                    .navigationTitle(L("sidebar.downloads"))
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(L("sidebar.no_active_playlist"))
                    .font(.title3.weight(.semibold))
                Text(L("sidebar.empty.downloads_message"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func seriesDetailForSeason(playlistId: UUID, seriesId: Int) -> some View {
        if let playlist = (playlists ?? []).first(where: { $0.id == playlistId }),
           let item = contentStore.seriesItems.first(where: { $0.series.seriesId == seriesId }) {
            NavigationStack {
                SeriesDetailView(playlist: playlist, series: item.series)
                    .id(seriesId)
            }
        } else {
            emptyDetail
        }
    }

    @ViewBuilder
    private var emptyDetail: some View {
        let isEmpty = (playlists ?? []).isEmpty
        VStack(spacing: 14) {
            Image(systemName: "tv.badge.wifi")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tertiary)

            Text(isEmpty ? L("playlists.empty.title") : "Select a Playlist")
                .font(.title2.weight(.semibold))

            Text(isEmpty
                 ? L("playlists.empty.message")
                 : "Expand a playlist in the sidebar to start browsing.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            if isEmpty {
                Button {
                    showingTypePicker = true
                } label: {
                    Text(L("playlists.empty.add_button"))
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("n", modifiers: [.command])
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private var playlistRootDetail: some View {
        VStack(spacing: 14) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.tertiary)
            Text("Expand the playlist")
                .font(.title3.weight(.semibold))
            Text("Click the chevron next to the playlist to load it and browse its sections.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sectionDetail(playlistId: UUID, section: PlaylistSection) -> some View {
        if let playlist = (playlists ?? []).first(where: { $0.id == playlistId }) {
            switch section {
            case .live:
                NavigationStack {
                    LiveStreamsView(playlist: playlist, externalSearch: $searchText)
                        .navigationTitle(L("dashboard.live"))
                }
            case .movies:
                NavigationStack {
                    VODView(playlist: playlist, externalSearch: $searchText)
                        .navigationTitle(L("dashboard.movies"))
                }
            case .series:
                NavigationStack {
                    SeriesView(playlist: playlist, externalSearch: $searchText)
                        .navigationTitle(L("dashboard.series"))
                }
            case .channels:
                NavigationStack {
                    M3UChannelsView(playlist: playlist, externalSearch: $searchText)
                        .navigationTitle(L("dashboard.channels"))
                }
            case .favorites:
                NavigationStack {
                    favoritesDetail(for: playlist)
                        .navigationTitle(L("favorites.title"))
                }
            }
        } else {
            emptyDetail
        }
    }

    @ViewBuilder
    private func favoritesDetail(for playlist: Playlist) -> some View {
        if playlist.kind == .m3u {
            M3UFavoritesView(playlist: playlist)
        } else {
            FavoritesView(playlist: playlist, initialType: "vod")
        }
    }

    @ViewBuilder
    private func categoryDetail(playlistId: UUID, section: PlaylistSection, categoryId: String) -> some View {
        if let playlist = (playlists ?? []).first(where: { $0.id == playlistId }) {
            NavigationStack {
                Group {
                    switch section {
                    case .live:
                        if let cat = contentStore.liveCategories.first(where: { $0.id == categoryId }) {
                            LiveCategoryDetailView(playlist: playlist, category: cat)
                        } else {
                            categoryLoadingPlaceholder
                        }
                    case .movies:
                        if let cat = contentStore.vodCategories.first(where: { $0.id == categoryId }) {
                            VODCategoryDetailView(playlist: playlist, category: cat)
                        } else {
                            categoryLoadingPlaceholder
                        }
                    case .series:
                        if let cat = contentStore.seriesCategories.first(where: { $0.id == categoryId }) {
                            SeriesCategoryDetailView(playlist: playlist, category: cat)
                        } else {
                            categoryLoadingPlaceholder
                        }
                    case .channels:
                        // M3U: categoryId burada group name'i taşıyor.
                        M3UGroupDetailView(playlist: playlist, group: categoryId)
                    case .favorites:
                        EmptyView()
                    }
                }
                // Aynı section içinde kategoriden kategoriye geçildiğinde SwiftUI view'ı yeniden
                // örneklemiyor; .task(id:) modifier'ları yeniden tetiklenmediği için içerik eski
                // kategoride takılı kalıyordu. `(section, categoryId)` üzerinden ID vererek taze
                // instance üretiyoruz.
                .id(CategoryIdentity(section: section, categoryId: categoryId))
            }
        } else {
            emptyDetail
        }
    }

    private struct CategoryIdentity: Hashable {
        let section: PlaylistSection
        let categoryId: String
    }

    @ViewBuilder
    private func itemDetail(playlistId: UUID, section: PlaylistSection, categoryId: String, itemId: String) -> some View {
        if let playlist = (playlists ?? []).first(where: { $0.id == playlistId }) {
            switch section {
            case .live, .channels:
                // Live ve M3U çalma için player overlay'e yönlenir; detail panel ana kategori
                // görünümünde kalır (içerik karışmasın diye).
                categoryDetail(playlistId: playlistId, section: section, categoryId: categoryId)
            case .movies:
                vodItemDetail(playlist: playlist, categoryId: categoryId, itemId: itemId)
            case .series:
                seriesItemDetail(playlist: playlist, categoryId: categoryId, itemId: itemId)
            case .favorites:
                EmptyView()
            }
        } else {
            emptyDetail
        }
    }

    @ViewBuilder
    private func vodItemDetail(playlist: Playlist, categoryId: String, itemId: String) -> some View {
        let items = contentStore.vodStreamsByCategoryId[categoryId] ?? []
        if let target = items.first(where: { String($0.stream.streamId) == itemId }) {
            NavigationStack {
                MovieDetailView(playlist: playlist, movie: target.stream, queue: items.map(\.stream))
                    .id(itemId)
            }
        } else {
            categoryDetail(playlistId: playlist.id, section: .movies, categoryId: categoryId)
        }
    }

    @ViewBuilder
    private func seriesItemDetail(playlist: Playlist, categoryId: String, itemId: String) -> some View {
        let items = contentStore.seriesItemsByCategoryId[categoryId] ?? []
        if let target = items.first(where: { String($0.series.seriesId) == itemId }) {
            NavigationStack {
                SeriesDetailView(playlist: playlist, series: target.series)
                    .id(itemId)
            }
        } else {
            categoryDetail(playlistId: playlist.id, section: .series, categoryId: categoryId)
        }
    }

    /// Live ve M3U item seçildiğinde player'ı tetikler. Player detail panel içinde render edilir
    /// (sidebar görünür kalır, kullanıcı başka kanala/filme geçebilir). Selection `.item` olarak
    /// kalır ki sidebar'da hangi içeriğin oynadığı vurgulansın.
    private func handleItemSelection(pid: UUID, section: PlaylistSection, catId: String, itemId: String) {
        guard let playlist = (playlists ?? []).first(where: { $0.id == pid }) else { return }
        switch section {
        case .live:
            let items = contentStore.liveStreamsByCategoryId[catId] ?? []
            guard let target = items.first(where: { String($0.stream.streamId) == itemId }) else { return }
            let streams = items.map(\.stream)
            let cat = contentStore.liveCategories.first(where: { $0.id == catId })
            let catName = cat?.name ?? ""
            playerOverlay.present(playlistId: playlist.id) {
                LivePlayerShell(
                    playlist: playlist,
                    queue: streams,
                    sections: [LiveChannelCategorySection(id: catId, title: catName, streams: streams)],
                    initialStream: target.stream,
                    initialHistory: nil,
                    subtitle: catName
                )
            }
        case .channels:
            let channels = m3uStore.channelsByGroup[catId] ?? []
            guard let target = channels.first(where: { $0.id == itemId }) else { return }
            playerOverlay.present {
                M3UPlayerShell(
                    playlist: playlist,
                    channel: target,
                    queue: channels
                )
            }
        case .movies, .series, .favorites:
            // Selection olarak kalır; detail panel item detayını gösterir.
            break
        }
    }

    /// Daha derin bir selection değiştiğinde üst seviyedeki disclosure'ları otomatik aç.
    private func autoExpandAncestors(for sel: SidebarSelection) {
        switch sel {
        case .category(let pid, let section, _):
            var current = expandedSections[pid] ?? []
            current.insert(section)
            expandedSections[pid] = current
        case .item(let pid, let section, let catId, _):
            var sectionSet = expandedSections[pid] ?? []
            sectionSet.insert(section)
            expandedSections[pid] = sectionSet
            expandedCategories.insert(CategoryExpansionKey(playlistId: pid, section: section, categoryId: catId))
        case .season(let pid, let seriesId, _):
            expandSeriesAncestors(pid: pid, seriesId: seriesId)
        case .episode(let pid, let seriesId, let seasonId, _):
            expandSeriesAncestors(pid: pid, seriesId: seriesId)
            expandedSeasonItems.insert(SeasonExpansionKey(playlistId: pid, seriesId: seriesId, seasonId: seasonId))
        case .recentlyAdded(let pid, let section):
            var sectionSet = expandedSections[pid] ?? []
            sectionSet.insert(section)
            expandedSections[pid] = sectionSet
        default:
            break
        }
    }

    private func expandSeriesAncestors(pid: UUID, seriesId: Int) {
        let categoryId = contentStore.seriesItems.first(where: { $0.series.seriesId == seriesId })?.series.categoryId ?? ""
        var sectionSet = expandedSections[pid] ?? []
        sectionSet.insert(.series)
        expandedSections[pid] = sectionSet
        expandedCategories.insert(CategoryExpansionKey(playlistId: pid, section: .series, categoryId: categoryId))
        expandedSeriesItems.insert(SeriesItemExpansionKey(playlistId: pid, seriesId: seriesId))
    }

    private func handleEpisodeSelection(pid: UUID, seriesId: Int, seasonId: String, episodeId: String) async {
        guard let playlist = (playlists ?? []).first(where: { $0.id == pid }) else { return }
        let ep: DBEpisode?
        do {
            ep = try await AppDatabase.shared.read { db in
                try DBEpisode.filter(Column("id") == episodeId).fetchOne(db)
            }
        } catch {
            return
        }
        guard let episode = ep else { return }
        // Async DB read sırasında kullanıcı başka yere geçtiyse (örn. kategori), stale Task
        // eski bölümü present etmesin. Selection hâlâ aynı episode'a işaret ediyor mu kontrol et.
        guard case .episode(let curPid, _, _, let curEpisodeId) = selection,
              curPid == pid, curEpisodeId == episodeId else { return }
        let series = contentStore.seriesItems.first(where: { $0.series.seriesId == seriesId })?.series
        let remoteURL = PlaybackURLBuilder(playlist: playlist).seriesURL(
            streamId: episode.episodeId ?? episode.id,
            containerExtension: episode.containerExtension
        )
        guard let url = remoteURL else { return }
        let cover = episode.cover.flatMap { URL(string: $0) } ?? series?.cover.flatMap { URL(string: $0) }
        playerOverlay.present(playlistId: playlist.id) {
            PlayerView(
                url: url,
                title: episode.title ?? L("detail.episode_fallback"),
                subtitle: series?.name,
                artworkURL: cover,
                isLiveStream: false,
                playlistId: playlist.id,
                streamId: episode.episodeId ?? episode.id,
                type: "series",
                seriesId: String(seriesId),
                resumeTimeMs: nil,
                containerExtension: episode.containerExtension,
                onNavigateToDetail: { _, _ in }
            )
        }
    }

    @ViewBuilder
    private var categoryLoadingPlaceholder: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(L("live.empty.preparing"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Activation

    private func activatePlaylist(_ playlist: Playlist) {
        let alreadyActive = (activePlaylistId == playlist.id)
        // withAnimation kullanmıyoruz — SwiftUI List(.sidebar) DisclosureGroup expansion'ı için
        // kendi varsayılanını (anlık/fade) kullansın. withAnimation ile birlikte row insertion
        // transition'ı `.move(edge: .top)` gibi davranıp child rows'u sidebar'ın tepesinden
        // kayarak getiriyordu.
        activePlaylistId = playlist.id
        selection = .section(playlist.id, playlist.kind == .m3u ? .channels : .live)
        UserDefaults.standard.set(playlist.id.uuidString, forKey: lastPlaylistKey)
        if !alreadyActive {
            Task {
                if playlist.kind == .m3u {
                    await m3uStore.loadPlaylist(playlist)
                } else {
                    await contentStore.loadPlaylist(playlist)
                }
                await MainActor.run {
                    RatingManager.shared.registerSuccessfulSession()
                }
            }
        }
    }

    private func deactivateCurrentPlaylist() {
        UserDefaults.standard.removeObject(forKey: lastPlaylistKey)
        activePlaylistId = nil
        selection = .empty
    }

    private func collapseActivePlaylist() {
        guard activePlaylistId != nil else { return }
        deactivateCurrentPlaylist()
    }

    // MARK: - Auto-load

    // MARK: - Breadcrumb path

    private var breadcrumbCrumbs: [BreadcrumbCrumb] {
        switch selection {
        case .empty:
            return []
        case .appSettings:
            return [BreadcrumbCrumb(title: L("sidebar.settings"), target: .appSettings)]
        case .appDownloads:
            return [BreadcrumbCrumb(title: L("sidebar.downloads"), target: .appDownloads)]
        case .appHistory:
            return [BreadcrumbCrumb(title: L("sidebar.history"), target: .appHistory)]
        case .appSearch:
            return [BreadcrumbCrumb(title: L("sidebar.search"), target: .appSearch)]
        case .playlist(let pid):
            return playlistCrumb(pid).map { [$0] } ?? []
        case .section(let pid, let section):
            var crumbs: [BreadcrumbCrumb] = []
            if let c = playlistCrumb(pid) { crumbs.append(c) }
            if let p = (playlists ?? []).first(where: { $0.id == pid }), !(p.kind == .m3u && section == .channels) {
                crumbs.append(BreadcrumbCrumb(title: sectionTitle(section), target: .section(pid, section)))
            }
            return crumbs
        case .category(let pid, let section, let catId):
            var crumbs: [BreadcrumbCrumb] = []
            if let c = playlistCrumb(pid) { crumbs.append(c) }
            if let p = (playlists ?? []).first(where: { $0.id == pid }), !(p.kind == .m3u && section == .channels) {
                crumbs.append(BreadcrumbCrumb(title: sectionTitle(section), target: .section(pid, section)))
            }
            let name = categoryName(playlistId: pid, section: section, categoryId: catId) ?? catId
            crumbs.append(BreadcrumbCrumb(title: name, target: .category(pid, section, catId)))
            return crumbs
        case .item(let pid, let section, let catId, let itemId):
            var crumbs: [BreadcrumbCrumb] = []
            if let c = playlistCrumb(pid) { crumbs.append(c) }
            if let p = (playlists ?? []).first(where: { $0.id == pid }), !(p.kind == .m3u && section == .channels) {
                crumbs.append(BreadcrumbCrumb(title: sectionTitle(section), target: .section(pid, section)))
            }
            let catName = categoryName(playlistId: pid, section: section, categoryId: catId) ?? catId
            crumbs.append(BreadcrumbCrumb(title: catName, target: .category(pid, section, catId)))
            let itemName = itemDisplayName(playlistId: pid, section: section, categoryId: catId, itemId: itemId) ?? itemId
            crumbs.append(BreadcrumbCrumb(title: itemName, target: .item(pid, section, catId, itemId)))
            return crumbs
        case .season(let pid, let seriesId, let seasonId):
            return seriesPath(pid: pid, seriesId: seriesId) + [
                BreadcrumbCrumb(title: seasonDisplayName(seasonId), target: .season(pid, seriesId, seasonId))
            ]
        case .episode(let pid, let seriesId, let seasonId, _):
            return seriesPath(pid: pid, seriesId: seriesId) + [
                BreadcrumbCrumb(title: seasonDisplayName(seasonId), target: .season(pid, seriesId, seasonId)),
                BreadcrumbCrumb(title: "Bölüm", target: nil)
            ]
        case .recentlyAdded(let pid, let section):
            var crumbs: [BreadcrumbCrumb] = []
            if let c = playlistCrumb(pid) { crumbs.append(c) }
            crumbs.append(BreadcrumbCrumb(title: sectionTitle(section), target: .section(pid, section)))
            crumbs.append(BreadcrumbCrumb(title: L("recently_added.title"), target: .recentlyAdded(pid, section)))
            return crumbs
        case .playlistSettings(let pid):
            var crumbs: [BreadcrumbCrumb] = []
            if let c = playlistCrumb(pid) { crumbs.append(c) }
            crumbs.append(BreadcrumbCrumb(title: L("sidebar.playlist_settings"), target: .playlistSettings(pid)))
            return crumbs
        }
    }

    private func playlistCrumb(_ pid: UUID) -> BreadcrumbCrumb? {
        guard let p = (playlists ?? []).first(where: { $0.id == pid }) else { return nil }
        return BreadcrumbCrumb(title: p.name, target: .playlist(pid))
    }

    private func sectionTitle(_ section: PlaylistSection) -> String {
        switch section {
        case .live:      return L("dashboard.live")
        case .movies:    return L("dashboard.movies")
        case .series:    return L("dashboard.series")
        case .channels:  return L("dashboard.channels")
        case .favorites: return L("favorites.title")
        }
    }

    private func categoryName(playlistId: UUID, section: PlaylistSection, categoryId: String) -> String? {
        switch section {
        case .live:     return contentStore.liveCategories.first(where: { $0.id == categoryId })?.name
        case .movies:   return contentStore.vodCategories.first(where: { $0.id == categoryId })?.name
        case .series:   return contentStore.seriesCategories.first(where: { $0.id == categoryId })?.name
        case .channels: return categoryId // M3U: categoryId IS the group name
        case .favorites: return nil
        }
    }

    private func itemDisplayName(playlistId: UUID, section: PlaylistSection, categoryId: String, itemId: String) -> String? {
        switch section {
        case .live:
            return contentStore.liveStreamsByCategoryId[categoryId]?
                .first(where: { String($0.stream.streamId) == itemId })?.stream.name
        case .movies:
            return contentStore.vodStreamsByCategoryId[categoryId]?
                .first(where: { String($0.stream.streamId) == itemId })?.stream.name
        case .series:
            return contentStore.seriesItemsByCategoryId[categoryId]?
                .first(where: { String($0.series.seriesId) == itemId })?.series.name
        case .channels:
            return m3uStore.channelsByGroup[categoryId]?.first(where: { $0.id == itemId })?.name
        case .favorites:
            return nil
        }
    }

    private func seriesPath(pid: UUID, seriesId: Int) -> [BreadcrumbCrumb] {
        var crumbs: [BreadcrumbCrumb] = []
        if let c = playlistCrumb(pid) { crumbs.append(c) }
        crumbs.append(BreadcrumbCrumb(title: sectionTitle(.series), target: .section(pid, .series)))
        if let item = contentStore.seriesItems.first(where: { $0.series.seriesId == seriesId }) {
            let catId = item.series.categoryId ?? ""
            if let catName = categoryName(playlistId: pid, section: .series, categoryId: catId) {
                crumbs.append(BreadcrumbCrumb(title: catName, target: .category(pid, .series, catId)))
            }
            crumbs.append(BreadcrumbCrumb(title: item.series.name, target: .item(pid, .series, catId, String(seriesId))))
        }
        return crumbs
    }

    /// `seasonId` format: "{seriesId}_{seasonNumber}" → "Sezon N" çıkarımı.
    private func seasonDisplayName(_ seasonId: String) -> String {
        if let last = seasonId.split(separator: "_").last, let num = Int(last) {
            return "Sezon \(num)"
        }
        return seasonId
    }

    // MARK: - History navigation

    private var canGoBack: Bool { !backStack.isEmpty }
    private var canGoForward: Bool { !forwardStack.isEmpty }

    private func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(selection)
        skipNextHistoryPush = true
        selection = prev
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(selection)
        skipNextHistoryPush = true
        selection = next
    }

    /// Sidebar disclosure'ları için AppKit-level çift tıklama monitörü kurar. SwiftUI
    /// `TapGesture(count: 2)` tek tıklamayı bekletip native-olmayan gecikme yaratıyordu;
    /// NSEvent monitörü gesture pipeline'ı bypass eder → tek tık anında selection (List native),
    /// çift tık `SidebarDoubleClickManager.shared.pendingToggle`'ı çalıştırır (hover edilen
    /// disclosure'ın toggle'ı).
    private func installDoubleClickMonitorIfNeeded() {
        guard doubleClickMonitor == nil else { return }
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.clickCount == 2 {
                SidebarDoubleClickManager.shared.fireIfHovering()
            }
            return event
        }
    }

    private func attemptAutoLoad() {
        guard !hasAttemptedAutoLoad, let list = playlists else { return }
        hasAttemptedAutoLoad = true
        if let lastIdString = UserDefaults.standard.string(forKey: lastPlaylistKey),
           let lastId = UUID(uuidString: lastIdString),
           let playlist = list.first(where: { $0.id == lastId }) {
            activatePlaylist(playlist)
        }
    }

    // MARK: - File open / drag-drop

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.plainText, .data]
        if let m3u = UTType(filenameExtension: "m3u")  { types.insert(m3u, at: 0) }
        if let m3u8 = UTType(filenameExtension: "m3u8") { types.insert(m3u8, at: 0) }
        panel.allowedContentTypes = types
        panel.prompt = "Import"
        panel.title = "Open Playlist File"
        if panel.runModal() == .OK, let url = panel.url {
            droppedFileURL = url
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "m3u" || ext == "m3u8" else { return }
            DispatchQueue.main.async {
                self.droppedFileURL = url
            }
        }
        return true
    }

    // MARK: - Delete

    private func performDelete(_ playlist: Playlist) {
        Task {
            do {
                _ = try await appDatabase.write { db in
                    try Playlist.deleteAll(db, ids: [playlist.id])
                }
                HiddenCategoryStore.shared.removeAll(playlistId: playlist.id)
                DownloadManager.shared.cleanupPlaylist(playlistId: playlist.id)
                if activePlaylistId == playlist.id {
                    deactivateCurrentPlaylist()
                }
            } catch {
                print("Failed to delete playlist: \(error)")
            }
            deleteCandidate = nil
        }
    }
}


#Preview {
    ContentView()
        .environment(\.appDatabase, .empty())
        .environmentObject(MenuSignal.shared)
}
