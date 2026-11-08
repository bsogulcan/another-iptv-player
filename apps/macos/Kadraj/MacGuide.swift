import GRDB
import SwiftUI

struct GuideDayTimeline: TimelineSchedule {
  let day: DateInterval

  func entries(from startDate: Date, mode: Mode) -> some Sequence<Date> {
    sequence(first: startDate) { previous in
      if previous < day.start { return day.start }
      guard previous < day.end else { return nil }
      return min(day.end, previous.addingTimeInterval(60))
    }
  }
}

struct MacGuide: View {
  @Environment(\.appDatabase) private var database
  @EnvironmentObject private var playback: DesktopPlayback
  @ObservedObject private var guide = EPGStore.shared
  @StateObject private var model: EPGGuideViewModel
  let source: Playlist
  let settings: () -> Void
  @State private var selected: ProgrammeSelection?
  @State private var channel: EPGGuideRow?
  @State private var channelSearch = ""
  @State private var task: Task<Void, Never>?
  @State private var failure: String?
  @State private var positionRequest = UUID()
  private let metrics = EPGGuideMetrics.guide(regularWidth: true)

  private struct ProgrammeSelection: Identifiable {
    let row: EPGGuideRow, programme: EPGProgramme
    var id: String { row.id + programme.id }
  }
  init(source: Playlist, settings: @escaping () -> Void) {
    self.source = source
    self.settings = settings
    _model = StateObject(
      wrappedValue: EPGGuideViewModel(
        source: source.kind == .xtream ? .xtream(source) : .m3u(source)))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if case .failed(let message) = guide.refreshState[source.id] {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.callout).foregroundStyle(.secondary)
          .padding(.horizontal, 22).padding(.vertical, 6)
      }
      if let selection = selected {
        programmePage(selection)
      } else if let channel {
        MacChannelSchedule(
          source: source, channel: channel, query: channelSearch, lastRefresh: guide.lastSuccess[source.id],
          back: { self.channel = nil },
          choose: { selected = ProgrammeSelection(row: channel, programme: $0) },
          live: { startLive(channel) })
          .id(channel.id)
          .searchable(text: $channelSearch, placement: .toolbar, prompt: Text(L("search.placeholder")))
      } else {
        guideContent
          .searchable(text: $model.searchQuery, placement: .toolbar, prompt: Text(L("search.placeholder")))
      }
    }
    .toolbar {
      ToolbarItem {
        Menu {
          Button(L("epg.categories.expand_all")) { model.setAllCollapsed(false) }
          Button(L("epg.categories.collapse_all")) { model.setAllCollapsed(true) }
        } label: {
          Label(L("category_picker.title"), systemImage: "list.bullet.indent")
        }
      }
      ToolbarItem {
        Button(L("epg.refresh"), systemImage: "arrow.clockwise") {
          Task {
            await guide.forceRefresh(playlist: source)
            await model.reloadAfterGuideRefresh()
          }
        }
        .disabled(guide.refreshState[source.id]?.isRefreshing == true)
      }
    }
    .task(id: source.id) {
      guide.setActivePlaylist(source)
      if source.kind == .m3u {
        await M3UContentStore.shared.loadPlaylist(source)
      } else {
        await PlaylistContentStore.shared.loadPlaylist(source)
      }
      guard !Task.isCancelled else { return }
      await guide.reload(playlist: source)
      await model.load()
    }
    .onChange(of: guide.lastSuccess[source.id]) { _, _ in
      Task { await model.reloadAfterGuideRefresh() }
    }
    .onDisappear {
      task?.cancel()
      model.cancelLoading()
    }
    .macError($failure)
  }

  private var guideContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(L("epg.guide.title")).font(.largeTitle.bold())
        Spacer()
        Picker(
          L("epg.guide.title"),
          selection: Binding(
            get: { model.selectedDay }, set: { day in Task { await model.selectDay(day) } })
        ) {
          ForEach(model.availableDays, id: \.self) { day in
            Text(day, format: .dateTime.weekday().day().month(.abbreviated)).tag(day)
          }
        }.labelsHidden().fixedSize()
      }.padding(.horizontal, 26).padding(.vertical, 14)
      switch model.state {
      case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      case .ready: grid
      case .notConfigured:
        ContentUnavailableView {
          Label(L("epg.not_configured.title"), systemImage: "calendar")
        } description: {
          Text(L("epg.not_configured.m3u_message"))
        } actions: {
          Button(L("dashboard.settings"), action: settings)
        }
      case .empty, .allHidden, .catalogFailed:
        ContentUnavailableView {
          Label(
            L(model.state == .allHidden ? "m3u.empty.all_hidden.title" : "epg.empty.title"),
            systemImage: "calendar")
        } description: {
          Text(L(model.state == .allHidden ? "guide.all_hidden.message" : "epg.empty.message"))
        } actions: {
          Button(L("common.try_again")) {
            Task {
              await model.retryCatalog()
              await guide.forceRefresh(playlist: source)
              await model.reloadAfterGuideRefresh()
            }
          }
        }
      }
    }
  }

  private var dayDuration: TimeInterval {
    Calendar.current.dateInterval(of: .day, for: model.dayStart)?.duration ?? 86400
  }
  private var grid: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let error = model.programmeError {
        Label(error, systemImage: "exclamationmark.triangle").padding(.leading, 26)
      }
      HStack {
        Button(L("epg.jump_to_now")) {
          Task {
            await model.selectDay(Date())
            positionRequest = UUID()
          }
        }
        Spacer()
        if let date = guide.lastSuccess[source.id] {
          Text(date, style: .relative).foregroundStyle(.secondary).font(.caption)
        }
      }.padding(.horizontal, 26)
      if model.hasNoSearchResults {
        ContentUnavailableView(L("favorites.empty.no_result.title"), systemImage: "magnifyingglass")
      } else {
        let hour =
          Calendar.current.isDateInToday(model.selectedDay)
          ? max(0, Int(Date().timeIntervalSince(model.dayStart) / 3600) - 1) : 0
        let duration = dayDuration
        let start = model.dayStart
        let dayHours = stride(from: 0, to: duration, by: 3600).map { start.addingTimeInterval($0) }
        MacGuideTable(
          layoutVersion: model.publishedLayoutVersion, headerHours: dayHours, items: model.items, channelWidth: metrics.channelColumnWidth,
          timelineWidth: CGFloat(duration / 3600) * metrics.hourWidth,
          horizontalPosition: CGFloat(hour) * metrics.hourWidth, positionRequest: positionRequest,
          header: AnyView(
            HStack(spacing: 0) {
              ForEach(dayHours, id: \.self) { time in
                Text(time, format: .dateTime.hour().minute()).font(.caption.monospacedDigit())
                  .frame(width: metrics.hourWidth * min(1, (duration - time.timeIntervalSince(start)) / 3600), alignment: .leading)
              }
            }.frame(height: 28).background(.bar)),
          channel: { AnyView(channelCell($0)) },
          timeline: { item in
            switch item {
            case .header: AnyView(Color.clear)
            case .channel(let row): AnyView(timelineRow(row))
            }
          }
        )
        .onChange(of: model.selectedDay) { _, _ in positionRequest = UUID() }
      }
    }
  }
  @ViewBuilder private func channelCell(_ item: EPGGuideItem) -> some View {
    switch item {
    case .header(let header):
      Button {
        model.toggleCategory(header.id)
      } label: {
        HStack(spacing: 5) {
          Label(header.title, systemImage: header.collapsed ? "chevron.forward" : "chevron.down")
            .font(.headline).lineLimit(1)
          Spacer(minLength: 2)
          Text(header.channelCount, format: .number).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.contentShape(Rectangle())
      }.buttonStyle(.plain).padding(.horizontal, 10)
        .accessibilityLabel(header.title)
        .accessibilityValue(L(header.collapsed ? "epg.categories.collapsed_a11y" : "epg.categories.expanded_a11y"))
        .accessibilityAddTraits(.isHeader)
    case .channel(let row):
      Button {
        channelSearch = ""
        channel = row
      } label: {
        Text(verbatim: row.displayName).font(.headline).lineLimit(2)
          .padding(.horizontal, 10).frame(
            maxWidth: .infinity, maxHeight: .infinity, alignment: .leading
          )
          .contentShape(Rectangle())
      }.buttonStyle(.plain)
    }
  }
  @ViewBuilder private func timelineRow(_ row: EPGGuideRow) -> some View {
    let start = model.dayStart
    let calendar = Calendar.current
    if let day = calendar.dateInterval(of: .day, for: start), day.end > .now {
      TimelineView(GuideDayTimeline(day: day)) { tick in
        let onSelectedDay = calendar.isDate(tick.date, inSameDayAs: start)
        timelineRow(row, now: onSelectedDay ? tick.date : nil)
      }
    } else {
      timelineRow(row, now: nil)
    }
  }

  private func timelineRow(_ row: EPGGuideRow, now: Date?) -> some View {
    ZStack(alignment: .leading) {
      ForEach(model.layout(for: row.channelKey).cells) { cell in
        if let programme = cell.programme {
          let onAir = now.map { programme.isCurrent(at: $0) } == true
          Button {
            selected = ProgrammeSelection(row: row, programme: programme)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: programme.title).font(.headline).lineLimit(1)
              Text(programme.start, format: .dateTime.hour().minute()).font(.caption)
                .foregroundStyle(.secondary)
            }.padding(.horizontal, 7).frame(
              width: max(1, cell.width - 2), height: 47, alignment: .leading
            )
            .background(
              onAir
                ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.09),
              in: .rect(cornerRadius: 5))
          }.buttonStyle(.plain).offset(x: cell.x).help(programme.title).accessibilityLabel(programme.title)
            .accessibilityValue([row.displayName, EPGTimeFormat.range(programme.start, programme.stop),
                                 onAir ? L("epg.now") : nil]
              .compactMap { $0 }.joined(separator: ", "))
        }
      }
    }.frame(width: CGFloat(dayDuration / 3600) * metrics.hourWidth, height: 50, alignment: .leading)
      .overlay(alignment: .leading) {
        if let now {
          Rectangle().fill(Color.accentColor.opacity(0.65)).frame(width: 1)
            .offset(x: CGFloat(now.timeIntervalSince(model.dayStart) / 3600) * metrics.hourWidth)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
  }
  private func programmePage(_ selection: ProgrammeSelection) -> some View {
    MacProgrammeDetail(
      source: source, row: selection.row, initial: selection.programme,
      backTitle: channel?.displayName ?? L("epg.guide.title"), back: { selected = nil },
      live: { startLive(selection.row) })
      .id(selection.id)
  }
  private func startLive(_ row: EPGGuideRow) {
    task?.cancel()
    task = Task {
      do {
        let item = CatalogItem(
          playlistId: source.id, kind: row.liveStream == nil ? "m3u" : "live",
          streamKey: row.liveStream.map { String($0.streamId) } ?? row.id, title: row.displayName,
          category: row.categoryTitle,
          artwork: row.iconURL?.absoluteString, rating: nil, favorite: false, sortIndex: 0)
        let media = try await MediaSelection.resolve(item, in: source, database: database)
        try Task.checkCancellation()
        playback.start(media)
      } catch { if !Task.isCancelled { failure = NetworkErrorText.describe(error) } }
    }
  }

}

