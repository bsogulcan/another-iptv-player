import SwiftUI
import GRDB

struct LiveTVTabView: View {
    let playlist: Playlist
    @EnvironmentObject private var contentStore: PlaylistContentStore
    @State private var playingChannel: PlayableChannel?

    var body: some View {
        CategoryListView(
            categories: contentStore.liveCategories,
            itemsForCategory: { contentStore.liveStreamsByCategoryId[$0.id] ?? [] },
            cardWidth: 360,
            emptyTitle: L("live.empty"),
            emptyIcon: "tv.slash",
            shelfEmptyMessage: L("live.empty"),
            isLoading: !contentStore.streamsLoaded,
            header: {
                ContinueWatchingShelf(playlist: playlist, typeFilter: "live") { item in
                    Task { await resumeFromHistory(item) }
                }
            }
        ) { (item: LiveStreamWithCategory) in
            ChannelCard(
                title: item.stream.name,
                subtitle: nil,
                imageURL: item.stream.streamIcon.flatMap(URL.init(string:))
            ) {
                startPlayback(stream: item.stream)
            }
        }
        .navigationTitle(L("dashboard.live"))
        .fullScreenCover(item: $playingChannel) { channel in
            PlayerView(url: channel.url, title: channel.title,
                       historyTags: channel.tags, resumeTimeMs: nil)
        }
    }

    private func startPlayback(stream: DBLiveStream) {
        guard let url = XtreamURLBuilder.liveStream(playlist: playlist, stream: stream) else { return }
        let tags = WatchHistoryTags(
            playlistId: playlist.id,
            streamId: String(stream.streamId),
            type: "live",
            seriesId: nil,
            title: stream.name,
            secondaryTitle: nil,
            imageURL: stream.streamIcon,
            containerExtension: nil
        )
        playingChannel = PlayableChannel(url: url, title: stream.name, tags: tags)
    }

    @MainActor
    private func resumeFromHistory(_ item: DBWatchHistory) async {
        guard let streamIdInt = Int(item.streamId) else { return }
        do {
            let stream = try await AppDatabase.shared.read { db in
                try DBLiveStream
                    .filter(Column("streamId") == streamIdInt && Column("playlistId") == playlist.id)
                    .fetchOne(db)
            }
            if let stream {
                startPlayback(stream: stream)
            } else {
                // Orphaned history — drop the stale row.
                try? await AppDatabase.shared.write { db in try db.execute(
                    sql: "DELETE FROM watchHistory WHERE id = ?",
                    arguments: [item.id]
                ) }
            }
        } catch {
            print("[LiveTab] resumeFromHistory failed: \(error)")
        }
    }
}

struct PlayableChannel: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    var tags: WatchHistoryTags? = nil
}
