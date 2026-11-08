import GRDB
import SwiftUI
import UniformTypeIdentifiers

struct MacPreferences: View {
  enum Pane: String { case general, source, playback, support }
  @State private var pane = Pane.general
  @EnvironmentObject private var language: LocalizationManager
  @AppStorage("mac.appearance") private var appearance = "system"
  @AppStorage(MacAudioOutput.speakerKey) private var useSpeakers = false
  @AppStorage("player.debugOverlayEnabled") private var showDiagnostics = false
  @AppStorage("player.pipEnabled") private var pip = true
  @AppStorage("player.continuePlayingInBackground") private var background = true
  @AppStorage("player.autoPlayNextEpisode") private var autoNext = true
  @AppStorage("player.speedUpOnLongPress") private var speed = true
  @AppStorage("download.wifi_only") private var wifiOnly = false
  let source: Playlist?
  let edit: (Playlist) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L("dashboard.settings")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
      Picker(L("dashboard.settings"), selection: $pane) {
        Text(ML("general")).tag(Pane.general)
        if source != nil { Text(L("settings.m3u.source")).tag(Pane.source) }
        Text(L("settings.player.title")).tag(Pane.playback)
        Text(L("support.title")).tag(Pane.support)
      }.pickerStyle(.segmented).labelsHidden().fixedSize()
      Form {
        switch pane {
        case .general:
          Section(L("settings.language.section")) {
            Picker(L("settings.language.title"), selection: $language.selectedLanguage) {
              ForEach(LocalizationManager.supportedLanguages, id: \.code) { lang in
                Text(lang.code == "system" ? L("settings.language.system") : lang.nativeName).tag(
                  lang.code)
              }
            }
            Picker(ML("appearance"), selection: $appearance) {
              Text(ML("system")).tag("system")
              Text(ML("light")).tag("light")
              Text(ML("dark")).tag("dark")
            }
          }
          Section(L("download.title")) { Toggle(L("download.wifi_only.title"), isOn: $wifiOnly) }
        case .source:
          if let source { MacSourcePreferences(source: source, edit: edit).id(source.id) }
        case .playback:
          Section(L("settings.player.title")) {
            Toggle(ML("use_builtin_speakers"), isOn: $useSpeakers)
              .accessibilityLabel(ML("use_builtin_speakers"))
            Toggle(L("settings.player.pip.title"), isOn: $pip)
            Toggle(L("settings.player.background.title"), isOn: $background)
              .accessibilityLabel(L("settings.player.background.title"))
            Toggle(L("settings.player.autonext.title"), isOn: $autoNext)
            Toggle(L("settings.player.longpress.title"), isOn: $speed)
            Toggle(L("player.show_debug_overlay"), isOn: $showDiagnostics)
          }
        case .support:
          MacSupportPreferences()
        }
      }.formStyle(.grouped).scrollContentBackground(.hidden)
    }
    .padding(.horizontal, 26).padding(.top, 14)
    .frame(maxWidth: 830, alignment: .leading).frame(
      maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading
    )
    .onChange(of: source?.id) { _, new in if new == nil && pane == .source { pane = .general } }
  }
}

private struct MacSourcePreferences: View {
  @Environment(\.appDatabase) private var database
  @ObservedObject private var hidden = HiddenCategoryStore.shared
  @State private var current: Playlist
  @State private var account: XtreamUserInfo?
  private struct AccountRequest: Equatable {
    let server: String
    let username: String
    let password: String
    let attempt: Int
  }
  @State private var accountAttempt = 0
  @State private var checkingAccount = false
  @State private var accountError: String?
  @State private var refreshTask: Task<Void, Never>?
  @State private var committing = false
  @State private var lastRefresh: Date?
  @State private var refreshFailure: (message: String, file: URL?, adult: Bool?, conflict: Bool)?
  private var busy: Bool { refreshTask != nil }
  @State private var picking = false
  @State private var clearDownloads = false
  @State private var clearHistory = false
  @State private var confirmingAdult: Bool?
  @State private var status: String?
  @State private var error: String?
  @State private var groups: [CatalogGroup] = []
  @State private var categoryType: MediaKind
  @State private var groupSearch = ""
  @State private var statistics: [String: Int] = [:]
  @State private var bytes: Int64 = 0
  @State private var reveal = false
  let source: Playlist
  let edit: (Playlist) -> Void
  init(source: Playlist, edit: @escaping (Playlist) -> Void) {
    self.source = source
    self.edit = edit
    _current = State(initialValue: source)
    _categoryType = State(initialValue: source.kind == .m3u ? .m3u : .live)
  }

