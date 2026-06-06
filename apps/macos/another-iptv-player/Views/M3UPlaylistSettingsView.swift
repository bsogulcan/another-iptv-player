import SwiftUI
import GRDB
import UniformTypeIdentifiers

/// macOS M3U PlaylistSettingsView — section sırası iOS ile birebir:
/// 1) Aksiyonlar (Refresh URL, Replace file)
/// 2) Downloads
/// 3) Language
/// 4) Player Settings
/// 5) Playlist Info
/// 6) Content Stats
/// 7) Content Management
/// 8) About
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

    @State private var downloadUsedBytes: Int64 = 0
    @State private var showingDeleteAllDownloadsAlert = false
    @State private var showDownloads = false

    @ObservedObject private var locale = LocalizationManager.shared

    init(playlist: Playlist, onDismiss: @escaping () -> Void) {
        self.playlist = playlist
        self.onDismiss = onDismiss
        _filterAdultContent = State(initialValue: playlist.filterAdultContent)
    }

    var body: some View {
        Form {
            // 1) Actions — iOS ile birebir
            Section {
                Button {
                    onDismiss()
                } label: {
                    HStack {
                        Label(L("settings.back_to_list"), systemImage: "list.bullet.rectangle")
                        Spacer()
                    }
                }
                .keyboardShortcut("[", modifiers: [.command])

                if !playlist.serverURL.isEmpty {
                    Button {
                        Task { await refreshFromURL() }
                    } label: {
                        HStack {
                            Label(L("settings.m3u.refresh_url"), systemImage: "arrow.clockwise")
                            Spacer()
                            if isSyncing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isSyncing)
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label(L("settings.m3u.refresh_file"), systemImage: "doc.badge.arrow.up")
                }
                .disabled(isSyncing)

                if isSyncing, let msg = syncMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            // 2) Downloads
            Section(L("download.title")) {
                LabeledContent(L("download.storage_used"),
                               value: ByteCountFormatter.string(fromByteCount: downloadUsedBytes, countStyle: .file))
                HStack {
                    Button {
                        showDownloads = true
                    } label: {
                        Label(L("download.title"), systemImage: "arrow.down.circle")
                    }
                    if downloadUsedBytes > 0 {
                        Button(role: .destructive) {
                            showingDeleteAllDownloadsAlert = true
                        } label: {
                            Label(L("download.delete_all"), systemImage: "trash")
                        }
                    }
                }
            }

            // 3) Language
            Section(L("settings.language.section")) {
                LanguagePickerInline()
            }

            // 4) Player Settings
            Section(L("settings.player.title")) {
                Toggle(L("settings.player.pip.title"), isOn: $pipEnabled)
                    .help(L("settings.player.pip.desc"))
                Toggle(L("settings.player.background.title"), isOn: $continuePlayingInBackground)
                    .help(L("settings.player.background.desc"))
            }

            // 5) Playlist Info
            Section(L("settings.playlist.info.title")) {
                LabeledContent(L("settings.playlist.name"), value: playlist.name)
                LabeledContent(L("settings.playlist.type"), value: L("settings.m3u.type_label"))
                if !playlist.serverURL.isEmpty {
                    LabeledContent(L("settings.m3u.source_url")) {
                        Text(playlist.serverURL)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                } else {
                    LabeledContent(L("settings.m3u.source"), value: L("playlists.local_file"))
                }
                if let epg = playlist.m3uEpgURL, !epg.isEmpty {
                    LabeledContent(L("settings.m3u.epg_url")) {
                        Text(epg)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }

            // 6) Content Stats
            Section(L("settings.stats.title")) {
                LabeledContent(L("settings.stats.channel_count"), value: channelCount.formatted())
                LabeledContent(L("settings.stats.group_count"), value: groupCount.formatted())
                LabeledContent(L("settings.stats.history_count"),
                               value: L("settings.stats.history_items_format", historyCount))
            }

            // 7) Content Management
            Section(L("settings.content_management.title")) {
                Toggle(L("settings.filter_adult.title"), isOn: $filterAdultContent)
                    .help(L("settings.filter_adult.m3u_desc"))
                    .onChange(of: filterAdultContent) { _, newValue in
                        Task { await saveFilterSetting(newValue: newValue) }
                    }

                Button(role: .destructive) {
                    showClearHistoryAlert = true
                } label: {
                    Label(L("history.clear.button_entry"), systemImage: "trash")
                }
                .disabled(historyCount == 0)
            }

            // 8) About
            Section(L("settings.about.title")) {
                LabeledContent(L("settings.about.version"),
                               value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"))
                Link(L("settings.about.github.title"),
                     destination: URL(string: "https://github.com/bsogulcan/another-iptv-player")!)
            }
        }
        .formStyle(.grouped)
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
        .sheet(isPresented: $showDownloads) {
            NavigationStack {
                DownloadsView(playlist: playlist)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("common.close")) { showDownloads = false }
                        }
                    }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
        .task {
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
