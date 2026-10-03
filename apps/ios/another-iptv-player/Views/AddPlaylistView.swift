import SwiftUI
import GRDB

private enum PlaylistFormField: Hashable {
    case name, url, username, password
}

struct AddPlaylistView: View {
    @Environment(\.dismiss) private var dismiss

    let editingPlaylist: Playlist?

    @FocusState private var focusedField: PlaylistFormField?

    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String

    @State private var filterAdultContent: Bool

    @State private var isLoading = false
    @State private var progressMessage: String?
    /// The running save, kept so that Cancel can stop it.
    @State private var saveTask: Task<Void, Never>?
    /// True once the import writes to the database. From there it runs to the end,
    /// so there is nothing left for Cancel to stop.
    @State private var isCommitting = false
    @State private var failure: PlaylistFormFailure?
    @State private var showsFailure = false
    @State private var didSetInitialFocus = false

    init(editingPlaylist: Playlist? = nil) {
        self.editingPlaylist = editingPlaylist
        _name = State(initialValue: editingPlaylist?.name ?? "")
        _url = State(initialValue: editingPlaylist?.serverURL ?? "")
        _username = State(initialValue: editingPlaylist?.username ?? "")
        _password = State(initialValue: editingPlaylist?.password ?? "")
        _filterAdultContent = State(initialValue: editingPlaylist?.filterAdultContent ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("add_playlist.section.info"))) {
                    TextField(L("add_playlist.name_placeholder"), text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }
                        .onAppear(perform: focusFirstFieldOnce)

                    // The expected shape is a prompt, not text in the field: a pasted
                    // address would land behind it ("http://http://…").
                    TextField(L("add_playlist.server_url"), text: $url, prompt: Text(verbatim: "http://example.com:8080"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit {
                            applyAccountLink()
                            focusedField = .username
                        }
                        .onChange(of: url) { old, new in
                            // Growing by several characters at once is a paste. A link
                            // typed by hand is left alone until the field is submitted:
                            // it becomes a complete account link at the first character
                            // of the password and would be rewritten under the cursor.
                            if new.count > old.count + 1 { applyAccountLink() }
                        }
                }

                Section(header: Text(L("add_playlist.section.credentials"))) {
                    TextField(L("add_playlist.username"), text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField(L("add_playlist.password"), text: $password)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(startSave)
                }

                Section {
                    Toggle(L("add_playlist.filter_adult"), isOn: $filterAdultContent)
                } header: {
                    Text(L("add_playlist.section.content_settings"))
                } footer: {
                    Text(L("onboarding.filter_adult.footer"))
                }
            }
            // On the form only: the toolbar below keeps a working Cancel.
            .disabled(isLoading)
            .navigationTitle(editingPlaylist == nil ? L("add_playlist.xtream.title_new") : L("add_playlist.xtream.title_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .modifier(PlaylistFormChrome(
                isSaving: isLoading,
                canAbortSave: !isCommitting,
                canSave: canSave,
                hasUnsavedInput: hasUnsavedInput,
                status: progressMessage,
                showsDurationHint: !isCommitting,
                failure: failure,
                showsFailure: $showsFailure,
                save: startSave,
                close: close,
                failureDismissed: returnFocus(after:)
            ))
        }
    }

