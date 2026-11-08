import Foundation
import GRDB

/// A file is read under its security scope, then its parsed catalogue is stored locally.
struct SourceDraft {
  let existing: Playlist?
  var kind: PlaylistKind
  var name: String
  var address: String
  var username: String
  var password: String
  var filterAdult: Bool
  var file: URL?

  init(kind: PlaylistKind, editing playlist: Playlist? = nil) {
    existing = playlist
    self.kind = playlist?.kind ?? kind
    name = playlist?.name ?? ""
    address = playlist?.serverURL ?? ""
    username = playlist?.username ?? ""
    password = playlist?.password ?? ""
    filterAdult = playlist?.filterAdultContent ?? false
  }

  mutating func selectFile(_ result: Result<URL, Error>) throws -> Bool {
    do {
      file = try result.get()
      return true
    } catch where isFileImportCancellation(error) {
      return false
    }
  }

  mutating func applyAccountLink() {
    guard kind == .xtream, let login = XtreamLinkDetector.detect(urlString: address) else { return }
    address = login.serverURL
    username = login.username
    password = login.password
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      name = URLComponents(string: login.serverURL)?.host ?? ""
    }
  }

  var hasUnsavedInput: Bool {
    func changed(_ current: String, _ stored: String?) -> Bool {
      current.trimmingCharacters(in: .whitespacesAndNewlines) != (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if changed(name, existing?.name) || changed(address, existing?.serverURL) { return true }
    if kind == .m3u { return file != nil }
    return changed(username, existing?.username) || password != (existing?.password ?? "") ||
      filterAdult != (existing?.filterAdultContent ?? false)
  }

  var canSave: Bool {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    switch kind {
    case .xtream:
      if XtreamLinkDetector.detect(urlString: address) != nil { return true }
      return XtreamLinkDetector.normalizedServerURL(address) != nil
        && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    case .m3u:
      if file != nil || (existing?.serverURL == "" && address.isEmpty) { return true }
      guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return false
      }
      return ["http", "https"].contains(url.scheme?.lowercased()) && url.host != nil
    }
  }

  func save(
    in database: AppDatabase, session: URLSession = PanelURLSession.shared,
    forceRefresh: Bool = false,
    status: @escaping @MainActor (String) -> Void, committing: @escaping @MainActor () -> Void
  ) async throws -> Playlist {
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = address.trimmingCharacters(in: .whitespacesAndNewlines)
    var source = existing ?? Playlist(name: title, serverURL: url, type: kind)
    source.name = title
    source.serverURL =
      kind == .xtream
      ? (XtreamLinkDetector.normalizedServerURL(url) ?? url) : (file == nil ? url : "")
    source.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
    source.password = password
    source.filterAdultContent = filterAdult
    if !forceRefresh, let existing, file == nil, source.serverURL == existing.serverURL,
      source.username == existing.username, source.password == existing.password,
      source.filterAdultContent == existing.filterAdultContent
    {
      let proposed = source
      return try await database.write { db in
        let saved = try proposed.mergingImportEdit(from: existing, in: db)
        try saved.update(db)
        return saved
      }
    }

    if kind == .xtream {
      let client = XtreamAPIClient(playlist: source, urlSession: session)
      status(L("add_playlist.verifying"))
      source.serverTimezone = try await client.verify().serverInfo?.timezone
      return try await importPanel(
        source, client: client, database: database, status: status, committing: committing)
    }

    if existing == nil, file == nil, let login = XtreamLinkDetector.detect(urlString: url) {
      var panel = Playlist(
        id: source.id, name: title, serverURL: login.serverURL, username: login.username,
        password: login.password)
      let client = XtreamAPIClient(playlist: panel, urlSession: session)
      status(L("add_m3u.xtream_detected"))
      if let auth = try? await client.verify() {
        panel.serverTimezone = auth.serverInfo?.timezone
        return try await importPanel(
          panel, client: client, database: database, status: status, committing: committing)
      }
      try Task.checkCancellation()
    }

    let service = M3UService(urlSession: session)
    status(L(file == nil ? "add_m3u.downloading" : "add_m3u.preparing"))
    let content: String
    if let file {
      content = try await service.readLocalAsync(url: file)
    } else {
      content = try await service.fetchRemote(urlString: url)
    }
    status(L("add_m3u.parsing"))
    let parsed = try await M3UParser.parseAsync(content)
    try Task.checkCancellation()
    committing()
    status(L("add_m3u.saving_db"))
    return try await M3UImporter.replace(
      playlist: source, channels: parsed.channels, epgURL: parsed.epgURL,
      clearServerURL: file != nil, editing: existing, in: database)
  }

  private func importPanel(
    _ source: Playlist, client: XtreamAPIClient, database: AppDatabase,
    status: @escaping @MainActor (String) -> Void, committing: @escaping @MainActor () -> Void
  ) async throws -> Playlist {
    return try await XtreamImporter.syncAndSave(
      playlist: source, client: client, database: database, editing: existing,
      progress: status, onPhase: { if $0 == .saving { committing() } })
  }
}
