import SwiftUI
import GRDB

/// macOS PlaylistSettingsView — section sırası iOS ile birebir:
/// 1) Aksiyonlar (Re-download)
/// 2) Downloads
/// 3) Language
/// 4) Player Settings
/// 5) Playlist Info (+ Subscription)
/// 6) Content Stats
/// 7) Server Info
/// 8) Content Management
/// 9) About
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

    @State private var downloadUsedBytes: Int64 = 0
    @State private var showingDeleteAllDownloadsAlert = false
    @State private var showDownloads = false

    init(playlist: Playlist, onDismiss: @escaping () -> Void) {
        self.playlist = playlist
        self.onDismiss = onDismiss
        _filterAdultContent = State(initialValue: playlist.filterAdultContent)
    }

    var body: some View {
        Form {
            // 1) Actions — iOS ile birebir: Back, Refresh
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

                Button {
                    Task { await syncContents() }
                } label: {
                    HStack {
                        Label(L("settings.refresh_all"), systemImage: "arrow.clockwise")
                        Spacer()
                        if isSyncing { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isSyncing)
                if isSyncing, let msg = progressMessage {
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

            // 5) Playlist Info + Subscription
            Section(L("settings.playlist.info.title")) {
                LabeledContent(L("settings.playlist.name"), value: playlist.name)
                LabeledContent(L("settings.playlist.server_url")) {
                    Text(playlist.serverURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent(L("settings.playlist.username")) {
                    Text(playlist.username)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent(L("settings.playlist.password")) {
                    HStack(spacing: 6) {
                        Group {
                            if isPasswordRevealed {
                                Text(playlist.password).textSelection(.enabled).monospaced()
                            } else {
                                Text(String(repeating: "•", count: max(playlist.password.count, 1)))
                            }
                        }
                        .foregroundStyle(.secondary)
                        Button {
                            isPasswordRevealed.toggle()
                        } label: {
                            Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(isPasswordRevealed ? "Hide password" : "Reveal password")
                    }
                }

                if isLoading {
                    HStack { ProgressView().controlSize(.small); Text(L("settings.playlist.fetching_info")).foregroundStyle(.secondary) }
                } else if let error = errorMessage {
                    HStack {
                        Text(L("settings.playlist.info_error", error)).foregroundStyle(.red).lineLimit(2)
                        Spacer()
                        Button(L("common.try_again")) { Task { await fetchAuthInfo() } }
                    }
                } else if let userInfo = authResponse?.userInfo {
                    LabeledContent(L("settings.playlist.subscription"),
                                   value: calculateRemainingDays(expDate: userInfo.expDate))
                    LabeledContent(L("settings.playlist.active_connection"),
                                   value: userInfo.activeCons ?? L("settings.playlist.unknown"))
                    LabeledContent(L("settings.playlist.max_connection"),
                                   value: userInfo.maxConnections ?? L("settings.playlist.unlimited"))
                }
            }

            // 6) Content Stats (only when verified)
            if authResponse?.userInfo != nil {
                Section(L("settings.stats.title")) {
                    LabeledContent(L("settings.stats.live_count"), value: liveCount.formatted())
                    LabeledContent(L("settings.stats.movie_count"), value: vodCount.formatted())
                    LabeledContent(L("settings.stats.series_count"), value: seriesCount.formatted())
                    LabeledContent(L("settings.stats.history_count"),
                                   value: L("settings.stats.history_items_format", historyCount))
                }

                // 7) Server Info
                if authResponse?.serverInfo?.timezone != nil
                    || (authResponse?.userInfo?.message.map { !$0.isEmpty } ?? false) {
                    Section(L("settings.server.title")) {
                        if let tz = authResponse?.serverInfo?.timezone {
                            LabeledContent(L("settings.server.timezone"), value: tz)
                        }
                        if let message = authResponse?.userInfo?.message, !message.isEmpty {
                            LabeledContent(L("settings.server.message")) {
                                Text(message).foregroundStyle(.secondary).font(.footnote).lineLimit(3)
                            }
                        }
                    }
                }

                // 8) Content Management
                Section(L("settings.content_management.title")) {
                    Toggle(L("settings.filter_adult.title"), isOn: $filterAdultContent)
                        .help(L("settings.filter_adult.xtream_desc"))
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
            }

            // 9) About
            Section(L("settings.about.title")) {
                LabeledContent(L("settings.about.version"),
                               value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"))
                Link(L("settings.about.github.title"),
                     destination: URL(string: "https://github.com/bsogulcan/another-iptv-player")!)
            }
        }
        .formStyle(.grouped)
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
    }

    // MARK: - Helpers

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
        if timestamp == 0 { return L("settings.playlist.unlimited") }
        let displayDate = Date(timeIntervalSince1970: timestamp)
        let days = Calendar.current.dateComponents([.day], from: Date(), to: displayDate).day ?? 0
        if days < 0 { return L("settings.playlist.expired") }
        return L("common.days_format", days)
    }

    private func saveFilterSetting(newValue: Bool) async {
        var updated = playlist
        updated.filterAdultContent = newValue
        do {
            try await AppDatabase.shared.write { db in
                try updated.save(db)
            }
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
        do {
            try await PlaylistContentStore.shared.syncFromNetworkReplacingLocal(playlist: playlist) { msg in
                progressMessage = msg
            }
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

/// macOS native inline dil seçici — LanguagePickerSection NavigationLink+List yapısında
/// (iOS push pattern'i). Form içinde tek satır Picker yeterli ve native.
struct LanguagePickerInline: View {
    @ObservedObject private var manager = LocalizationManager.shared

    var body: some View {
        Picker(L("settings.language.title"), selection: $manager.selectedLanguage) {
            Text(L("settings.language.system")).tag("system")
            Divider()
            ForEach(LocalizationManager.supportedLanguages) { lang in
                if lang.code != "system" {
                    Text(lang.nativeName).tag(lang.code)
                }
            }
        }
        .pickerStyle(.menu)
    }
}