    // MARK: - Input

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPassword: String { password.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The address to store. While the field still holds what an edit was opened
    /// with, that is the stored text itself: normalising it would count as a change
    /// of server and turn a rename into a full re-import.
    private var resolvedServerURL: String? {
        let typed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing = editingPlaylist, typed == editing.serverURL.trimmingCharacters(in: .whitespacesAndNewlines) {
            return editing.serverURL
        }
        return XtreamLinkDetector.normalizedServerURL(typed)
    }

    private var canSave: Bool {
        guard !isLoading, !trimmedName.isEmpty else { return false }
        // A complete account link in the address field brings its own user name and
        // password; `savePlaylist` moves them into their fields.
        if XtreamLinkDetector.detect(urlString: url) != nil { return true }
        return resolvedServerURL != nil && !trimmedUsername.isEmpty && !trimmedPassword.isEmpty
    }

    /// Compared trimmed, as saved: a stray space is not input worth a warning.
    private var hasUnsavedInput: Bool {
        func differs(_ value: String, _ stored: String?) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                != (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return differs(name, editingPlaylist?.name)
            || differs(url, editingPlaylist?.serverURL)
            || differs(username, editingPlaylist?.username)
            || differs(password, editingPlaylist?.password)
            || filterAdultContent != (editingPlaylist?.filterAdultContent ?? false)
    }

    /// Providers send the account as one link (`…/get.php?username=…&password=…`).
    /// Pasted into the address field it fills the form it describes.
    private func applyAccountLink() {
        guard let link = XtreamLinkDetector.detect(urlString: url) else { return }
        url = link.serverURL
        username = link.username
        password = link.password
        if trimmedName.isEmpty, let host = URLComponents(string: link.serverURL)?.host {
            name = host
        }
    }

    /// A new form opens with the keyboard on its first field. Once only: the row
    /// appears again every time it scrolls back into view.
    private func focusFirstFieldOnce() {
        guard !didSetInitialFocus else { return }
        didSetInitialFocus = true
        if editingPlaylist == nil { focusedField = .name }
    }

    private func returnFocus(after failure: PlaylistFormFailure) {
        let field: PlaylistFormField
        switch failure.field {
        case .address: field = .url
        case .credentials: field = .username
        case nil: return
        }
        // The alert is still on its way out when its button action runs, and a focus
        // request made right then can get lost.
        Task { focusedField = field }
    }

    // MARK: - Save

    private func startSave() {
        guard canSave else { return }
        // The keyboard would cover the status line.
        focusedField = nil
        saveTask = Task { await savePlaylist() }
    }

    private func close() {
        saveTask?.cancel()
        dismiss()
    }

    private func report(_ error: Error) {
        // A cancelled request arrives as a wrapped URLError, so ask the task rather
        // than the error. The form is gone by then; there is nobody to tell.
        guard !Task.isCancelled else { return }
        failure = PlaylistFormFailure.describing(error)
        showsFailure = true
    }

    private func savePlaylist() async {
        applyAccountLink()
        guard let serverURL = resolvedServerURL else { return }

        isLoading = true
        isCommitting = false
        progressMessage = nil
        defer {
            isLoading = false
            progressMessage = nil
        }

        // An edit starts from the stored row: the form owns five of its columns and
        // must hand the others (guide settings, panel timezone, catch-up probe
        // result, creation date) back as they were.
        var newPlaylist = editingPlaylist ?? Playlist(name: trimmedName, serverURL: serverURL)
        newPlaylist.name = trimmedName
        newPlaylist.serverURL = serverURL
        newPlaylist.username = trimmedUsername
        newPlaylist.password = trimmedPassword
        newPlaylist.filterAdultContent = filterAdultContent

        if let editing = editingPlaylist,
           newPlaylist.serverURL == editing.serverURL,
           newPlaylist.username == editing.username,
           newPlaylist.password == editing.password,
           newPlaylist.filterAdultContent == editing.filterAdultContent {
            // Only the name changed: nothing to download.
            do {
                let newName = newPlaylist.name
                try await AppDatabase.shared.updatePlaylist(id: editing.id) { $0.name = newName }
                dismiss()
            } catch {
                report(error)
            }
            return
        }

        let client = ProgressReportingXtreamClient(playlist: newPlaylist)
        progressMessage = L("add_playlist.verifying")
        do {
            let response = try await client.verify()

            // Capture the panel timezone for timeshift start-time conversion.
            if let tz = response.serverInfo?.timezone?.trimmingCharacters(in: .whitespacesAndNewlines), !tz.isEmpty {
                newPlaylist.serverTimezone = tz
            }

            try await client.importCatalog(
                of: newPlaylist,
                status: { progressMessage = $0 },
                onCommitting: { isCommitting = true }
            )
            dismiss()
        } catch {
            report(error)
        }
    }
}

#Preview {
    AddPlaylistView()
}

// MARK: - Shared by the Xtream and the M3U form

/// What a form tells the user when a save fails: a title that names the problem, a
/// sentence a person can act on, and the input to send them back to.
struct PlaylistFormFailure: Equatable {
    enum Field {
        case address
        case credentials
    }

