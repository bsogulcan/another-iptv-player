import SwiftUI
import NukeUI
import GRDBQuery

/// "Continue Watching" shelf — a horizontal row of the most recently watched
/// items for a playlist, optionally filtered by type (live / vod / series).
///
/// Renders nothing if the query returns no rows, so each dashboard tab can
/// drop it in unconditionally at the top of its scroll view.
struct ContinueWatchingShelf: View {
    let playlist: Playlist
    let typeFilter: String?
    let onPlay: (DBWatchHistory) -> Void

    @Query<RecentWatchHistoryRequest> private var historyItems: [DBWatchHistory]

    private let cardWidth: CGFloat = 360

    init(playlist: Playlist, typeFilter: String?, onPlay: @escaping (DBWatchHistory) -> Void) {
        self.playlist = playlist
        self.typeFilter = typeFilter
        self.onPlay = onPlay
        _historyItems = Query(
            RecentWatchHistoryRequest(playlistId: playlist.id, limit: 15, type: typeFilter),
            in: \.appDatabase
        )
    }

    var body: some View {
        if !historyItems.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("continue_watching.title"))
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 60)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(historyItems) { item in
                            HistoryCard(item: item, width: cardWidth) {
                                onPlay(item)
                            }
                            .frame(width: cardWidth)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 16)
                }
            }
            .padding(.vertical, 12)
            .focusSection()
        }
    }
}

/// Landscape continue-watching card. Mirrors `ChannelCard`'s
/// poster-outside-title structure: only the thumbnail gets the tvOS card
/// focus treatment, so the title below never clips.
private struct HistoryCard: View {
    let item: DBWatchHistory
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                ZStack(alignment: .bottom) {
                    thumbnail
                        .frame(width: width, height: thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if item.type != "live" && item.durationMs > 0 {
                        progressBar
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = item.secondaryTitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .frame(width: width, alignment: .leading)
        }
    }

    private var thumbHeight: CGFloat { width * 9.0 / 16.0 }

    private var progress: Double {
        guard item.durationMs > 0 else { return 0 }
        return min(max(Double(item.lastTimeMs) / Double(item.durationMs), 0), 1)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.55))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 4)
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = item.imageURL.flatMap(URL.init(string:)) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                Image(systemName: item.type == "live" ? "tv" : "film")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
            }
    }
}

/// Series-specific Continue Watching shelf. Dedupes by seriesId and renders
/// portrait series covers, so a user who watched three episodes of the same
/// series sees one card (not three). Tapping opens the series detail view
/// — the user presses "Resume" there to actually play the pending episode.
struct ContinueWatchingSeriesShelf: View {
    let playlist: Playlist
    let onTap: (RecentSeriesHistoryEntry) -> Void

    @Query<RecentSeriesHistoryRequest> private var entries: [RecentSeriesHistoryEntry]

    private let cardWidth: CGFloat = 260

    init(playlist: Playlist, onTap: @escaping (RecentSeriesHistoryEntry) -> Void) {
        self.playlist = playlist
        self.onTap = onTap
        _entries = Query(
            RecentSeriesHistoryRequest(playlistId: playlist.id, limit: 15),
            in: \.appDatabase
        )
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("continue_watching.title"))
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 60)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(entries) { entry in
                            SeriesHistoryCard(entry: entry, width: cardWidth) {
                                onTap(entry)
                            }
                            .frame(width: cardWidth)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 16)
                }
            }
            .padding(.vertical, 12)
            .focusSection()
        }
    }
}

private struct SeriesHistoryCard: View {
    let entry: RecentSeriesHistoryEntry
    let width: CGFloat
    let action: () -> Void

    private var thumbHeight: CGFloat { width * 3.0 / 2.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                ZStack(alignment: .bottom) {
                    thumbnail
                        .frame(width: width, height: thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if entry.durationMs > 0 {
                        progressBar
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }
            }
            .buttonStyle(.card)

            Text(entry.series.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .frame(width: width, alignment: .leading)
        }
    }

    private var progress: Double {
        guard entry.durationMs > 0 else { return 0 }
        return min(max(Double(entry.lastTimeMs) / Double(entry.durationMs), 0), 1)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.55))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 4)
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = entry.series.cover.flatMap(URL.init(string:)) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay {
                Image(systemName: "play.tv")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
            }
    }
}
