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
    @State private var errorMessage: String?
    @State private var showError = false

    init(editingPlaylist: Playlist? = nil) {
        self.editingPlaylist = editingPlaylist
        _name = State(initialValue: editingPlaylist?.name ?? "")
        _url = State(initialValue: editingPlaylist?.serverURL ?? "http://")
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

                    TextField(L("add_playlist.server_url"), text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
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
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                Section(header: Text(L("add_playlist.section.content_settings"))) {
                    Toggle(isOn: $filterAdultContent) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("add_playlist.filter_adult"))
                            Text(L("add_playlist.filter_adult.desc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(editingPlaylist == nil ? L("add_playlist.xtream.title_new") : L("add_playlist.xtream.title_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) {
                        Task { await savePlaylist() }
                    }
                    .disabled(name.isEmpty || url.isEmpty || username.isEmpty || password.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(progressMessage ?? L("add_playlist.verifying"))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(Color(.systemBackground).opacity(0.9))
                    .cornerRadius(12)
                    .shadow(radius: 20)
                }
            }
            .alert(L("common.error"), isPresented: $showError, actions: {
                Button(L("common.ok"), role: .cancel) { }
            }, message: {
                Text(errorMessage ?? L("common.unknown_error"))
            })
        }
        // Doğrulama/senkron sürerken sheet kaydırılarak kapatılamasın (bkz. AddM3UPlaylistView).
        .interactiveDismissDisabled(isLoading)
    }

    private func savePlaylist() async {
        isLoading = true
        errorMessage = nil
        progressMessage = L("add_playlist.verifying")
        
        // Carry EPG/catch-up columns over on edit so a name-only save doesn't
        // reset them (the panel timezone is otherwise re-resolved lazily later).
        var newPlaylist = Playlist(
            id: editingPlaylist?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            serverURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password.trimmingCharacters(in: .whitespacesAndNewlines),
            filterAdultContent: filterAdultContent,
            epgEnabled: editingPlaylist?.epgEnabled ?? true,
            serverTimezone: editingPlaylist?.serverTimezone,
            timeshiftStyle: editingPlaylist?.timeshiftStyle
        )

        // Credentials or filter changed check
        let detailsChanged = editingPlaylist == nil ||
            newPlaylist.serverURL != editingPlaylist?.serverURL ||
            newPlaylist.username != editingPlaylist?.username ||
            newPlaylist.password != editingPlaylist?.password ||
            newPlaylist.filterAdultContent != editingPlaylist?.filterAdultContent

        if !detailsChanged {
            // Only name changed
            do {
                try await AppDatabase.shared.write { db in
                    try newPlaylist.save(db)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
            return
        }
        
        let client = XtreamAPIClient(playlist: newPlaylist)
        
        do {
            let response = try await client.verify()

            // Capture the panel timezone for timeshift start-time conversion.
            if let tz = response.serverInfo?.timezone?.trimmingCharacters(in: .whitespacesAndNewlines), !tz.isEmpty {
                newPlaylist.serverTimezone = tz
            }

            if response.userInfo?.auth == 1 {
                await syncAndSave(newPlaylist: newPlaylist, client: client)
            } else {
                await MainActor.run {
                    errorMessage = L("add_playlist.auth_failed")
                    showError = true
                    isLoading = false
                    progressMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isLoading = false
                progressMessage = nil
            }
        }
    }
    
    private func syncAndSave(newPlaylist: Playlist, client: XtreamAPIClient) async {
        do {
            try await XtreamImporter.syncAndSave(playlist: newPlaylist, client: client) { message in
                self.progressMessage = message
            }

            await MainActor.run {
                self.isLoading = false
                self.progressMessage = nil
                // A newly added playlist might match one another device
                // already pushed favorites/progress for before this device
                // ever synced; replay from the start to pick those up.
                if editingPlaylist == nil {
                    SyncEngine.shared.resetCursor()
                }
                self.dismiss()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = L("add_playlist.download_save_error", error.localizedDescription)
                self.showError = true
                self.isLoading = false
                self.progressMessage = nil
            }
        }
    }
}

#Preview {
    AddPlaylistView()
}
