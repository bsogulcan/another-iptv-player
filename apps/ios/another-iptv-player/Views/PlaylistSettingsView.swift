import SwiftUI
import UIKit
import Combine
import GRDB

struct PlaylistSettingsView: View {
    let playlist: Playlist
    let onDismiss: () -> Void

    /// The playlist row as stored. `playlist` is the value the dashboard was opened
    /// with and never changes afterwards, so everything shown here, handed to the
    /// stores or passed to the sections below comes from this copy, which is
    /// replaced by the row every write returns and re-read whenever the form appears.
    @State private var current: Playlist

    @State private var authResponse: XtreamAuthResponse?
    /// The account request is running and there is no earlier answer to show.
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lastAccountFetch: Date?
    /// Katalog yenileme (syncContents) hatası — playlist bilgi hatasından (errorMessage)
    /// ayrı tutulur; eskiden ikisi karışıyor ve "Try Again" yanlış işlemi tetikliyordu.
    @State private var syncError: String?
    /// A failed local write (history delete, saving a setting), shown as an alert.
    @State private var actionError: String?

    @State private var isPasswordRevealed = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var isSyncing = false
    /// The row that started the running (or last) download: its progress and its
    /// failure are shown next to that row, which is where the user is looking.
    @State private var syncOrigin: SyncOrigin = .refreshRow
    @State private var progressMessage: String?
    @State private var syncSuccessCount = 0
    @State private var syncFailureCount = 0

    /// Row counts of the local catalog; nil until the first read, so the rows do
    /// not show a zero that is replaced a moment later.
    @State private var localStats: (live: Int, vod: Int, series: Int, history: Int)?

    /// The switch position the user asked for, waiting for the confirmation dialog.
    @State private var adultFilterPrompt: Bool?
    /// The confirmed position while its save is on the way to the database.
    @State private var adultFilterSaving: Bool?
    @State private var showClearHistoryDialog = false

    @AppStorage("player.pipEnabled") private var pipEnabled = true
    @AppStorage("player.continuePlayingInBackground") private var continuePlayingInBackground = true
    @AppStorage("player.speedUpOnLongPress") private var speedUpOnLongPress = true
    @AppStorage("player.autoPlayNextEpisode") private var autoPlayNextEpisode = true
    @AppStorage("download.wifi_only") private var downloadWifiOnly = false

    /// nil until the first measurement.
    @State private var downloadUsedBytes: Int64?
    @State private var showingDeleteAllDownloadsDialog = false

    private enum SyncOrigin {
        case refreshRow
        case adultFilter
    }

    /// How long a successful account answer is reused. The form re-appears on every
    /// tab switch and every pop back from a pushed screen, and each of those sent a
    /// request to the panel. Pull to refresh asks again at once.
    private static let accountInfoLifetime: TimeInterval = 300

    /// Stands in for the password until it is revealed. A fixed length: one bullet
    /// per character gave the real length away.
    private static let passwordMask = String(repeating: "•", count: 8)

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

