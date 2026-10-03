import SwiftUI
import Combine
import GRDB
import UniformTypeIdentifiers

/// M3U playlist'e özel ayarlar ekranı. Xtream'in auth/abonelik/stat bölümleri yok.
struct M3UPlaylistSettingsView: View {
    let playlist: Playlist
    let onDismiss: () -> Void

    /// The playlist row as stored. `playlist` is the value the dashboard was opened
    /// with and never changes afterwards, so everything shown here, handed to the
    /// importer and the stores or passed to the guide section comes from this copy,
    /// which is replaced by the row every write returns and re-read whenever the
    /// form appears and after every re-import.
    @State private var current: Playlist

    /// Row counts; nil until the first read, so the rows do not show a zero that
    /// is replaced a moment later.
    @State private var localStats: (channels: Int, groups: Int, history: Int)?

    /// The re-import that is running, if any. The spinner and the phase text sit on
    /// the row that started it.
    @State private var runningAction: SyncAction?
    @State private var syncMessage: String?
    @State private var syncSuccessCount = 0
    @State private var syncFailureCount = 0
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showFileImporter = false

    /// The switch position while its save is on the way; nil follows the row.
    @State private var pendingAdultFilter: Bool?
    /// Counts the saves, so only the latest one hands the switch back to the row.
    @State private var adultFilterGeneration = 0
    @State private var showClearHistoryDialog = false

    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continuePlayingInBackground = true
    @AppStorage("player.speedUpOnLongPress") private var speedUpOnLongPress = true
    @AppStorage("player.autoPlayNextEpisode") private var autoPlayNextEpisode = true
    @AppStorage("download.wifi_only") private var downloadWifiOnly = false
    /// nil until the first measurement.
    @State private var downloadUsedBytes: Int64?
    @State private var showingDeleteAllDownloadsDialog = false

    @ObservedObject private var locale = LocalizationManager.shared

    private enum SyncAction {
        case url
        case file
    }

    init(playlist: Playlist, onDismiss: @escaping () -> Void) {
        self.playlist = playlist
        self.onDismiss = onDismiss
        _current = State(initialValue: playlist)
    }