    let title: String
    let message: String
    /// Nil when no field is at fault (offline, a file that cannot be read, the database).
    let field: Field?

    /// The one place where the forms turn an error into text. The descriptions of
    /// the panel and M3U errors wrap the Foundation text ("Network error: The data
    /// couldn't be read because…") and are shared with the refresh paths, so they
    /// are replaced here instead of changed there.
    static func describing(_ error: Error) -> PlaylistFormFailure {
        switch error {
        case let error as XtreamError:
            switch error {
            case .unauthenticated:
                return PlaylistFormFailure(
                    title: L("onboarding.error.title.sign_in"), message: L("misc.xtream.auth_error"), field: .credentials
                )
            case .networkError(let underlying):
                return connection(underlying)
            case .decodingError:
                return unreachable(L("onboarding.error.not_xtream"))
            case .serverError(let status):
                return unreachable(L("onboarding.error.http", status))
            case .invalidURL:
                return unreachable(L("onboarding.error.invalid_address"))
            }
        case let error as M3UServiceError:
            switch error {
            case .networkError(let underlying):
                return connection(underlying)
            case .serverError(let code):
                return unreachable(L("onboarding.error.http", "HTTP \(code)"))
            case .invalidURL:
                return unreachable(L("onboarding.error.invalid_address"))
            case .fileReadError, .encodingUnsupported:
                return PlaylistFormFailure(title: L("loading.error.title"), message: NetworkErrorText.describe(error), field: nil)
            }
        case let error as M3UParserError:
            // Empty, or not a playlist at all: the link or the file is the wrong one.
            return PlaylistFormFailure(title: L("loading.error.title"), message: NetworkErrorText.describe(error), field: .address)
        default:
            // Foundation and database messages follow the device language. Keep the
            // form in the app's language, as with other browse errors.
            return PlaylistFormFailure(title: L("onboarding.error.title.save"), message: NetworkErrorText.describe(error), field: nil)
        }
    }

    private static func unreachable(_ message: String) -> PlaylistFormFailure {
        PlaylistFormFailure(title: L("onboarding.error.title.connection"), message: message, field: .address)
    }

    private static func connection(_ underlying: Error) -> PlaylistFormFailure {
        switch (underlying as? URLError)?.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return PlaylistFormFailure(
                title: L("onboarding.error.title.connection"), message: L("onboarding.error.offline"), field: nil
            )
        case .timedOut:
            return unreachable(L("onboarding.error.timeout"))
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .badURL, .unsupportedURL:
            return unreachable(L("onboarding.error.unreachable"))
        default:
            return unreachable(L("onboarding.error.connection"))
        }
    }
}

/// Which of the three large lists of an Xtream import have not arrived yet.
struct XtreamDownloadProgress: Equatable {
    enum Part: CaseIterable {
        case live, movies, series
    }

    private(set) var outstanding: [Part] = Part.allCases

    mutating func finish(_ part: Part) {
        outstanding.removeAll { $0 == part }
    }

    /// Names a list that is still downloading, so the text is true for as long as
    /// it stands. With all three in, only the category lists can still be missing.
    var message: String {
        switch outstanding.first {
        case .live: return L("add_playlist.fetching_live")
        case .movies: return L("add_playlist.fetching_movies")
        case .series: return L("add_playlist.fetching_series")
        case nil: return L("add_playlist.fetching_categories")
        }
    }
}

/// The panel client of the two forms. It reports each of the large lists as it
/// arrives: the importer announces the whole download as "categories", which are
/// in after a second while the movie and series lists take the rest of the wait.
final class ProgressReportingXtreamClient: XtreamAPIClient {
    private var progress = XtreamDownloadProgress()
    private var status: (@MainActor (String) -> Void)?
    private var isWriting = false

