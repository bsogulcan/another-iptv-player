import SwiftUI
import GRDB
import UniformTypeIdentifiers

private enum M3UFormField: Hashable {
    case name, url
}

/// M3U/M3U8 türü playlist için ayrı ekleme ekranı. Xtream akışı etkilenmez.
struct AddM3UPlaylistView: View {
    @Environment(\.dismiss) private var dismiss

    let editingPlaylist: Playlist?

    @FocusState private var focusedField: M3UFormField?

    @State private var name: String
    @State private var url: String

    /// Yerel dosya yüklenmiş mi? (URL modu ile karşılıklı.)
    @State private var localFileName: String? = nil
    @State private var localContent: String? = nil

    @State private var showFileImporter = false

    @State private var isLoading = false
    @State private var progressMessage: String?
    /// True while the step on screen is a download, the only one whose length
    /// depends on the connection.
    @State private var isOnNetwork = false
    /// The running save or file read, kept so that Cancel can stop it.
    @State private var workTask: Task<Void, Never>?
    /// True once an Xtream import writes to the database (see `AddPlaylistView`).
    @State private var isCommitting = false
    @State private var failure: PlaylistFormFailure?
    @State private var showsFailure = false
    @State private var didSetInitialFocus = false

    init(editingPlaylist: Playlist? = nil) {
        self.editingPlaylist = editingPlaylist
        _name = State(initialValue: editingPlaylist?.name ?? "")
        _url = State(initialValue: editingPlaylist?.serverURL ?? "")
    }