private struct MacProgrammeDetail: View {
  let source: Playlist, row: EPGGuideRow, initial: EPGProgramme
  @Environment(\.appDatabase) private var database
  let backTitle: String
  let back: () -> Void, live: () -> Void
  @EnvironmentObject private var playback: DesktopPlayback
  @State private var resolving: Task<Void, Never>?
  @State private var catchupError: String?
  @State private var detail: EPGProgramme?
  @State private var actionTime = Date()
  var body: some View {
    let programme = detail ?? initial
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Button(backTitle, systemImage: "chevron.backward", action: { cancelCatchup(); back() }).buttonStyle(.link)
        HStack(spacing: 10) {
          if let url = row.iconURL {
            CachedImage(url: url, width: 44, height: 44, cornerRadius: 8, contentMode: .fit,
              iconName: "tv", loadProfile: .standard)
              .accessibilityHidden(true)
          }
          Text(verbatim: row.displayName).foregroundStyle(.secondary)
        }
        Text(verbatim: programme.title).font(.largeTitle.bold())
        HStack {
          Text(verbatim: EPGTimeFormat.day(programme.start, wide: false) + " · "
            + EPGTimeFormat.range(programme.start, programme.stop) + " · "
            + EPGTimeFormat.duration(programme.duration))
          if programme.isCurrent(at: actionTime) {
            Text(L("epg.detail.live_badge")).font(.caption.bold())
              .padding(.horizontal, 7).padding(.vertical, 3)
              .background(Color.accentColor.opacity(0.2), in: Capsule())
          }
        }
        if programme.isCurrent(at: actionTime) {
          TimelineView(.periodic(from: actionTime, by: 60)) { tick in
            if let fraction = programme.progress(at: tick.date) {
              ProgressView(value: fraction).accessibilityLabel(programme.title)
            }
          }
        }
        HStack {
          Button(L("epg.detail.play_channel"), systemImage: "play.fill", action: { cancelCatchup(); live() }).buttonStyle(
            .borderedProminent)
          if let stream = row.liveStream, stream.tvArchive == 1 {
            Group {
              if programme.isCurrent(at: actionTime) || CatchupAvailability.isPlayable(
                tvArchive: stream.tvArchive, tvArchiveDurationDays: stream.tvArchiveDuration,
                programmeStart: programme.start, now: actionTime
              ) {
                Button(
                  L(catchupError != nil ? "common.try_again" :
                    programme.isCurrent(at: actionTime) ? "epg.detail.watch_from_start" : "epg.detail.play_catchup"),
                  systemImage: "clock.arrow.circlepath"
                ) { playArchive(stream: stream, programme: programme) }.disabled(resolving != nil)
              }
            }
            if resolving != nil { ProgressView().controlSize(.small) }
          }
        }
        if let catchupError {
          Label(catchupError, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary).textSelection(.enabled)
        }
        if let category = programme.category { Text(verbatim: category).foregroundStyle(.secondary) }
        if let subtitle = programme.subtitle { Text(verbatim: subtitle).font(.headline) }
        if let desc = programme.desc { Text(verbatim: desc).textSelection(.enabled) }
      }.padding(26).frame(maxWidth: 800, alignment: .leading).frame(
        maxWidth: .infinity, alignment: .leading)
    }.task(id: [programme.start, programme.stop]) {
      actionTime = Date()
      var boundaries = [programme.start, programme.stop]
      if let stream = row.liveStream, stream.tvArchive == 1, stream.tvArchiveDuration > 0 {
        boundaries.append(programme.start.addingTimeInterval(Double(stream.tvArchiveDuration) * 86400 + 0.001))
      }
      for date in boundaries.sorted() where date > actionTime {
        do { try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow))) } catch { return }
        actionTime = Date()
      }
    }.onDisappear { cancelCatchup() }.task(id: initial.id) {
      let playlistID = source.id, key = row.channelKey
      let start = Int64(initial.start.timeIntervalSince1970)
      let observation = ValueObservation.tracking { db in
        try DBEPGProgramme.filter(Column("playlistId") == playlistID && Column("channelKey") == key
          && Column("startTs") == start).fetchOne(db).map(EPGProgramme.init(from:))
      }
      do {
        for try await updated in observation.removeDuplicates().values(in: database.reader) {
          try Task.checkCancellation()
          if let updated { detail = updated }
        }
      } catch {
        guard !Task.isCancelled else { return }
        Log.error("EPG", NetworkErrorText.describe(error))
      }
    }
  }
  private func cancelCatchup() {
    resolving?.cancel()
    resolving = nil
  }

  private func playArchive(stream: DBLiveStream, programme: EPGProgramme) {
    guard resolving == nil else { return }
    catchupError = nil
    resolving = Task {
      do {
        let zone = await PanelTimeZoneResolver.resolve(playlist: source)
        try Task.checkCancellation()
        let archive = try await CatchupURLResolver.resolve(
          playlist: source, streamId: stream.streamId, startUTC: programme.start,
          durationMinutes: CatchupAvailability.requestDurationMinutes(
            programmeStart: programme.start, programmeStop: programme.stop), panelTimeZone: zone)
        try Task.checkCancellation()
        playback.start(MediaSelection(url: archive.url, playlistId: source.id,
          streamId: String(stream.streamId), type: "catchup", title: programme.title,
          secondaryTitle: "\(stream.name) · \(EPGTimeFormat.range(programme.start, programme.stop))",
          artwork: stream.streamIcon, storesHistory: false))
      } catch {
        guard !Task.isCancelled else { return }
        catchupError = NetworkErrorText.describe(error)
      }
      resolving = nil
    }
  }

}

