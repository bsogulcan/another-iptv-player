import SwiftUI
import GRDB
import UniformTypeIdentifiers

/// M3U playlist'e özel ayarlar ekranı. Xtream'in auth/abonelik/stat bölümleri yok.
struct M3UPlaylistSettingsView: View {
    let playlist: Playlist
    let onDismiss: () -> Void

    @State private var channelCount: Int = 0
    @State private var groupCount: Int = 0
    @State private var historyCount: Int = 0

    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showFileImporter = false

    @State private var filterAdultContent: Bool
    @State private var showClearHistoryAlert = false

    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continuePlayingInBackground = true
    @AppStorage("player.speedUpOnLongPress") private var speedUpOnLongPress = true
    @AppStorage("download.wifi_only") private var downloadWifiOnly = false
    @State private var downloadUsedBytes: Int64 = 0
    @State private var showingDeleteAllDownloadsAlert = false

    @ObservedObject private var locale = LocalizationManager.shared

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

                if !playlist.serverURL.isEmpty {
                    Button {
                        Task { await refreshFromURL() }
                    } label: {
                        HStack {
                            Text(L("settings.m3u.refresh_url"))
                            Spacer()
                            if isSyncing { ProgressView() }
                        }
                    }
                    .disabled(isSyncing)
                }

                Button {
                    showFileImporter = true
                } label: {
                    HStack {
                        Text(L("settings.m3u.refresh_file"))
                        Spacer()
                        Image(systemName: "doc.badge.arrow.up")
                    }
                }
                .disabled(isSyncing)

                if isSyncing, let msg = syncMessage {
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

            Section(header: Text(L("settings.playlist.info.title"))) {
                HStack {
                    Text(L("settings.playlist.name")); Spacer()
                    Text(playlist.name).foregroundColor(.secondary)
                }
                HStack {
                    Text(L("settings.playlist.type")); Spacer()
                    Text(L("settings.m3u.type_label")).foregroundColor(.secondary)
                }
                if !playlist.serverURL.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("settings.m3u.source_url"))
                        Text(playlist.serverURL)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                } else {
                    HStack {
                        Text(L("settings.m3u.source")); Spacer()
                        Text(L("playlists.local_file")).foregroundColor(.secondary)
                    }
                }
                if let epg = playlist.m3uEpgURL, !epg.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("settings.m3u.epg_url"))
                        Text(epg)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
            }

            Section(header: Text(L("settings.stats.title"))) {
                HStack {
                    Text(L("settings.stats.channel_count")); Spacer()
                    Text("\(channelCount)").foregroundColor(.secondary)
                }
                HStack {
                    Text(L("settings.stats.group_count")); Spacer()
                    Text("\(groupCount)").foregroundColor(.secondary)
                }
                HStack {
                    Text(L("settings.stats.history_count")); Spacer()
                    Text(L("settings.stats.history_items_format", historyCount)).foregroundColor(.secondary)
                }
            }

            Section(header: Text(L("settings.content_management.title"))) {
                Toggle(isOn: $filterAdultContent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.filter_adult.title"))
                        Text(L("settings.filter_adult.m3u_desc"))
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

            Section(header: Text(L("settings.about.title"))) {
                HStack {
                    Text(L("settings.about.version")); Spacer()
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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.allowedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert(L("common.error"), isPresented: $showError, actions: {
            Button(L("common.ok"), role: .cancel) { }
        }, message: {
            Text(errorMessage ?? L("common.unknown_error"))
        })
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
            await fetchStats()
            await refreshDownloadUsage()
        }
        .refreshable {
            await fetchStats()
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

    // MARK: - File Picker

    private static var allowedFileTypes: [UTType] {
        var types: [UTType] = [.plainText, .data]
        if let m3u = UTType(filenameExtension: "m3u") { types.insert(m3u, at: 0) }
        if let m3u8 = UTType(filenameExtension: "m3u8") { types.insert(m3u8, at: 0) }
        return types
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            errorMessage = err.localizedDescription
            showError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await refreshFromLocalFile(url: url) }
        }
    }

    // MARK: - Sync

    private func refreshFromURL() async {
        isSyncing = true
        syncMessage = L("settings.m3u.downloading")
        defer {
            isSyncing = false
            syncMessage = nil
        }
        do {
            let content = try await M3UService().fetchRemote(urlString: playlist.serverURL)
            syncMessage = L("settings.m3u.parsing")
            let parsed = try await M3UParser.parseAsync(content)
            syncMessage = L("settings.m3u.saving")
            try await M3UImporter.replace(
                playlist: playlist,
                channels: parsed.channels,
                epgURL: parsed.epgURL
            )
            await fetchStats()
            await M3UContentStore.shared.reloadIfActive(playlist: playlist)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func refreshFromLocalFile(url: URL) async {
        isSyncing = true
        syncMessage = L("settings.m3u.reading_file")
        defer {
            isSyncing = false
            syncMessage = nil
        }
        do {
            let content = try M3UService().readLocal(url: url)
            syncMessage = L("settings.m3u.parsing")
            let parsed = try await M3UParser.parseAsync(content)
            syncMessage = L("settings.m3u.saving")
            try await M3UImporter.replace(
                playlist: playlist,
                channels: parsed.channels,
                epgURL: parsed.epgURL,
                clearServerURL: true
            )
            await fetchStats()
            await M3UContentStore.shared.reloadIfActive(playlist: playlist)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func fetchStats() async {
        do {
            let pid = playlist.id
            let stats = try await AppDatabase.shared.read { db -> (Int, Int, Int) in
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM m3uChannel WHERE playlistId = ?", arguments: [pid]) ?? 0
                let groups = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT groupTitle) FROM m3uChannel WHERE playlistId = ?", arguments: [pid]) ?? 0
                let history = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM watchHistory WHERE playlistId = ?", arguments: [pid]) ?? 0
                return (count, groups, history)
            }
            await MainActor.run {
                self.channelCount = stats.0
                self.groupCount = stats.1
                self.historyCount = stats.2
            }
        } catch {
            print("M3U stats fetch error: \(error)")
        }
    }

    // MARK: - Adult Filter / History

    private func saveFilterSetting(newValue: Bool) async {
        var updated = playlist
        updated.filterAdultContent = newValue
        do {
            try await AppDatabase.shared.write { db in
                try updated.save(db)
            }
            await M3UContentStore.shared.reloadIfActive(playlist: updated)
        } catch {
            errorMessage = L("misc.save_setting_error", error.localizedDescription)
            showError = true
        }
    }

    private func clearHistory() async {
        do {
            let pid = playlist.id
            try await AppDatabase.shared.write { db in
                try db.execute(sql: "DELETE FROM watchHistory WHERE playlistId = ?", arguments: [pid])
            }
            await fetchStats()
        } catch {
            errorMessage = L("misc.history_delete_error", error.localizedDescription)
            showError = true
        }
    }
}
