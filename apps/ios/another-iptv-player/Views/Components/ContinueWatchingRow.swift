import SwiftUI
import GRDB
import GRDBQuery

struct ContinueWatchingRow<Destination: View>: View {
    let playlist: Playlist
    let typeFilter: String?
    @Query<RecentWatchHistoryRequest> private var historyItems: [DBWatchHistory]
    @ViewBuilder let destination: () -> Destination
    var onPlay: (DBWatchHistory) -> Void

    init(
        playlist: Playlist,
        typeFilter: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination,
        onPlay: @escaping (DBWatchHistory) -> Void
    ) {
        self.playlist = playlist
        self.typeFilter = typeFilter
        self.destination = destination
        self.onPlay = onPlay
        // This shelf sits above every other one and draws nothing while it is empty.
        // With the rows in the first body it is part of the first layout; delivered a
        // frame later it would be inserted on top and push the whole page down.
        _historyItems = Query(
            RecentWatchHistoryRequest(playlistId: playlist.id, limit: 10, type: typeFilter, immediate: true),
            in: \.appDatabase
        )
    }

    var body: some View {
        if !historyItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ShelfHeader(L("continue_watching.title")) {
                    destination()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: BrowseMetrics.posterShelfSpacing) {
                        ForEach(historyItems) { item in
                            Button {
                                onPlay(item)
                            } label: {
                                if item.type == "live" {
                                    HistoryCard(item: item, width: 160, height: 90, loadProfile: .shelf)
                                } else {
                                    HistoryCard(item: item, width: 208, height: 117, loadProfile: .shelf, showsPlayGlyph: true)
                                }
                            }
                            .buttonStyle(.cardPress)
                            .accessibilityIdentifier(HistoryCard.accessibilityIdentifier(for: item, in: playlist))
                            .historyItemContextMenu(item, onPlay: onPlay)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 8)
                    // The remaining cards slide together when one is removed (and
                    // reorder when another title becomes the most recent one).
                    .animation(.default, value: historyItems.map(\.id))
                }
                // Lets the context-menu lift and its shadow reach past the shelf's edges.
                .scrollClipDisabled()
                .contentMargins(.horizontal, BrowseMetrics.pageMargin, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            }
            .padding(.vertical, 12)
        }
    }
}

/// A history item as a card: the 16:9 artwork with the watched part, the title and
/// the episode or channel line. Used by the Continue Watching shelf and the full
/// history grid.
struct HistoryCard: View {
    let item: DBWatchHistory
    var width: CGFloat = 160
    var height: CGFloat = 90
    var loadProfile: ImageLoadProfile = .shelf
    /// A play glyph in the corner of the artwork: the Continue Watching shelf plays on tap.
    var showsPlayGlyph: Bool = false

    static let cornerRadius = BrowseMetrics.tileCornerRadius

    /// `card.<type>.<id>`: the type history stores ("live", "vod", "series"), or
    /// "m3u" for every entry of an M3U playlist.
    static func accessibilityIdentifier(for item: DBWatchHistory, in playlist: Playlist) -> String {
        let type = playlist.type == PlaylistKind.m3u.rawValue ? "m3u" : item.type
        return "card.\(type).\(item.streamId)"
    }

    var body: some View {
        let subtitle = item.secondaryTitle
        VStack(alignment: .leading, spacing: 6) {
            CachedImage(
                url: item.imageURL.flatMap { URL(string: $0) },
                width: width,
                height: height,
                cornerRadius: Self.cornerRadius,
                contentMode: .fill,
                iconName: item.type == "live" ? "tv" : "film",
                loadProfile: loadProfile
            )
            .overlay(alignment: .bottom) {
                if item.type != "live" && item.durationMs > 0 {
                    CardProgressBar(fraction: Double(item.lastTimeMs) / Double(item.durationMs))
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
            .overlay(alignment: .center) {
                if showsPlayGlyph {
                    Image(systemName: "play.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.black.opacity(0.45)))
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .posterTitleStyle(width: width)

                if let remaining = remainingText(seriesLine: subtitle) {
                    Text(remaining)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .frame(width: width, alignment: .leading)
                } else if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: width, alignment: .leading)
                }
            }
        }
    }
}

extension HistoryCard {
    /// "12:34 left" on the shelf, for a film or episode that is under way. The episode
    /// line takes its place otherwise.
    fileprivate func remainingText(seriesLine: String?) -> String? {
        guard showsPlayGlyph, item.type != "live", item.durationMs > 0 else { return nil }
        let fraction = Double(item.lastTimeMs) / Double(item.durationMs)
        guard fraction > 0.02, fraction < 0.95 else { return nil }
        let remaining = DetailFormatting.formatMs(item.durationMs - item.lastTimeMs)
        if let subtitle = seriesLine, !subtitle.isEmpty, item.type == "series" {
            return "\(subtitle) · \(L("detail.remaining_format", remaining))"
        }
        return L("detail.remaining_format", remaining)
    }
}

// MARK: - Removing one item

extension DBWatchHistory {
    /// Deletes one history row. The row is also where the title's resume position
    /// and its progress bar come from, so both go with it.
    static func remove(id: String, from database: AppDatabase) async {
        do {
            try await WatchHistoryWriter.remove(id: id, in: database)
        } catch {
            Log.error("WatchHistory", "remove failed: \(error)")
        }
    }
}

extension View {
    /// Long-press menu of a history card, on the shelf and in the full history grid:
    /// play the item, or take it out of the history. The observing `@Query` drops
    /// the card once the row is gone.
    func historyItemContextMenu(
        _ item: DBWatchHistory,
        onPlay: @escaping (DBWatchHistory) -> Void
    ) -> some View {
        cardContextMenuShape(cornerRadius: HistoryCard.cornerRadius)
            .contextMenu {
                PlayMenuButton { onPlay(item) }
                RemoveFromHistoryMenuButton(item: item)
            }
    }
}