private struct MacChannelSchedule: View {
  @Environment(\.appDatabase) private var database
  @Environment(\.locale) private var locale
  let source: Playlist, channel: EPGGuideRow
  let query: String
  let lastRefresh: Date?
  let back: () -> Void, choose: (EPGProgramme) -> Void, live: () -> Void
  @State private var programmes: [EPGProgramme] = []
  @State private var error: String?
  @State private var loading = true
  @State private var now = Date()
  @State private var scrolledToCurrent = false
  nonisolated private struct Schedule: Sendable {
    var days: [Date: [EPGProgramme]] = [:]
    var dates: [Date] = []
    var current: EPGProgramme?
  }
  @State private var schedule = Schedule()
  @State private var revision = 0
  @State private var displayedFilter: Filter?
  private struct Filter: Equatable {
    let revision: Int
    let query: String
    let calendar: Calendar
    let now: Date
  }

  @concurrent private static func group(_ programmes: [EPGProgramme], query: String, calendar: Calendar, now: Date) async throws -> Schedule {
    var schedule = Schedule()
    for programme in programmes {
      try Task.checkCancellation()
      if query.isEmpty || programme.title.localizedStandardContains(query) {
        schedule.days[calendar.startOfDay(for: programme.start), default: []].append(programme)
        if schedule.current == nil, programme.isCurrent(at: now) { schedule.current = programme }
      }
    }
    schedule.dates = schedule.days.keys.sorted()
    return schedule
  }

