import SwiftUI
import GRDB

struct PlaylistSettingsView: View {
    let playlist: Playlist
    let onDismiss: () -> Void

    @State private var authResponse: XtreamAuthResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var isPasswordRevealed = false

    @State private var isSyncing = false
    @State private var progressMessage: String?

    @State private var liveCount: Int = 0
    @State private var vodCount: Int = 0
    @State private var seriesCount: Int = 0
    @State private var historyCount: Int = 0

    @State private var filterAdultContent: Bool
    @State private var showClearHistoryAlert = false

    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continuePlayingInBackground = true
    @AppStorage("player.speedUpOnLongPress") private var speedUpOnLongPress = true
    @AppStorage("download.wifi_only") private var downloadWifiOnly = false

    @State private var downloadUsedBytes: Int64 = 0
    @State private var showingDeleteAllDownloadsAlert = false
    
    init(playlist: Playlist, onDismiss: @escaping () -> Void) {
        self.playlist = playlist
        self.onDismiss = onDismiss
        _filterAdultContent = State(initialValue: playlist.filterAdultContent)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    onDismiss()
                } label: {
                    HStack {
                        Text(L("settings.back_to_list"))
                        Spacer()
                        Image(systemName: "list.bullet.rectangle")
                    }
                }

                Button(action: {
                    Task { await syncContents() }
                }) {
                    HStack {
                        Text(L("settings.refresh_all"))
                        Spacer()
                        if isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncing)

                if isSyncing, let msg = progressMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text(L("download.title"))) {
                NavigationLink {
                    DownloadsView(playlist: playlist)
                } label: {
                    HStack {
                        Text(L("download.title"))
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                    }
                }

                Toggle(isOn: $downloadWifiOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("download.wifi_only.title"))
                        Text(L("download.wifi_only.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(L("download.storage_used"))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: downloadUsedBytes, countStyle: .file))
                        .foregroundColor(.secondary)
                }

                if downloadUsedBytes > 0 {
                    Button(role: .destructive) {
                        showingDeleteAllDownloadsAlert = true
                    } label: {
                        HStack {
                            Text(L("download.delete_all"))
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                }
            }

            LanguagePickerSection()

            // — Player Settings —
            Section(header: Text(L("settings.player.title"))) {
                Toggle(isOn: $pipEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.player.pip.title"))
                        Text(L("settings.player.pip.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $continuePlayingInBackground) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.player.background.title"))
                        Text(L("settings.player.background.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $speedUpOnLongPress) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.player.longpress.title"))
                        Text(L("settings.player.longpress.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // — Playlist & Abonelik Bilgileri (birleşik) —
            Section(header: HStack {
                Text(L("settings.playlist.info.title"))
                Spacer()
                if authResponse?.userInfo != nil {
                    Button(action: {
                        Task { await fetchAuthInfo() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .textCase(.none)
                }
            }) {
                HStack {
                    Text(L("settings.playlist.name"))
                    Spacer()
                    Text(playlist.name)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(L("settings.playlist.server_url"))
                    Spacer()
                    Text(playlist.serverURL)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(L("settings.playlist.username"))
                    Spacer()
                    Text(playlist.username)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(L("settings.playlist.password"))
                    Spacer()
                    if isPasswordRevealed {
                        Text(playlist.password)
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(repeating: "•", count: playlist.password.count))
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        isPasswordRevealed.toggle()
                    }) {
                        Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView(L("settings.playlist.fetching_info"))
                        Spacer()
                    }
                } else if let error = errorMessage {
                    Text(L("settings.playlist.info_error", error))
                        .foregroundColor(.red)
                    Button(L("common.try_again")) {
                        Task { await fetchAuthInfo() }
                    }
                } else if let userInfo = authResponse?.userInfo {
                    HStack {
                        Text(L("settings.playlist.subscription"))
                        Spacer()
                        Text(calculateRemainingDays(expDate: userInfo.expDate))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(L("settings.playlist.active_connection"))
                        Spacer()
                        Text(userInfo.activeCons ?? L("settings.playlist.unknown"))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(L("settings.playlist.max_connection"))
                        Spacer()
                        Text(userInfo.maxConnections ?? L("settings.playlist.unlimited"))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // — İçerik İstatistikleri + Sunucu Bilgileri —
            if authResponse?.userInfo != nil {
                Section(header: Text(L("settings.stats.title"))) {
                    HStack {
                        Text(L("settings.stats.live_count"))
                        Spacer()
                        Text("\(liveCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(L("settings.stats.movie_count"))
                        Spacer()
                        Text("\(vodCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(L("settings.stats.series_count"))
                        Spacer()
                        Text("\(seriesCount)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(L("settings.stats.history_count"))
                        Spacer()
                        Text(L("settings.stats.history_items_format", historyCount))
                            .foregroundColor(.secondary)
                    }
                }

                if authResponse?.serverInfo?.timezone != nil
                    || (authResponse?.userInfo?.message.map { !$0.isEmpty } ?? false) {
                    Section(header: Text(L("settings.server.title"))) {
                        if let timeZone = authResponse?.serverInfo?.timezone {
                            HStack {
                                Text(L("settings.server.timezone"))
                                Spacer()
                                Text(timeZone)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let message = authResponse?.userInfo?.message, !message.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L("settings.server.message"))
                                Text(message)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // — İçerik Yönetimi —
                Section(header: Text(L("settings.content_management.title"))) {
                    Toggle(isOn: $filterAdultContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.filter_adult.title"))
                            Text(L("settings.filter_adult.xtream_desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: filterAdultContent) { _, newValue in
                        Task { await saveFilterSetting(newValue: newValue) }
                    }

                    Button(role: .destructive) {
                        showClearHistoryAlert = true
                    } label: {
                        HStack {
                            Text(L("history.clear.button_entry"))
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                    .disabled(historyCount == 0)
                }
            }

            Section(header: Text(L("settings.about.title"))) {
                HStack {
                    Text(L("settings.about.version"))
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                        .foregroundColor(.secondary)
                }

                Link(destination: URL(string: "https://github.com/bsogulcan/another-iptv-player")!) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.about.github.title"))
                            Text(L("settings.about.github.desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .alert(L("history.clear.title"), isPresented: $showClearHistoryAlert) {
            Button(L("common.cancel"), role: .cancel) { }
            Button(L("common.confirm_delete_yes"), role: .destructive) {
                Task { await clearHistory() }
            }
        } message: {
            Text(L("history.clear.message.all"))
        }
        .alert(L("download.delete_all"), isPresented: $showingDeleteAllDownloadsAlert) {
            Button(L("common.cancel"), role: .cancel) { }
            Button(L("common.confirm_delete_yes"), role: .destructive) {
                Task {
                    await DownloadManager.shared.deleteAll(playlistId: playlist.id)
                    await refreshDownloadUsage()
                }
            }
        } message: {
            Text(L("download.delete_all.message"))
        }
        .task {
            await fetchAuthInfo()
            await fetchLocalStats()
            await refreshDownloadUsage()
        }
        .refreshable {
            await fetchAuthInfo()
            await fetchLocalStats()
            await refreshDownloadUsage()
        }
    }
    
    private func refreshDownloadUsage() async {
        let pid = playlist.id
        let bytes = await Task.detached(priority: .utility) {
            DownloadStorage.usedBytes(playlistId: pid)
        }.value
        await MainActor.run { downloadUsedBytes = bytes }
    }

    private func fetchLocalStats() async {
        do {
            let pid = playlist.id
            let counts = try await AppDatabase.shared.read { db in
                let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM liveStream WHERE playlistId = ?", arguments: [pid]) ?? 0
                let vod = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM vodStream WHERE playlistId = ?", arguments: [pid]) ?? 0
                let series = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM series WHERE playlistId = ?", arguments: [pid]) ?? 0
                let history = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM watchHistory WHERE playlistId = ?", arguments: [pid]) ?? 0
                return (live, vod, series, history)
            }
            
            await MainActor.run {
                self.liveCount = counts.0
                self.vodCount = counts.1
                self.seriesCount = counts.2
                self.historyCount = counts.3
            }
        } catch {
            print("Stats fetch error: \(error)")
        }
    }
    
    private func clearHistory() async {
        do {
            let pid = playlist.id
            try await AppDatabase.shared.write { db in
                try db.execute(sql: "DELETE FROM watchHistory WHERE playlistId = ?", arguments: [pid])
            }
            await fetchLocalStats()
            // Continue watching row in Dashboard will update via GRDB watcher if implemented,
            // or on next disappear/appear.
        } catch {
            print("History clear error: \(error)")
        }
    }
    
    private func fetchAuthInfo() async {
        isLoading = true
        errorMessage = nil
        let client = XtreamAPIClient(playlist: playlist)
        do {
            let response = try await client.verify()
            await MainActor.run {
                self.authResponse = response
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func calculateRemainingDays(expDate: String?) -> String {
        guard let expDateStr = expDate, let timestamp = TimeInterval(expDateStr) else {
            return L("settings.playlist.unlimited_or_unknown")
        }

        if timestamp == 0 {
            return L("settings.playlist.unlimited")
        }

        let displayDate = Date(timeIntervalSince1970: timestamp)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: displayDate)

        if let days = components.day {
            if days < 0 {
                return L("settings.playlist.expired")
            }
            return L("common.days_format", days)
        }
        return L("settings.playlist.unknown")
    }
    
    private func saveFilterSetting(newValue: Bool) async {
        var updated = playlist
        updated.filterAdultContent = newValue
        do {
            try await AppDatabase.shared.write { db in
                try updated.save(db)
            }
            // Filtre değişince içerikleri otomatik yeniden indir
            await syncContents()
        } catch {
            await MainActor.run {
                self.errorMessage = L("misc.save_setting_error", error.localizedDescription)
            }
        }
    }

    private func syncContents() async {
        isSyncing = true
        errorMessage = nil
        print("--- REFRESH SETTINGS: SYNC STARTED (SQLITE) ---")
        let totalStartTime = Date()

        do {
            try await PlaylistContentStore.shared.syncFromNetworkReplacingLocal(playlist: playlist) { msg in
                progressMessage = msg
            }
            print("--- REFRESH TOTAL TIME: \(Date().timeIntervalSince(totalStartTime)) seconds ---")
            await fetchLocalStats()
            await PlaylistContentStore.shared.reloadFromDatabaseIfActive(playlistId: playlist.id)
            await MainActor.run {
                self.isSyncing = false
                self.progressMessage = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = L("misc.refresh_error", error.localizedDescription)
                self.isSyncing = false
                self.progressMessage = nil
            }
        }
    }
}

