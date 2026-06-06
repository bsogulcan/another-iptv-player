import SwiftUI
import GRDB

private enum PlaylistFormField: Hashable {
    case name, url, username, password
}

struct AddPlaylistView: View {
    let editingPlaylist: Playlist?
    let onFinished: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: PlaylistFormField?

    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String
    @State private var filterAdultContent: Bool

    @State private var isLoading = false
    @State private var progressMessage: String?
    @State private var errorMessage: String?
    @State private var showError = false

    init(
        editingPlaylist: Playlist? = nil,
        onFinished: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.editingPlaylist = editingPlaylist
        self.onFinished = onFinished
        self.onCancel = onCancel
        _name = State(initialValue: editingPlaylist?.name ?? "")
        _url = State(initialValue: editingPlaylist?.serverURL ?? "http://")
        _username = State(initialValue: editingPlaylist?.username ?? "")
        _password = State(initialValue: editingPlaylist?.password ?? "")
        _filterAdultContent = State(initialValue: editingPlaylist?.filterAdultContent ?? false)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isLoading
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    TextField(L("add_playlist.name_placeholder"), text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }

                    TextField(L("add_playlist.server_url"), text: $url)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                } header: {
                    Text(L("add_playlist.section.info"))
                }

                Section {
                    TextField(L("add_playlist.username"), text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField(L("add_playlist.password"), text: $password)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                } header: {
                    Text(L("add_playlist.section.credentials"))
                }

                Section {
                    Toggle(L("add_playlist.filter_adult"), isOn: $filterAdultContent)
                } header: {
                    Text(L("add_playlist.section.content_settings"))
                } footer: {
                    Text(L("add_playlist.filter_adult.desc"))
                }
            }

            if isLoading {
                loadingOverlay
            }
        }
        .navigationTitle(editingPlaylist == nil ? L("add_playlist.xtream.title_new") : L("add_playlist.xtream.title_edit"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("common.cancel")) { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("common.save")) {
                    Task { await savePlaylist() }
                }
                .disabled(!canSave)
            }
        }
        .alert(L("common.error"), isPresented: $showError) {
            Button(L("common.ok"), role: .cancel) { }
        } message: {
            Text(errorMessage ?? L("common.unknown_error"))
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                Text(progressMessage ?? L("add_playlist.verifying"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @MainActor
    private func savePlaylist() async {
        isLoading = true
        errorMessage = nil
        progressMessage = L("add_playlist.verifying")
        defer {
            isLoading = false
            progressMessage = nil
        }

        let newPlaylist = Playlist(
            id: editingPlaylist?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            serverURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password.trimmingCharacters(in: .whitespacesAndNewlines),
            filterAdultContent: filterAdultContent
        )

        let detailsChanged = editingPlaylist == nil ||
            newPlaylist.serverURL != editingPlaylist?.serverURL ||
            newPlaylist.username != editingPlaylist?.username ||
            newPlaylist.password != editingPlaylist?.password ||
            newPlaylist.filterAdultContent != editingPlaylist?.filterAdultContent

        if !detailsChanged {
            do {
                try await AppDatabase.shared.write { db in try newPlaylist.save(db) }
                onFinished()
            } catch {
                present(error: error.localizedDescription)
            }
            return
        }

        do {
            let response = try await XtreamAPIClient(playlist: newPlaylist).verify()
            guard response.userInfo?.auth == 1 else {
                present(error: L("add_playlist.auth_failed"))
                return
            }

            try await PlaylistSyncService.syncReplacingLocal(
                playlist: newPlaylist,
                persistPlaylistRow: true
            ) { phase in
                Task { @MainActor in
                    progressMessage = localizedProgress(for: phase)
                }
            }

            onFinished()
        } catch {
            present(error: L("add_playlist.download_save_error", error.localizedDescription))
        }
    }

    private func present(error message: String) {
        errorMessage = message
        showError = true
    }

    /// Match the phase wording the Add flow used before (different from Refresh).
    private func localizedProgress(for phase: PlaylistSyncService.Phase) -> String {
        switch phase {
        case .clearing:        return L("add_playlist.verifying")
        case .fetchCategories: return L("add_playlist.fetching_categories")
        case .fetchLive:       return L("add_playlist.fetching_live")
        case .fetchMovies:     return L("add_playlist.fetching_movies")
        case .fetchSeries:     return L("add_playlist.fetching_series")
        case .saving:          return L("add_playlist.saving_db")
        }
    }
}