  private func programmeRow(_ programme: EPGProgramme, at now: Date) -> some View {
    let current = programme.isCurrent(at: now)
    let past = programme.isPast(at: now)
    let archiveAvailable = past && channel.liveStream.map {
      CatchupAvailability.isPlayable(tvArchive: $0.tvArchive, tvArchiveDurationDays: $0.tvArchiveDuration,
                                     programmeStart: programme.start, now: now)
    } == true
    let synopsis = programme.desc?.trimmingCharacters(in: .whitespacesAndNewlines)
    let time = programme.start.formatted(.dateTime.weekday().hour().minute().locale(locale))
    return Button { choose(programme) } label: {
      HStack {
        Text(programme.start, format: .dateTime.hour().minute()).monospacedDigit()
          .foregroundStyle(.secondary).frame(width: 75, alignment: .leading)
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(verbatim: programme.title)
            if current {
              Text(L("epg.now")).font(.caption.bold()).padding(.horizontal, 5)
                .background(Color.accentColor.opacity(0.2), in: Capsule())
            }
          }
          if let synopsis, !synopsis.isEmpty {
            Text(verbatim: synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          if current, let fraction = programme.progress(at: now) {
            ProgressView(value: fraction).accessibilityHidden(true)
          }
        }
        Spacer()
        if archiveAvailable {
          Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.accentColor)
        }
        Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
      }.contentShape(Rectangle())
    }.buttonStyle(.plain)
      .accessibilityLabel(programme.title)
      .accessibilityValue([time, current ? L("epg.now") : nil, archiveAvailable ? L("epg.catchup.available") : nil, synopsis]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
  }