                Button {
                    Task { await syncContents(origin: .refreshRow) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.refresh_all"))
                            // The phase is a second line of this row rather than a row
                            // of its own, and the line is there for the whole download
                            // (blank until the first phase), so the form moves once
                            // when it starts and once when it ends.
                            if isSyncing {
                                Text(progressMessage ?? " ")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        Spacer()
                        if isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncing)
                .accessibilityLabel(L("settings.refresh_all"))
                .accessibilityValue(isSyncing ? (progressMessage ?? "") : "")

                if let syncError, syncOrigin == .refreshRow {
                    syncErrorRow(syncError)
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

                Toggle(isOn: $autoPlayNextEpisode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.player.autonext.title"))
                        Text(L("settings.player.autonext.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // — Playlist & Abonelik Bilgileri (birleşik) —
            Section {
                LabeledContent(L("settings.playlist.name")) {
                    Text(current.name).textSelection(.enabled)
                }

                LabeledContent(L("settings.playlist.server_url")) {
                    Text(current.serverURL).textSelection(.enabled)
                }

                LabeledContent(L("settings.playlist.username")) {
                    Text(current.username).textSelection(.enabled)
                }

                passwordRow

                // The three account rows are always there and only their value side
                // changes (spinner, value or a dash), so nothing below them moves
                // when the panel answers, fails or is asked again.
                LabeledContent(L("settings.playlist.subscription")) {
                    accountValue { calculateRemainingDays(expDate: $0.expDate) }
                }

                LabeledContent(L("settings.playlist.active_connection")) {
                    accountValue { $0.activeCons ?? L("settings.playlist.unknown") }
                }

                LabeledContent(L("settings.playlist.max_connection")) {
                    accountValue { $0.maxConnections ?? L("settings.playlist.unlimited") }
                }
            } header: {
                Text(L("settings.playlist.info.title"))
            } footer: {
                // Pull to refresh is the retry; the values of the last answer stay
                // on screen above this line.
                if let errorMessage {
                    Text(L("settings.playlist.info_error", errorMessage))
                }
            }

            // — İçerik İstatistikleri —
            // Local sections (statistics, guide, content management) read the database
            // only, so they do not wait for the account request and are there offline.
            Section(header: Text(L("settings.stats.title"))) {
                LabeledContent(L("settings.stats.live_count"), value: localStats.map { $0.live.formatted(.number.locale(AppLocale.current)) } ?? "")
                LabeledContent(L("settings.stats.movie_count"), value: localStats.map { $0.vod.formatted(.number.locale(AppLocale.current)) } ?? "")
                LabeledContent(L("settings.stats.series_count"), value: localStats.map { $0.series.formatted(.number.locale(AppLocale.current)) } ?? "")
                LabeledContent(
                    L("settings.stats.history_count"),
                    value: localStats.map { L("settings.stats.history_items_format", $0.history) } ?? ""
                )
            }

            // — Sunucu Bilgileri —
            if authResponse?.serverInfo?.timezone != nil
                || (authResponse?.userInfo?.message.map { !$0.isEmpty } ?? false) {
                Section(header: Text(L("settings.server.title"))) {
                    if let timeZone = authResponse?.serverInfo?.timezone {
                        LabeledContent(L("settings.server.timezone"), value: timeZone)
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

            // — EPG (TV Rehberi) —
            XtreamEPGSettingsSection(playlist: $current)

            // — İçerik Yönetimi —
            Section(header: Text(L("settings.content_management.title"))) {
                Toggle(isOn: adultFilterBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.filter_adult.title"))
                        Text(L("settings.filter_adult.xtream_desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // A flip during a download would be saved without being applied.
                .disabled(isSyncing || adultFilterSaving != nil)
                // The new value is handed to the actions as data: the dialog clears
                // the prompt when it closes, and the order of that and the button's
                // action is not ours to rely on.
                .confirmationDialog(
                    L("settings.filter_adult.title"),
                    isPresented: adultFilterPromptPresented,
                    titleVisibility: .visible,
                    presenting: adultFilterPrompt
                ) { newValue in
                    Button(L("settings.refresh_all")) {
                        applyAdultFilter(newValue)
                    }
                    Button(L("common.cancel"), role: .cancel) { }
                } message: { _ in
                    Text(L("settings.filter_adult.xtream_desc"))
                }

                if syncOrigin == .adultFilter {
                    if isSyncing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(progressMessage ?? L("settings.refresh_all"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else if let syncError {
                        syncErrorRow(syncError)
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
        .alert(
            L("common.error"),
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button(L("common.ok"), role: .cancel) { }
        } message: {
            Text(actionError ?? L("common.unknown_error"))
        }
        // Once on the form: on a section these would be applied to every row.
        .sensoryFeedback(.success, trigger: syncSuccessCount)
        .sensoryFeedback(.error, trigger: syncFailureCount)
        // A revealed password must not stay readable behind another tab, a pushed
        // screen or the app switcher. On the form, not on the row: a row also
        // "disappears" when it scrolls out of view.
        .onDisappear { isPasswordRevealed = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isPasswordRevealed = false }
        }
        .task {
            // The row first: the account request may write to it (the panel's
            // timezone), and a read that started earlier must not land on top of
            // that. Then the local values next to the request, not after it: it can
            // take as long as the panel's timeout, and only the account rows need it.
            await reloadStoredRow()
            async let account: Void = fetchAuthInfo()
            await fetchLocalStats()
            await refreshDownloadUsage()
            await account
        }
        // A failed account request is asked again once the connection comes back.
        .onReceive(NetworkStatus.shared.$reconnectCount.dropFirst()) { _ in
            guard errorMessage != nil else { return }
            Task { await fetchAuthInfo(force: true) }
        }
        .refreshable {
            await reloadStoredRow()
            async let account: Void = fetchAuthInfo(force: true)
            await fetchLocalStats()
            await refreshDownloadUsage()
            await account
        }
    }

    // MARK: - Rows

    /// The whole row is the control, as tall as its neighbours: a 44 pt eye button
    /// inside the row made this one row taller than the rest.
    private var passwordRow: some View {
        Button {
            isPasswordRevealed.toggle()
        } label: {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(isPasswordRevealed ? current.password : Self.passwordMask)
                        .foregroundStyle(Color.secondary)
                    Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(Color.accentColor)
                }
            } label: {
                // Colours, not hierarchical styles: inside a button those resolve
                // against the tint and the row would turn blue.
                Text(L("settings.playlist.password"))
                    .foregroundStyle(Color.primary)
            }
        }
        .accessibilityLabel(L("settings.playlist.password"))
        .accessibilityValue(isPasswordRevealed ? current.password : "")
        .accessibilityHint(isPasswordRevealed ? L("settings.hide_password") : L("settings.show_password"))
        // Text selection does not work inside a button label, so copying is a menu.
        .contextMenu {
            Button {
                UIPasteboard.general.string = current.password
            } label: {
                Label(L("settings.copy"), systemImage: "doc.on.doc")
            }
        }
    }

    /// Value side of an account row: the value once the panel has answered (kept
    /// while it is asked again and after a later failure), a spinner during the
    /// first request, a dash when there is nothing to show.
    @ViewBuilder
    private func accountValue(_ text: (XtreamUserInfo) -> String) -> some View {
        if let userInfo = authResponse?.userInfo {
            Text(text(userInfo))
        } else if isLoading {
            ProgressView()
        } else {
            Text(verbatim: "—")
        }
    }

    private func syncErrorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
            Button(L("common.try_again")) {
                Task { await syncContents(origin: syncOrigin) }
            }
            .font(.caption.weight(.semibold))
        }
    }

    // MARK: - Adult filter

    /// Shows the position the user asked for while the dialog is up and while the
    /// save is running, the stored one otherwise. Flipping the switch only asks:
    /// the change means downloading the whole catalog again.
    private var adultFilterBinding: Binding<Bool> {
        Binding(
            get: { adultFilterPrompt ?? adultFilterSaving ?? current.filterAdultContent },
            set: { adultFilterPrompt = $0 }
        )
    }

    private var adultFilterPromptPresented: Binding<Bool> {
        Binding(
            get: { adultFilterPrompt != nil },
            // Animated, so a cancelled switch slides back instead of jumping.
            set: { presented in
                if !presented { withAnimation { adultFilterPrompt = nil } }
            }
        )
    }

    private func applyAdultFilter(_ newValue: Bool) {
        guard !isSyncing, adultFilterSaving == nil else { return }
        adultFilterSaving = newValue
        Task { await saveFilterSetting(newValue: newValue) }
    }

    private func saveFilterSetting(newValue: Bool) async {
        do {
            let saved = try await AppDatabase.shared.updatePlaylist(id: current.id) {
                $0.filterAdultContent = newValue
            }
            if let saved { current = saved }
            adultFilterSaving = nil
            guard saved != nil else { return }
            // Filtre değişince içerikleri otomatik yeniden indir
            await syncContents(origin: .adultFilter)
        } catch {
            // Nothing was saved and nothing is downloaded: the switch goes back.
            withAnimation { adultFilterSaving = nil }
            actionError = L("misc.save_setting_error", error.localizedDescription)
        }
    }

    // MARK: - Local data

    /// The playlist row as it is stored now. Other writers (the guide's timezone
    /// and catch-up probes, an edit) change it without this screen hearing of it.
    private func reloadStoredRow() async {
        let pid = playlist.id
        let stored = try? await AppDatabase.shared.read { db in
            try Playlist.fetchOne(db, key: pid)
        }
        if let stored, stored != current { current = stored }
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
            localStats = (live: counts.0, vod: counts.1, series: counts.2, history: counts.3)
        } catch {
            Log.error("Settings", "stats read failed: \(error.localizedDescription)")
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
            actionError = L("misc.history_delete_error", error.localizedDescription)
        }
    }

    // MARK: - Account

    private func fetchAuthInfo(force: Bool = false) async {
        if !force, let last = lastAccountFetch, Date().timeIntervalSince(last) < Self.accountInfoLifetime {
            return
        }
        // With an answer on screen the rows stay as they are while the panel is
        // asked again; the row spinners are for the first request only. An earlier
        // failure also stays until this request has its own outcome.
        if authResponse == nil { isLoading = true }
        let client = XtreamAPIClient(playlist: current)
        do {
            let response = try await client.verify()
            withAnimation {
                authResponse = response
                errorMessage = nil
                isLoading = false
            }
            lastAccountFetch = Date()
            // Refresh the cached panel timezone (used for timeshift start-time
            // conversion) whenever it changed.
            if let tz = response.serverInfo?.timezone?.trimmingCharacters(in: .whitespacesAndNewlines),
               !tz.isEmpty, tz != current.serverTimezone {
                let saved = try? await AppDatabase.shared.updatePlaylist(id: current.id) {
                    $0.serverTimezone = tz
                }
                if let saved { current = saved }
            }
        } catch {
            // Leaving the tab cancels the request. That is not a failure to report,
            // and the next appearance asks again.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                isLoading = false
                return
            }
            withAnimation {
                errorMessage = NetworkErrorText.describe(error)
                isLoading = false
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

    // MARK: - Catalog download

    private func syncContents(origin: SyncOrigin) async {
        // One download at a time: a second one would fetch the same catalog again,
        // and whichever finished first would clear the other's progress.
        guard !isSyncing else { return }
        withAnimation {
            isSyncing = true
            syncOrigin = origin
            syncError = nil
            progressMessage = nil
        }

        do {
            // The store takes the adult-content flag from the stored row, inside
            // its write.
            try await PlaylistContentStore.shared.syncFromNetworkReplacingLocal(playlist: current) { msg in
                progressMessage = msg
            }
            await fetchLocalStats()
            await PlaylistContentStore.shared.reloadFromDatabaseIfActive(playlistId: current.id)
            withAnimation {
                isSyncing = false
                progressMessage = nil
            }
            syncSuccessCount += 1
        } catch {
            withAnimation {
                syncError = L("misc.refresh_error", NetworkErrorText.describe(error))
                isSyncing = false
                progressMessage = nil
            }
            syncFailureCount += 1
        }
    }
}