    private var hasLocalFile: Bool { localContent != nil }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard !trimmedName.isEmpty, !isLoading else { return false }
        if hasLocalFile { return true }
        // Düzenlemede kaynak değişmediyse yalnız ad güncellenir; yerel dosyadan
        // eklenmiş playlist'lerde serverURL boştur, boş URL kaydı engellememeli.
        if let editing = editingPlaylist, trimmedURL == editing.serverURL { return true }
        return !trimmedURL.isEmpty
    }

    /// Compared trimmed, as saved: a stray space is not input worth a warning.
    private var hasUnsavedInput: Bool {
        hasLocalFile
            || trimmedName != (editingPlaylist?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            || trimmedURL != (editingPlaylist?.serverURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("add_playlist.section.info"))) {
                    TextField(L("add_m3u.name_placeholder"), text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }
                        .onAppear(perform: focusFirstFieldOnce)
                }

                Section(header: Text(L("add_m3u.section.source")), footer: Text(L("add_m3u.section.source_footer"))) {
                    TextField(L("add_m3u.url_placeholder"), text: $url)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.go)
                        .onSubmit(startSave)
                        .disabled(hasLocalFile)
                        .foregroundColor(hasLocalFile ? .secondary : .primary)

                    HStack {
                        Button {
                            focusedField = nil
                            showFileImporter = true
                        } label: {
                            Label(hasLocalFile ? L("add_m3u.pick_another_file") : L("add_m3u.pick_file"),
                                  systemImage: "doc.badge.plus")
                        }

                        Spacer()

                        if let local = localFileName {
                            Text(local)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    if hasLocalFile {
                        Button(role: .destructive) {
                            localFileName = nil
                            localContent = nil
                        } label: {
                            Label(L("add_m3u.remove_file"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
            // On the form only: the toolbar below keeps a working Cancel.
            .disabled(isLoading)
            .navigationTitle(editingPlaylist == nil ? L("add_m3u.title_new") : L("add_m3u.title_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: Self.allowedFileTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .modifier(PlaylistFormChrome(
                isSaving: isLoading,
                canAbortSave: !isCommitting,
                canSave: canSave,
                hasUnsavedInput: hasUnsavedInput,
                status: progressMessage,
                showsDurationHint: isOnNetwork,
                failure: failure,
                showsFailure: $showsFailure,
                save: startSave,
                close: close,
                failureDismissed: returnFocus(after:)
            ))
        }
    }

    // MARK: - Form

    /// A new form opens with the keyboard on its first field. Once only: the row
    /// appears again every time it scrolls back into view.
    private func focusFirstFieldOnce() {
        guard !didSetInitialFocus else { return }
        didSetInitialFocus = true
        if editingPlaylist == nil { focusedField = .name }
    }

    private func returnFocus(after failure: PlaylistFormFailure) {
        // The link is the only input that can be at fault here, and it is not
        // editable while a file stands in for it.
        guard failure.field == .address, !hasLocalFile else { return }
        // The alert is still on its way out when its button action runs, and a focus
        // request made right then can get lost.
        Task { focusedField = .url }
    }

    private func startSave() {
        guard canSave else { return }
        // The keyboard would cover the status line.
        focusedField = nil
        workTask = Task { await savePlaylist() }
    }

    private func close() {
        workTask?.cancel()
        dismiss()
    }

    private func report(_ error: Error) {
        // A cancelled request arrives as a wrapped URLError, so ask the task rather
        // than the error. The form is gone by then; there is nobody to tell.
        guard !Task.isCancelled else { return }
        failure = PlaylistFormFailure.describing(error)
        showsFailure = true
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
        case .failure(let error):
            failure = PlaylistFormFailure(title: L("loading.error.title"), message: NetworkErrorText.describe(error), field: nil)
            showsFailure = true
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            isLoading = true
            isOnNetwork = false
            progressMessage = L("common.loading")
            workTask = Task {
                defer {
                    isLoading = false
                    progressMessage = nil
                }
                do {
                    let content = try await M3UService().readLocalAsync(url: fileURL)
                    // The read runs detached and finishes on its own after a Cancel.
                    guard !Task.isCancelled else { return }
                    localContent = content
                    localFileName = fileURL.lastPathComponent
                    if trimmedName.isEmpty {
                        name = fileURL.deletingPathExtension().lastPathComponent
                    }
                } catch {
                    report(error)
                }
            }
        }
    }

    // MARK: - Xtream auto-detection

    /// Tries to add the detected Xtream credentials as an Xtream playlist.
    /// Returns `true` when the save flow was handled here (success or a surfaced sync
    /// error); `false` when the panel doesn't answer the Xtream API and the caller
    /// should fall back to downloading the link as plain M3U.
    private func addAsXtream(credentials: XtreamLinkDetector.Credentials, name: String) async -> Bool {
        progressMessage = L("add_m3u.xtream_detected")

        let playlist = Playlist(
            name: name,
            serverURL: credentials.serverURL,
            username: credentials.username,
            password: credentials.password,
            type: .xtream
        )
        let client = ProgressReportingXtreamClient(playlist: playlist)

        do {
            _ = try await client.verify()
        } catch {
            // get.php link without a working player_api — treat as a regular M3U link.
            return false
        }

        do {
            try await client.importCatalog(
                of: playlist,
                status: { progressMessage = $0 },
                onCommitting: {
                    isCommitting = true
                    isOnNetwork = false
                }
            )
            dismiss()
        } catch {
            // Account verified but sync failed: surface the error instead of falling
            // back, since get.php is likely blocked on such panels anyway.
            report(error)
        }
        return true
    }

    // MARK: - Save

    private func savePlaylist() async {
        isLoading = true
        isCommitting = false
        isOnNetwork = false
        progressMessage = nil
        defer {
            isLoading = false
            progressMessage = nil
        }

        let trimmedURL = self.trimmedURL
        let trimmedName = self.trimmedName

        // Source unchanged while editing (no new file picked, URL untouched — including
        // the always-empty URL of local-file playlists): only update the name. Without
        // this, local-file playlists could never be renamed at all, and URL playlists
        // re-downloaded the entire list just to change the name.
        if let editing = editingPlaylist, !hasLocalFile, trimmedURL == editing.serverURL {
            do {
                try await AppDatabase.shared.updatePlaylist(id: editing.id) { $0.name = trimmedName }
                dismiss()
            } catch {
                report(error)
            }
            return
        }

        progressMessage = L("add_m3u.preparing")

        // Xtream-style get.php links get connected through the Xtream API when possible:
        // many panels block get.php downloads, and the API unlocks VOD/series/EPG anyway.
        // Only for new playlists — converting an existing M3U playlist would orphan its
        // favorites and watch history. Falls back to the plain M3U flow below.
        if editingPlaylist == nil, !hasLocalFile,
           let credentials = XtreamLinkDetector.detect(urlString: trimmedURL) {
            isOnNetwork = true
            if await addAsXtream(credentials: credentials, name: trimmedName) { return }
            // A cancelled verify fails like a panel without the API does. It must
            // not go on to download the link as M3U.
            guard !Task.isCancelled else { return }
        }

        // An edit starts from the stored row; the form owns its name and its source.
        var newPlaylist = editingPlaylist ?? Playlist(name: trimmedName, serverURL: "", type: .m3u)
        newPlaylist.name = trimmedName
        newPlaylist.serverURL = hasLocalFile ? "" : trimmedURL

        do {
            let rawContent: String
            if let local = localContent {
                rawContent = local
            } else {
                isOnNetwork = true
                progressMessage = L("add_m3u.downloading")
                rawContent = try await M3UService().fetchRemote(urlString: trimmedURL)
            }

            isOnNetwork = false
            progressMessage = L("add_m3u.parsing")
            let parsed = try await M3UParser.parseAsync(rawContent)
            // Check again before importing, in case cancellation arrived after parsing.
            // The database write is transactional.
            try Task.checkCancellation()

            progressMessage = L("add_m3u.saving_db")
            isCommitting = true
            try await M3UImporter.replace(
                playlist: newPlaylist,
                channels: parsed.channels,
                epgURL: parsed.epgURL,
                clearServerURL: hasLocalFile
            )
            dismiss()
        } catch {
            report(error)
        }
    }
}

#Preview {
    AddM3UPlaylistView()
}
