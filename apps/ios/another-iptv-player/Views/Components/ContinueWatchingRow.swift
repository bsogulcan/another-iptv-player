import SwiftUI
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
        _historyItems = Query(
            RecentWatchHistoryRequest(playlistId: playlist.id, limit: 10, type: typeFilter),
            in: \.appDatabase
        )
    }

    var body: some View {
        if !historyItems.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    destination()
                } label: {
                    HStack(spacing: 6) {
                        Text(L("continue_watching.title"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(historyItems) { item in
                            HistoryCard(item: item)
                                .onTapGesture {
                                    onPlay(item)
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

struct HistoryCard: View {
    let item: DBWatchHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                CachedImage(
                    url: item.imageURL.flatMap { URL(string: $0) },
                    width: 160,
                    height: 90,
                    cornerRadius: 12,
                    contentMode: .fill,
                    iconName: item.type == "live" ? "tv" : "film"
                )

                if item.type != "live" && item.durationMs > 0 {
                    let progress = Double(item.lastTimeMs) / Double(item.durationMs)
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.black.opacity(0.5))
                            .frame(height: 3)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 160 * min(max(progress, 0), 1), height: 3)
                    }
                    .cornerRadius(1.5)
                }
            }
            .frame(width: 160, height: 90)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)

                if let subtitle = item.secondaryTitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 160, alignment: .leading)
        }
    }
}