  var body: some View {
    let filter = Filter(revision: revision, query: query.trimmingCharacters(in: .whitespacesAndNewlines), calendar: .current, now: now)
    VStack(alignment: .leading, spacing: 12) {
      Button(L("epg.guide.title"), systemImage: "chevron.backward", action: back).buttonStyle(.link)
        .accessibilityIdentifier("guide.schedule.back")
      HStack {
        Text(verbatim: channel.displayName).font(.largeTitle.bold())
        Spacer()
        Button(L("epg.detail.play_channel"), systemImage: "play.fill", action: live)
      }
      if loading || (!programmes.isEmpty && schedule.days.isEmpty && displayedFilter != filter) {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if programmes.isEmpty {
        ContentUnavailableView(L("epg.no_data.channel"), systemImage: "calendar")
      } else if schedule.days.isEmpty {
        ContentUnavailableView.search(text: query)
      } else {
        let current = schedule.current
        ScrollViewReader { proxy in
          List {
            ForEach(schedule.dates, id: \.self) { day in
              Section(EPGTimeFormat.dayLabel(day, wide: true)) {
                ForEach(schedule.days[day] ?? []) { programme in
                  programmeRow(programme, at: now).id(programme.id)
                }
              }
            }
          }
          .onChange(of: current?.id, initial: true) { _, id in
            guard !scrolledToCurrent, query.isEmpty, let id else { return }
            scrolledToCurrent = true
            proxy.scrollTo(id, anchor: .center)
          }
          .toolbar {
            ToolbarItem {
              Button(L("epg.jump_to_now"), systemImage: "clock") {
                if let current { proxy.scrollTo(current.id, anchor: .center) }
              }.disabled(current == nil)
            }
          }
        }
      }
    }.padding(22).task(id: filter) {
      do {
        if !filter.query.isEmpty { try await Task.sleep(for: .milliseconds(120)) }
        let grouped = try await Self.group(programmes, query: filter.query, calendar: filter.calendar, now: filter.now)
        try Task.checkCancellation()
        schedule = grouped
        displayedFilter = filter
      } catch { }
    }.task {
      while !Task.isCancelled {
        now = Date()
        do { try await Task.sleep(for: .seconds(60)) } catch { return }
      }
    }.task(id: lastRefresh) {
      loading = programmes.isEmpty
      error = nil
      do {
        var archive: [EPGProgramme] = []
        if let stream = channel.liveStream {
          await EPGStore.shared.ensureShortEPG(playlist: source, stream: stream)
          try Task.checkCancellation()
          archive = try await EPGStore.shared.archiveProgrammes(playlist: source, stream: stream)
        }
        let reference = Date()
        let start = reference.addingTimeInterval(-2 * 86400)
        let end = reference.addingTimeInterval(8 * 86400)
        let channelKey = channel.channelKey
        let playlistID = source.id
        let archiveKey = archive.first?.channelKey
        let earliestArchive = archive.map(\.start).min() ?? reference
        let observation = ValueObservation.tracking { db in
          let key = Column("channelKey"), begins = Column("startTs"), ends = Column("stopTs")
          var interval = key == channelKey && ends > Int64(start.timeIntervalSince1970)
            && begins < Int64(end.timeIntervalSince1970)
          if let archiveKey {
            interval = interval || (key == archiveKey && begins >= Int64(earliestArchive.timeIntervalSince1970)
              && begins < Int64(reference.timeIntervalSince1970))
          }
          return try DBEPGProgramme.filter(Column("playlistId") == playlistID && interval)
            .order(begins, key).fetchAll(db).map(EPGProgramme.init(from:))
        }
        for try await rows in observation.removeDuplicates().values(in: database.reader) {
          try Task.checkCancellation()
          programmes = rows
          revision += 1
          loading = false
        }
      } catch {
        guard !Task.isCancelled else { return }
        self.error = NetworkErrorText.describe(error)
      }
      loading = false
    }.macError($error)
  }
}
