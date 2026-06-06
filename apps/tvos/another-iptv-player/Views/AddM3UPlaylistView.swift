import SwiftUI
import GRDB

private enum M3UFormField: Hashable {
    case name, url
}

struct AddM3UPlaylistView: View {
    let editingPlaylist: Playlist?
    let onFinished: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: M3UFormField?

    @State private var name: String
    @State private var url: String
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
        _url = State(initialValue: editingPlaylist?.serverURL ?? "")
        _filterAdultContent = State(initialValue: editingPlaylist?.filterAdultContent ?? false)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !url.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isLoading
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    TextField(L("add_m3u.name_placeholder"), text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }
                } header: {
                    Text(L("add_playlist.section.info"))
                }

                Section {
                    TextField(L("add_m3u.url_placeholder"), text: $url)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .url)
                        .submitLabel(.done)
                } header: {
                    Text(L("add_m3u.section.source"))
                } footer: {
                    Text(L("add_m3u.section.source_footer"))
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
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                        Text(progressMessage ?? L("common.loading"))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .navigationTitle(editingPlaylist == nil ? L("add_m3u.title_new") : L("add_m3u.title_edit"))
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

    @MainActor
    private func savePlaylist() async {
        isLoading = true
        errorMessage = nil
        progressMessage = L("add_m3u.preparing")
        defer {
            isLoading = false
            progressMessage = nil
        }

        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let newPlaylist = Playlist(
            id: editingPlaylist?.id ?? UUID(),
            name: trimmedName,
            serverURL: trimmedURL,
            username: "",
            password: "",
            filterAdultContent: filterAdultContent,
            type: .m3u,
            m3uEpgURL: nil
        )

        do {
            progressMessage = L("add_m3u.downloading")
            let rawContent = try await M3UService().fetchRemote(urlString: trimmedURL)

            progressMessage = L("add_m3u.parsing")
            let parsed = try await M3UParser.parseAsync(rawContent)

            let visibleChannels = filterAdultContent
                ? parsed.channels.filter { ch in
                    if AdultContentFilter.isAdultCategoryName(ch.name) { return false }
                    if let group = ch.groupTitle, AdultContentFilter.isAdultCategoryName(group) { return false }
                    return true
                  }
                : parsed.channels

            progressMessage = L("add_m3u.saving_db")
            try await M3UImporter.replace(
                playlist: newPlaylist,
                channels: visibleChannels,
                epgURL: parsed.epgURL,
                clearServerURL: false
            )

            onFinished()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