    /// Imports the catalog of `playlist` through this client. `status` receives the
    /// text to show. `onCommitting` is called when the import starts to write; from
    /// then on cancelling the task no longer stops it. `database` is injected by
    /// tests; the app writes to the shared one.
    func importCatalog(
        of playlist: Playlist,
        database: AppDatabase = .shared,
        status: @escaping @MainActor (String) -> Void,
        onCommitting: @escaping @MainActor () -> Void
    ) async throws {
        progress = XtreamDownloadProgress()
        isWriting = false
        self.status = status
        defer { self.status = nil }

        try await XtreamImporter.syncAndSave(
            playlist: playlist,
            client: self,
            database: database,
            progress: { message in
                // Of the importer's two texts only the one for the write is shown.
                if self.isWriting { status(message) }
            },
            onPhase: { phase in
                switch phase {
                case .downloading:
                    status(self.progress.message)
                case .saving:
                    self.isWriting = true
                    onCommitting()
                }
            }
        )
    }

    override func getLiveStreams(categoryId: String? = nil) async throws -> [XtreamLiveStream] {
        let streams = try await super.getLiveStreams(categoryId: categoryId)
        finish(.live)
        return streams
    }

    override func getVODStreams(categoryId: String? = nil) async throws -> [XtreamVODStream] {
        let streams = try await super.getVODStreams(categoryId: categoryId)
        finish(.movies)
        return streams
    }

    override func getSeries(categoryId: String? = nil) async throws -> [XtreamSeries] {
        let series = try await super.getSeries(categoryId: categoryId)
        finish(.series)
        return series
    }

    private func finish(_ part: XtreamDownloadProgress.Part) {
        progress.finish(part)
        if !isWriting { status?(progress.message) }
    }
}

/// Toolbar, status line, failure alert and dismissal rules of an add / edit form.
/// Applied to the form itself, after its own `.disabled`, so that Cancel stays
/// usable while everything else is locked.
struct PlaylistFormChrome: ViewModifier {
    let isSaving: Bool
    /// False from the moment the running save can no longer be abandoned.
    let canAbortSave: Bool
    let canSave: Bool
    let hasUnsavedInput: Bool
    let status: String?
    /// Whether the wait depends on the connection (a download, not a local step).
    let showsDurationHint: Bool
    let failure: PlaylistFormFailure?
    @Binding var showsFailure: Bool
    let save: () -> Void
    /// Stops whatever is running and closes the form.
    let close: () -> Void
    let failureDismissed: (PlaylistFormFailure) -> Void

    @State private var isConfirmingDiscard = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) {
                        // A running save is stopped and the form closed without a
                        // second question; only idle input is worth asking about.
                        if isSaving || !hasUnsavedInput {
                            close()
                        } else {
                            isConfirmingDiscard = true
                        }
                    }
                    .disabled(isSaving && !canAbortSave)
                    // On the button, so the dialog opens from it where the system
                    // anchors dialogs to their source.
                    .confirmationDialog(
                        L("onboarding.form.discard"), isPresented: $isConfirmingDiscard, titleVisibility: .hidden
                    ) {
                        Button(L("onboarding.form.discard"), role: .destructive, action: close)
                        Button(L("onboarding.form.keep_editing"), role: .cancel) { }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L("common.save"), action: save)
                            .disabled(!canSave)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSaving, let status {
                    LoadingProcessView(message: status, showsDurationHint: showsDurationHint)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: isSaving)
            .alert(failure?.title ?? L("common.error"), isPresented: $showsFailure, presenting: failure) { failure in
                Button(L("common.ok"), role: .cancel) { failureDismissed(failure) }
            } message: { failure in
                Text(failure.message)
            }
            // A swipe must not close the sheet under a running save, which would go
            // on unseen, nor throw away an address and a password typed by hand.
            // The swipe has no callback, so the question itself is asked by Cancel.
            .interactiveDismissDisabled(isSaving || hasUnsavedInput)
            // Downloading a large panel takes minutes, and a locked phone suspends
            // the requests. The forms are only reachable from the playlist list,
            // where nothing plays, so nobody else has a say in the idle timer here.
            // Tied to the form being on screen: a cancelled save unwinds after the
            // sheet has gone, possibly into a player that wants the screen kept on.
            .onChange(of: isSaving) { _, saving in
                UIApplication.shared.isIdleTimerDisabled = saving
            }
            .onDisappear {
                if isSaving { UIApplication.shared.isIdleTimerDisabled = false }
            }
    }
}
