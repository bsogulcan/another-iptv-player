import GRDB
import SwiftUI
import UniformTypeIdentifiers

struct SourceEditor: View {
  @Environment(\.appDatabase) private var database
  @State private var draft: SourceDraft
  private enum Field { case name, address, username, password }
  @FocusState private var focused: Field?
  @State private var didSetInitialFocus = false
  @State private var pickingFile = false
  @State private var status: String?
  @State private var failure: String?
  @State private var needsReload = false
  @State private var committing = false
  @State private var confirmingDiscard = false
  @State private var operation: Task<Void, Never>?
  let saved: (Playlist) -> Void
  let cancel: () -> Void

  init(
    kind: PlaylistKind, editing: Playlist? = nil, saved: @escaping (Playlist) -> Void,
    cancel: @escaping () -> Void
  ) {
    _draft = State(initialValue: SourceDraft(kind: kind, editing: editing))
    self.saved = saved
    self.cancel = cancel
  }

  var body: some View {
    Form {
      Section(L("add_playlist.section.info")) {
        TextField(
          L("settings.playlist.name"), text: $draft.name,
          prompt: Text(L("add_playlist.name_placeholder")))
          .focused($focused, equals: .name)
          .onSubmit { if draft.file == nil || draft.kind == .xtream { focused = .address } }
          .onAppear {
            guard !didSetInitialFocus else { return }
            didSetInitialFocus = true
            if draft.existing == nil { focused = .name }
          }
        if draft.existing == nil {
          Picker(L("playlist_type.section"), selection: $draft.kind) {
            Text(L("playlist_type.xtream.title")).tag(PlaylistKind.xtream)
            Text(L("playlist_type.m3u.title")).tag(PlaylistKind.m3u)
          }.pickerStyle(.segmented)
        }
      }.disabled(operation != nil || needsReload)
      if draft.kind == .xtream {
        Section(L("add_playlist.section.credentials")) {
          TextField(
            L("add_playlist.server_url"), text: $draft.address, prompt: Text(verbatim: "https://"))
            .focused($focused, equals: .address)
            .onSubmit {
              draft.applyAccountLink()
              focused = .username
            }
            .onChange(of: draft.address) { previous, next in
              if next.count > previous.count + 1 { draft.applyAccountLink() }
            }
          TextField(L("add_playlist.username"), text: $draft.username)
            .focused($focused, equals: .username)
            .onSubmit { focused = .password }
          SecureField(L("add_playlist.password"), text: $draft.password)
            .focused($focused, equals: .password)
            .onSubmit { save() }
        }.disabled(operation != nil || needsReload)
        Section(L("add_playlist.section.content_settings")) {
          Toggle(L("add_playlist.filter_adult"), isOn: $draft.filterAdult)
        }.disabled(operation != nil || needsReload)
      } else {
        Section(L("add_m3u.section.source")) {
          let usesSavedFile = draft.existing?.serverURL == "" && draft.address.isEmpty
          if let file = draft.file {
            LabeledContent(L("playlists.local_file"), value: file.lastPathComponent)
            Button(L("add_m3u.remove_file")) { draft.file = nil }
          } else {
            if usesSavedFile { Label(L("playlists.local_file"), systemImage: "doc") }
            TextField(
              L("settings.m3u.source_url"), text: $draft.address, prompt: Text(verbatim: "https://")
            ).focused($focused, equals: .address)
              .onSubmit { save() }
          }
          Button(
            L(draft.file != nil || usesSavedFile ? "add_m3u.pick_another_file" : "add_m3u.pick_file"),
            systemImage: "folder"
          ) { pickingFile = true }
        }.disabled(operation != nil || needsReload)
      }
      if let failure {
        Section {
          Label(failure, systemImage: "exclamationmark.triangle").textSelection(.enabled)
          if needsReload {
            Button(ML("reload_source")) { Task { await reloadDraft() } }
          }
        }
      }
      Section {
        HStack {
          if let status {
            ProgressView().controlSize(.small)
            Text(status).foregroundStyle(.secondary)
          }
          Spacer()
          Button(L("common.cancel")) {
            if operation == nil && draft.hasUnsavedInput {
              confirmingDiscard = true
            } else {
              operation?.cancel()
              cancel()
            }
          }.disabled(committing).keyboardShortcut(.cancelAction)
            .confirmationDialog(L("onboarding.form.discard"), isPresented: $confirmingDiscard, titleVisibility: .hidden) {
              Button(L("onboarding.form.discard"), role: .destructive, action: cancel)
              Button(L("onboarding.form.keep_editing"), role: .cancel) {}
            }
          Button(L("common.save"), action: save)
            .buttonStyle(.borderedProminent).disabled(!draft.canSave || operation != nil || needsReload)
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(L(draft.existing == nil ? "playlist_type.title" : "common.edit"))
    .fileImporter(
      isPresented: $pickingFile,
      allowedContentTypes: [
        UTType(filenameExtension: "m3u") ?? .plainText,
        UTType(filenameExtension: "m3u8") ?? .plainText, .plainText,
      ]
    ) { result in
      do {
        if try draft.selectFile(result) { failure = nil }
      } catch {
        failure = NetworkErrorText.describe(error)
      }
    }
    .onChange(of: failure) { _, message in
      if let message { AccessibilityNotification.Announcement(message).post() }
    }
    .onDisappear { if !committing { operation?.cancel() } }
  }

  private func reloadDraft() async {
    guard let id = draft.existing?.id else { return }
    do {
      guard let latest = try await database.read({ try Playlist.fetchOne($0, key: id) }) else {
        cancel()
        return
      }
      draft = SourceDraft(kind: latest.kind, editing: latest)
      failure = nil
      needsReload = false
    } catch { failure = NetworkErrorText.describe(error) }
  }

  private func save() {
    guard operation == nil, draft.canSave, !needsReload else { return }
    draft.applyAccountLink()
    failure = nil
    operation = Task {
      defer {
        operation = nil
        status = nil
        committing = false
      }
      do {
        let playlist = try await draft.save(
          in: database, status: { status = $0 }, committing: { committing = true })
        guard !Task.isCancelled else { return }
        saved(playlist)
      } catch {
        guard !Task.isCancelled else { return }
        needsReload = error is PlaylistImportConflict
        let problem = PlaylistFormFailure.describing(error)
        failure = needsReload ? NetworkErrorText.describe(error) : problem.message
        switch problem.field {
        case .credentials: focused = .username
        case .address where draft.file == nil: focused = .address
        default: break
        }
      }
    }
  }
}
