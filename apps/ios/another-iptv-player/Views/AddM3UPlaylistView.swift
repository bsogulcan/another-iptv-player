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
    @State private var errorMessage: String?
    @State private var showError = false

    init(editingPlaylist: Playlist? = nil) {
        self.editingPlaylist = editingPlaylist
        _name = State(initialValue: editingPlaylist?.name ?? "")
        _url = State(initialValue: editingPlaylist?.serverURL ?? "")
    }

    private var hasLocalFile: Bool { localContent != nil }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !isLoading else { return false }
        if hasLocalFile { return true }
        return !url.trimmingCharacters(in: .whitespaces).isEmpty
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
                }

                Section(header: Text(L("add_m3u.section.source")), footer: Text(L("add_m3u.section.source_footer"))) {
                    TextField(L("add_m3u.url_placeholder"), text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.done)
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
            .navigationTitle(editingPlaylist == nil ? L("add_m3u.title_new") : L("add_m3u.title_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) {
                        Task { await savePlaylist() }
                    }
                    .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: Self.allowedFileTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .overlay {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text(progressMessage ?? L("common.loading"))
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
            do {
                let content = try M3UService().readLocal(url: url)
                localContent = content
                localFileName = url.lastPathComponent
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Save

    private func savePlaylist() async {
        isLoading = true
        errorMessage = nil
        progressMessage = L("add_m3u.preparing")

        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let newPlaylist = Playlist(
            id: editingPlaylist?.id ?? UUID(),
            name: trimmedName,
            serverURL: hasLocalFile ? "" : trimmedURL,
            username: "",
            password: "",
            filterAdultContent: false,
            type: .m3u,
            m3uEpgURL: nil
        )

        do {
            let rawContent: String
            if let local = localContent {
                rawContent = local
            } else {
                progressMessage = L("add_m3u.downloading")
                rawContent = try await M3UService().fetchRemote(urlString: trimmedURL)
            }

            progressMessage = L("add_m3u.parsing")
            let parsed = try await M3UParser.parseAsync(rawContent)

            progressMessage = L("add_m3u.saving_db")
            try await M3UImporter.replace(
                playlist: newPlaylist,
                channels: parsed.channels,
                epgURL: parsed.epgURL,
                clearServerURL: hasLocalFile
            )

            await MainActor.run {
                self.isLoading = false
                self.progressMessage = nil
                self.dismiss()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
                self.progressMessage = nil
            }
        }
    }
}

#Preview {
    AddM3UPlaylistView()
}