    var body: some View {
        Form {
            Section {
                Button(L("settings.back_to_list")) {
                    onDismiss()
                }

                if !current.serverURL.isEmpty {
                    syncRow(L("settings.m3u.refresh_url"), action: .url) {
                        Task { await refreshFromURL() }
                    }
                }

                syncRow(L("settings.m3u.refresh_file"), action: .file) {
                    showFileImporter = true
                }
            }

            Section(header: Text(L("download.title"))) {
                NavigationLink(L("download.title")) {
                    DownloadsView(playlist: current)
                }

                Toggle(isOn: $downloadWifiOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("download.wifi_only.title"))
                        Text(L("download.wifi_only.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent(
                    L("download.storage_used"),
                    value: downloadUsedBytes.map { $0.formatted(.byteCount(style: .file).locale(AppLocale.current)) } ?? ""
                )

                if let downloadUsedBytes, downloadUsedBytes > 0 {
                    Button(L("download.delete_all"), role: .destructive) {
                        showingDeleteAllDownloadsDialog = true
                    }
                    .confirmationDialog(L("download.delete_all"), isPresented: $showingDeleteAllDownloadsDialog) {
                        Button(L("download.delete_all"), role: .destructive) {
                            Task {
                                await DownloadManager.shared.deleteAll(playlistId: current.id)
                                await refreshDownloadUsage()
                            }
                        }
                        Button(L("common.cancel"), role: .cancel) { }
                    } message: {
                        Text(L("download.delete_all.message"))
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
                Toggle(isOn: $autoPlayNextEpisode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.player.autonext.title"))
                        Text(L("settings.player.autonext.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text(L("settings.playlist.info.title"))) {
                LabeledContent(L("settings.playlist.name")) {
                    Text(current.name).textSelection(.enabled)
                }
                LabeledContent(L("settings.playlist.type"), value: L("settings.m3u.type_label"))
                if !current.serverURL.isEmpty {
                    // Stacked, unlike the other pairs: the link is long (it carries
                    // the account) and would squeeze its label on one line. It is
                    // cut after three lines; copying gives the whole of it.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("settings.m3u.source_url"))
                        Text(current.serverURL)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                } else {
                    LabeledContent(L("settings.m3u.source"), value: L("playlists.local_file"))
                }
            }

            M3UEPGSettingsSection(playlist: $current)

            Section(header: Text(L("settings.stats.title"))) {
                LabeledContent(L("settings.stats.channel_count"), value: localStats.map { $0.channels.formatted(.number.locale(AppLocale.current)) } ?? "")
                LabeledContent(L("settings.stats.group_count"), value: localStats.map { $0.groups.formatted(.number.locale(AppLocale.current)) } ?? "")
                LabeledContent(
                    L("settings.stats.history_count"),
                    value: localStats.map { L("settings.stats.history_items_format", $0.history) } ?? ""
                )
            }

            Section(header: Text(L("settings.content_management.title"))) {
                Toggle(isOn: adultFilterBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.filter_adult.title"))
                        Text(L("settings.filter_adult.m3u_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(L("history.clear.button_entry"), role: .destructive) {
                    showClearHistoryDialog = true
                }
                .disabled((localStats?.history ?? 0) == 0)
                // After `.disabled`, so the dialog's own buttons are not disabled with the row.
                .confirmationDialog(L("history.clear.title"), isPresented: $showClearHistoryDialog) {
                    Button(L("history.clear.button_entry"), role: .destructive) {
                        Task { await clearHistory() }
                    }
                    Button(L("common.cancel"), role: .cancel) { }
                } message: {
                    Text(L("history.clear.message.all"))
                }
            }

            Section(header: Text(L("settings.about.title"))) {
                LabeledContent(L("settings.about.version")) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                        .textSelection(.enabled)
                }
                Link(destination: URL(string: "https://github.com/bsogulcan/another-iptv-player")!) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.about.github.title"))
                            // The colour, not the hierarchical style: inside a link
                            // `.secondary` is a faded tint, pale blue on white.
                            Text(L("settings.about.github.desc"))
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
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
        // Once on the form: on a section these would be applied to every row.
        .sensoryFeedback(.success, trigger: syncSuccessCount)
        .sensoryFeedback(.error, trigger: syncFailureCount)
        .task {
            await reloadStoredRow()
            await fetchStats()
            await refreshDownloadUsage()
        }
        .onReceive(DownloadManager.shared.$dbVersion.dropFirst()) { _ in
            Task { await refreshDownloadUsage() }
        }
        .refreshable {
            await reloadStoredRow()
            await fetchStats()
            await refreshDownloadUsage()
        }
    }

    // MARK: - Rows

    /// A re-import row. While its action runs it carries the spinner and, as a
    /// second line, the phase: a line of the row rather than a row of its own, and
    /// there for the whole run (blank until the first phase), so the form moves
    /// once at the start and once at the end. Both rows are disabled meanwhile.
    private func syncRow(_ title: String, action: SyncAction, perform: @escaping () -> Void) -> some View {
        let isRunning = runningAction == action
        return Button(action: perform) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if isRunning {
                        Text(syncMessage ?? " ")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                if isRunning { ProgressView() }
            }
        }
        .disabled(runningAction != nil)
        .accessibilityLabel(title)
        .accessibilityValue(isRunning ? (syncMessage ?? "") : "")
    }

    /// Shows the position the user asked for while its save is running, the stored
    /// one otherwise.
    private var adultFilterBinding: Binding<Bool> {
        Binding(
            get: { pendingAdultFilter ?? current.filterAdultContent },
            set: { newValue in
                pendingAdultFilter = newValue
                adultFilterGeneration += 1
                let generation = adultFilterGeneration
                Task { await saveFilterSetting(newValue: newValue, generation: generation) }
            }
        )
    }

    // MARK: - Local data

    private func storedRow() async -> Playlist? {
        let pid = playlist.id
        return try? await AppDatabase.shared.read { db in
            try Playlist.fetchOne(db, key: pid)
        }
    }

    /// The playlist row as it is stored now. Pull to refresh on the Channels tab
    /// and an edit change it without this screen hearing of it.
    private func reloadStoredRow() async {
        if let stored = await storedRow(), stored != current { current = stored }
    }

    private func refreshDownloadUsage() async {
        let pid = playlist.id
        let bytes = await Task.detached(priority: .utility) {
            DownloadStorage.usedBytes(playlistId: pid)
        }.value
        if downloadUsedBytes == nil {
            downloadUsedBytes = bytes
        } else {
            // A later change adds or removes the delete row.
            withAnimation { downloadUsedBytes = bytes }
        }
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
            errorMessage = NetworkErrorText.describe(err)
            showError = true
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await refreshFromLocalFile(url: url) }
        }
    }

    // MARK: - Sync

    private func refreshFromURL() async {
        guard beginSync(.url, message: L("settings.m3u.downloading")) else { return }
        do {
            // The importer writes the name and the link it is given, so they are
            // taken from the row as it is now, not as it was when this screen opened.
            let source = await storedRow() ?? current
            let content = try await M3UService().fetchRemote(urlString: source.serverURL)
            syncMessage = L("settings.m3u.parsing")
            let parsed = try await M3UParser.parseAsync(content)
            syncMessage = L("settings.m3u.saving")
            try await M3UImporter.replace(
                playlist: source,
                channels: parsed.channels,
                epgURL: parsed.epgURL
            )
            await finishSync(importedFrom: source)
        } catch {
            failSync(error)
        }
    }

    private func refreshFromLocalFile(url: URL) async {
        guard beginSync(.file, message: L("settings.m3u.reading_file")) else { return }
        do {
            let source = await storedRow() ?? current
            let content = try await M3UService().readLocalAsync(url: url)
            syncMessage = L("settings.m3u.parsing")
            let parsed = try await M3UParser.parseAsync(content)
            syncMessage = L("settings.m3u.saving")
            try await M3UImporter.replace(
                playlist: source,
                channels: parsed.channels,
                epgURL: parsed.epgURL,
                clearServerURL: true
            )
            await finishSync(importedFrom: source)
        } catch {
            failSync(error)
        }
    }

    private func beginSync(_ action: SyncAction, message: String) -> Bool {
        guard runningAction == nil else { return false }
        withAnimation {
            runningAction = action
            syncMessage = message
        }
        return true
    }

    /// The import changed the row (the header's guide URL, the link cleared by a
    /// file import), so the screen and the store continue from the stored row.
    private func finishSync(importedFrom source: Playlist) async {
        let stored = await storedRow() ?? source
        await fetchStats()
        await M3UContentStore.shared.reloadIfActive(playlist: stored)
        let latest = await storedRow() ?? current
        withAnimation {
            current = latest
            runningAction = nil
            syncMessage = nil
        }
        syncSuccessCount += 1
    }

    private func failSync(_ error: Error) {
        withAnimation {
            runningAction = nil
            syncMessage = nil
        }
        errorMessage = NetworkErrorText.describe(error)
        showError = true
        syncFailureCount += 1
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
            localStats = (channels: stats.0, groups: stats.1, history: stats.2)
        } catch {
            Log.error("Settings", "M3U stats read failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Adult Filter / History

    private func saveFilterSetting(newValue: Bool, generation: Int) async {
        do {
            let saved = try await AppDatabase.shared.updatePlaylist(id: current.id) {
                $0.filterAdultContent = newValue
            }
            if let saved { current = saved }
            if generation == adultFilterGeneration { pendingAdultFilter = nil }
            if let saved {
                await M3UContentStore.shared.reloadIfActive(playlist: saved)
            }
        } catch {
            // Nothing was saved: the switch goes back to the stored position.
            if generation == adultFilterGeneration {
                withAnimation { pendingAdultFilter = nil }
            }
            errorMessage = L("misc.save_setting_error", NetworkErrorText.describe(error))
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
            errorMessage = L("misc.history_delete_error", NetworkErrorText.describe(error))
            showError = true
        }
    }
}
