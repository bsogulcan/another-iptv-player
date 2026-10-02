import SwiftUI
import GRDBQuery

/// Day-grouped programme schedule for one channel. Live-updates via GRDBQuery.
struct ChannelEPGDetailView: View {
    let playlist: Playlist
    let channelKey: String
    let displayName: String
    let iconURL: URL?
    let liveStream: DBLiveStream?
    /// Starts the channel when it is not an Xtream stream (an M3U channel); handed
    /// on to the programme sheet. Nil when there is nothing to play.
    let onPlayChannel: (() -> Void)?

    @Query<ChannelEPGRequest> private var rows: [DBEPGProgramme]
    @State private var selected: EPGProgramme?
    @State private var hasScrolledToNow = false
    @Environment(\.epgSnapshot) private var epgSnapshot

    init(playlist: Playlist, channelKey: String, displayName: String, iconURL: URL?, liveStream: DBLiveStream?,
         onPlayChannel: (() -> Void)? = nil) {
        self.playlist = playlist
        self.channelKey = channelKey
        self.displayName = displayName
        self.iconURL = iconURL
        self.liveStream = liveStream
        self.onPlayChannel = onPlayChannel
        let now = Date()
        let from = Int64(now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970)
        let to = Int64(now.addingTimeInterval(8 * 86_400).timeIntervalSince1970)
        _rows = Query(ChannelEPGRequest(playlistId: playlist.id, channelKey: channelKey, fromTs: from, toTs: to), in: \.appDatabase)
    }

    private var programmes: [EPGProgramme] { rows.map(EPGProgramme.init(from:)) }

    private var days: [(day: Date, items: [EPGProgramme])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: programmes) { cal.startOfDay(for: $0.start) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.start < $1.start }) }
    }

    var body: some View {
        Group {
            if programmes.isEmpty {
                CatalogEmptyView(.message(title: L("epg.no_data.channel"),
                                          systemImage: "calendar.badge.exclamationmark", description: nil))
            } else {
                scheduleList
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { programme in
            EPGProgrammeDetailSheet(playlist: playlist, programme: programme,
                                    channelName: displayName, channelIcon: iconURL, liveStream: liveStream,
                                    onPlayChannel: onPlayChannel)
                .presentationDetents([.medium, .large])
        }
    }

    private var scheduleList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(days, id: \.day) { group in
                    Section(header: Text(dayLabel(group.day))) {
                        ForEach(group.items) { programme in
                            // A button, so the cell highlights while pressed and
                            // VoiceOver announces it as one.
                            Button {
                                selected = programme
                            } label: {
                                row(programme)
                            }
                            .id(rowID(programme))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .onAppear {
                scrollToNowIfNeeded(proxy)
            }
            .onChange(of: rows) { _, _ in
                scrollToNowIfNeeded(proxy)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let current = programmes.first(where: { $0.isCurrent(at: Date()) }) {
                            withAnimation { proxy.scrollTo(rowID(current), anchor: .center) }
                        }
                    } label: {
                        // A plain clock: the arrowed one marks catch-up in the rows.
                        Label(L("epg.jump_to_now"), systemImage: "clock")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ programme: EPGProgramme) -> some View {
        let now = Date()
        let isCurrent = programme.isCurrent(at: now)
        let isPast = programme.isPast(at: now)
        HStack(alignment: .top, spacing: 12) {
            Text(EPGTimeFormat.time(programme.start))
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Inside a list button unstyled text takes the accent colour.
                    Text(programme.title).font(.body).lineLimit(1)
                        .foregroundStyle(.primary)
                    if isCurrent {
                        Text(L("epg.now")).font(.caption2.bold())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                    }
                }
                if let desc = programme.desc, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                if isCurrent, let fraction = programme.progress(at: now) {
                    ProgressView(value: fraction).tint(.accentColor)
                }
            }
            Spacer(minLength: 0)
            if isPast, isCatchupPlayable(programme, now: now) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                    .accessibilityLabel(L("epg.catchup.available"))
            }
        }
        .overlay(alignment: .leading) {
            if isCurrent {
                Rectangle().fill(Color.accentColor).frame(width: 3).padding(.vertical, 2)
                    .padding(.leading, -8)
            }
        }
        .opacity(isPast && !isCatchupPlayable(programme, now: now) ? 0.55 : 1)
    }

    private func isCatchupPlayable(_ programme: EPGProgramme, now: Date) -> Bool {
        guard let s = liveStream, s.tvArchive == 1 else { return false }
        return CatchupAvailability.isPlayable(tvArchive: s.tvArchive, tvArchiveDurationDays: s.tvArchiveDuration,
                                              programmeStart: programme.start, now: now)
    }

    private func rowID(_ programme: EPGProgramme) -> String { programme.id }

    /// Deferred a tick so the target row (often ~2 days into the list) has been laid out before scrolling.
    private func scrollToNowIfNeeded(_ proxy: ScrollViewProxy) {
        guard !hasScrolledToNow, let current = programmes.first(where: { $0.isCurrent(at: Date()) }) else { return }
        hasScrolledToNow = true
        DispatchQueue.main.async {
            proxy.scrollTo(rowID(current), anchor: .center)
        }
    }

    private func dayLabel(_ day: Date) -> String {
        EPGTimeFormat.dayLabel(day, wide: true)
    }
}

/// NavigationStack-wrapped variant for sheet presentation (from cards / player).
struct ChannelEPGSheet: View {
    let playlist: Playlist
    let channelKey: String
    let displayName: String
    let iconURL: URL?
    let liveStream: DBLiveStream?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChannelEPGDetailView(playlist: playlist, channelKey: channelKey,
                                 displayName: displayName, iconURL: iconURL, liveStream: liveStream)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("common.close")) { dismiss() }
                    }
                }
        }
    }
}