  var body: some View {
    Group {
      Section(L("settings.playlist.info.title")) {
        LabeledContent(L("settings.playlist.name"), value: current.name)
        LabeledContent(L("settings.m3u.source"), value: current.displaySource)
        LabeledContent(
          L("settings.playlist.type"),
          value: L(current.kind == .m3u ? "playlist_type.m3u.title" : "playlist_type.xtream.title"))
        if current.kind == .xtream {
          LabeledContent(L("settings.playlist.username"), value: current.username)
          LabeledContent(L("settings.playlist.password")) {
            Text(verbatim: reveal ? current.password : "••••••••").privacySensitive()
            Button(
              L(reveal ? "settings.hide_password" : "settings.show_password"),
              systemImage: reveal ? "eye.slash" : "eye"
            ) { reveal.toggle() }.labelStyle(.iconOnly)
          }
          if let account {
            if let exp = account.expDate.flatMap(TimeInterval.init), exp > 0 {
              LabeledContent(ML("expires")) {
                Text(Date(timeIntervalSince1970: exp), format: .dateTime.year().month().day())
              }
            }
            LabeledContent(
              L("settings.playlist.active_connection"), value: account.activeCons ?? "—")
            LabeledContent(
              L("settings.playlist.max_connection"), value: account.maxConnections ?? "—")
            if let message = account.message, !message.isEmpty {
              Text(verbatim: message).textSelection(.enabled)
            }
          }
          if let accountError {
            Label(accountError, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.secondary).textSelection(.enabled)
          }
          HStack {
            Button(ML("check_account")) { accountAttempt += 1 }.disabled(checkingAccount)
            if checkingAccount { ProgressView().controlSize(.small) }
          }
          .task(id: AccountRequest(server: current.serverURL, username: current.username,
                                   password: current.password, attempt: accountAttempt)) {
            await verifyAccount()
          }
        }
        Button(L("common.edit")) { edit(current) }
      }
      Section(L("settings.content_management.title")) {
        Group {
          if source.kind == .xtream || !source.serverURL.isEmpty {
            Button(
              L(source.kind == .xtream ? "settings.refresh_all" : "settings.m3u.refresh_url"),
              systemImage: "arrow.clockwise"
            ) { refresh(file: nil) }
          }
          if source.kind == .m3u {
            Button(L("settings.m3u.refresh_file"), systemImage: "folder") { picking = true }
          }
          Toggle(
            L("settings.filter_adult.title"),
            isOn: Binding(
              get: { current.filterAdultContent },
              set: { choice in
                if source.kind == .xtream { confirmingAdult = choice } else { setAdult(choice) }
              }))
        }.disabled(busy)
        if busy {
          HStack {
            ProgressView().controlSize(.small)
            Text(status ?? L("common.loading"))
            Spacer()
            if !committing {
              Button(L("common.cancel")) { refreshTask?.cancel() }
            }
          }
        } else if let refreshFailure {
          Label(refreshFailure.message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary).textSelection(.enabled)
          if refreshFailure.conflict {
            Button(ML("reload_source")) { Task { await reloadCurrentSource() } }
          } else {
            Button(L("common.try_again")) { refresh(file: refreshFailure.file, adult: refreshFailure.adult) }
          }
        } else if let lastRefresh {
          LabeledContent(L("epg.last_updated")) {
            Text(lastRefresh, format: .dateTime.hour().minute())
          }
        }
      }
      if source.kind == .xtream {
        XtreamEPGSettingsSection(playlist: $current)
      } else {
        M3UEPGSettingsSection(playlist: $current)
      }
      DisclosureGroup(L("category_picker.hidden_section")) {
        if source.kind == .xtream {
          Picker(L("settings.playlist.type"), selection: $categoryType) {
            ForEach([MediaKind.live, .vod, .series], id: \.self) { Text($0.title).tag($0) }
          }
        }
        TextField(L("category_picker.search_placeholder"), text: $groupSearch)
        ForEach(
          groups.filter {
            groupSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(groupSearch)
          }
        ) { group in
          Toggle(
            group.name,
            isOn: Binding(
              get: {
                !hidden.isHidden(
                  playlistId: source.id, type: categoryType.rawValue, categoryId: group.id)
              },
              set: {
                hidden.setHidden(
                  !$0, playlistId: source.id, type: categoryType.rawValue, categoryId: group.id)
              }))
        }
      }
      Section(L("settings.stats.title")) {
        ForEach(
          source.kind == .xtream ? ["live", "vod", "series"] : ["m3u", "groups"], id: \.self
        ) { key in
          LabeledContent(
            L(statsKey(key)),
            value: (statistics[key] ?? 0).formatted(.number.locale(AppLocale.current)))
        }
        LabeledContent(
          L("settings.stats.history_count"), value: (statistics["history"] ?? 0).formatted())
        LabeledContent(
          L("download.storage_used"),
          value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        Button(L("history.clear.button_entry"), role: .destructive) { clearHistory = true }
        Button(L("download.delete_all"), role: .destructive) { clearDownloads = true }
      }
    }
    .task(id: categoryType) { await readGroups() }
    .task(id: source.id) { await readStats() }
    .onChange(of: source) { _, new in current = new }
    .onDisappear { if !committing { refreshTask?.cancel() } }
    .fileImporter(
      isPresented: $picking,
      allowedContentTypes: [
        UTType(filenameExtension: "m3u") ?? .plainText,
        UTType(filenameExtension: "m3u8") ?? .plainText, .plainText,
      ]
    ) { result in
      if case .success(let file) = result { refresh(file: file) }
    }
    .confirmationDialog(
      L("settings.filter_adult.title"),
      isPresented: Binding(
        get: { confirmingAdult != nil }, set: { if !$0 { confirmingAdult = nil } }),
      presenting: confirmingAdult
    ) { next in
      Button(L("settings.refresh_all")) { setAdult(next) }
      Button(L("common.cancel"), role: .cancel) {}
    } message: { _ in
      Text(L("settings.filter_adult.xtream_desc"))
    }
    .confirmationDialog(L("history.clear.title"), isPresented: $clearHistory) {
      Button(L("common.delete"), role: .destructive) {
        Task {
          do {
            _ = try await database.write {
              try DBWatchHistory.filter(Column("playlistId") == source.id).deleteAll($0)
            }
            await readStats()
          } catch { self.error = NetworkErrorText.describe(error) }
        }
      }
    } message: {
      Text(L("history.clear.message.all"))
    }
    .confirmationDialog(L("download.delete_all"), isPresented: $clearDownloads) {
      Button(L("common.delete"), role: .destructive) {
        Task {
          await DownloadManager.shared.deleteAll(playlistId: source.id)
          await readStats()
        }
      }
    } message: {
      Text(L("download.delete_all.message"))
    }
    .macError($error)
  }
  private func statsKey(_ name: String) -> String {
    switch name {
    case "live": "settings.stats.live_count"
    case "series": "settings.stats.series_count"
    case "vod": "settings.stats.movie_count"
    case "groups": "settings.stats.group_count"
    default: "settings.stats.channel_count"
    }
  }
  private func verifyAccount() async {
    checkingAccount = true
    accountError = nil
    account = nil
    do {
      let info = try await XtreamAPIClient(playlist: current).verify().userInfo
      guard !Task.isCancelled else { return }
      account = info
    } catch {
      guard !Task.isCancelled else { return }
      accountError = NetworkErrorText.describe(error)
    }
    checkingAccount = false
  }
  private func readGroups() async {
    do {
      groups = try await database.read {
        try MacCatalogQuery.groups(in: $0, playlist: source.id, kind: categoryType)
      }
    } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
  }
  private func readStats() async {
    let pid = source.id
    do {
      statistics = try await database.read { db in
        var result: [String: Int] = [:]
        for kind in MediaKind.allCases {
          result[kind.rawValue] =
            try Int.fetchOne(
              db, sql: "SELECT count(*) FROM \(kind.table) WHERE playlistId=?", arguments: [pid])
            ?? 0
        }
        result["groups"] = try MacCatalogQuery.groups(in: db, playlist: pid, kind: .m3u).count
        result["history"] = try DBWatchHistory.filter(Column("playlistId") == pid).fetchCount(db)
        return result
      }
      bytes = await Task.detached(priority: .utility) { DownloadStorage.usedBytes(playlistId: pid) }
        .value
    } catch { if !Task.isCancelled { self.error = NetworkErrorText.describe(error) } }
  }
  private func reloadCurrentSource() async {
    do {
      let id = source.id
      guard let latest = try await database.read({ try Playlist.fetchOne($0, key: id) }) else { return }
      current = latest
      refreshFailure = nil
      await readGroups()
      await readStats()
    } catch { self.error = NetworkErrorText.describe(error) }
  }

  private func refresh(file: URL?, adult: Bool? = nil) {
    guard !busy else { return }
    refreshFailure = nil
    refreshTask = Task {
      defer {
        refreshTask = nil
        committing = false
        status = nil
      }
      do {
        var draft = SourceDraft(kind: source.kind, editing: current)
        draft.file = file
        if let adult { draft.filterAdult = adult }
        current = try await draft.save(
          in: database, forceRefresh: true, status: { status = $0 }, committing: { committing = true })
        await readGroups()
        await readStats()
        await EPGStore.shared.reload(playlist: current)
        lastRefresh = Date()
      } catch {
        guard !Task.isCancelled else { return }
        refreshFailure = (L("misc.refresh_error", NetworkErrorText.describe(error)), file, adult, error is PlaylistImportConflict)
      }
    }
  }
  private func setAdult(_ enable: Bool) {
    if source.kind == .xtream {
      refresh(file: nil, adult: enable)
      return
    }
    Task {
      do {
        if let saved = try await database.updatePlaylist(
          id: source.id, { $0.filterAdultContent = enable })
        {
          current = saved
        }
        await readGroups()
      } catch { self.error = NetworkErrorText.describe(error) }
    }
  }
}
