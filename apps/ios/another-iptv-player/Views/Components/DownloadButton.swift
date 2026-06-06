import SwiftUI
import Combine
import GRDB
import GRDBQuery

/// İçerik detay ekranlarında gösterilen, 4 state'li indirme butonu.
/// State'ler DB + DownloadManager ilerlemesinden türetilir, item düşüyor/geliyor
/// diye view'da state tutmaya gerek yok.
struct DownloadButton: View {
    /// `DownloadManager.idFor(vod:streamId:)` veya `.idFor(episode:episodeId:)` ile üret.
    let id: String
    let playlistId: UUID
    let streamId: String
    let type: String // "vod" veya "episode"
    let title: String
    let secondaryTitle: String?
    let imageURL: String?
    let remoteURL: URL
    let containerExtension: String?
    var seriesId: String? = nil
    var seasonNumber: Int? = nil
    var episodeNumber: Int? = nil

    /// Kompakt variant — dizi bölüm satırları gibi dar alanlar için.
    var compact: Bool = false

    @ObservedObject private var manager = DownloadManager.shared
    @Query<DownloadedItemByIDRequest> private var item: DBDownloadedItem?

    init(
        id: String,
        playlistId: UUID,
        streamId: String,
        type: String,
        title: String,
        secondaryTitle: String?,
        imageURL: String?,
        remoteURL: URL,
        containerExtension: String?,
        seriesId: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        compact: Bool = false
    ) {
        self.id = id
        self.playlistId = playlistId
        self.streamId = streamId
        self.type = type
        self.title = title
        self.secondaryTitle = secondaryTitle
        self.imageURL = imageURL
        self.remoteURL = remoteURL
        self.containerExtension = containerExtension
        self.seriesId = seriesId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.compact = compact
        _item = Query(DownloadedItemByIDRequest(id: id), in: \.appDatabase)
    }

    private var progress: DownloadProgress? { manager.progress[id] }

    private enum State { case idle, queued, downloading(Double), completed, failed }
    private var state: State {
        if let item = item {
            switch item.downloadStatus {
            case .completed: return .completed
            case .failed: return .failed
            case .queued: return .queued
            case .downloading:
                return .downloading(progress?.fraction ?? 0)
            }
        }
        return .idle
    }

    var body: some View {
        Button(action: primaryAction) {
            labelContent
        }
        .buttonStyle(.plain)
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var labelContent: some View {
        switch state {
        case .idle:
            button(icon: "arrow.down.circle", title: L("download.action"))
        case .queued:
            button(icon: "clock", title: L("download.status.queued"))
        case .downloading(let p):
            downloadingLabel(progress: p)
        case .completed:
            button(icon: "checkmark.circle.fill", title: L("download.completed"), accent: .green)
        case .failed:
            button(icon: "exclamationmark.triangle.fill", title: L("download.retry"), accent: .orange)
        }
    }

    private func button(icon: String, title: String, accent: Color = .primary) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: icon)
                .font(compact ? .footnote.weight(.semibold) : .footnote.weight(.semibold))
            if !compact {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(accent)
        .frame(maxWidth: compact ? nil : .infinity)
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 6 : 11)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func downloadingLabel(progress: Double) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            ProgressView(value: max(0, min(1, progress)))
                .progressViewStyle(.circular)
                .controlSize(.mini)
            Text(L("download.downloading_format", Int(progress * 100)))
                .font(compact ? .caption2.weight(.semibold) : .footnote.weight(.semibold))
                .lineLimit(1)
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: compact ? nil : .infinity)
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 6 : 11)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        switch state {
        case .idle:
            Button { primaryAction() } label: {
                Label(L("download.action"), systemImage: "arrow.down.circle")
            }
        case .downloading, .queued:
            Button(role: .destructive) {
                manager.cancel(id: id)
            } label: {
                Label(L("download.cancel"), systemImage: "xmark")
            }
        case .completed:
            Button(role: .destructive) {
                Task { await manager.delete(id: id) }
            } label: {
                Label(L("download.delete"), systemImage: "trash")
            }
        case .failed:
            Button { primaryAction() } label: {
                Label(L("download.retry"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                Task { await manager.delete(id: id) }
            } label: {
                Label(L("download.delete"), systemImage: "trash")
            }
        }
    }

    private func primaryAction() {
        switch state {
        case .idle, .failed:
            Task {
                await manager.enqueue(
                    id: id,
                    playlistId: playlistId,
                    streamId: streamId,
                    type: type,
                    title: title,
                    secondaryTitle: secondaryTitle,
                    imageURL: imageURL,
                    remoteURL: remoteURL,
                    containerExtension: containerExtension,
                    seriesId: seriesId,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber
                )
            }
        case .downloading, .queued:
            // İndirme sürerken veya kuyruktayken butona tıklama yok sayılır; iptal için context menu kullanılır.
            break
        case .completed:
            // Completed state için tıklama boş bırakılır; context menu ile sil.
            break
        }
    }
}

// MARK: - M3U context-menu items

/// M3U kanal kartının context menüsünde kullanılan indirme item'ı.
/// State'e göre tek bir buton gösterir: idle → "İndir", downloading/queued → "İptal",
/// completed/failed → "Sil". Yalnızca contextMenu açıldığında değerlendirildiği için
/// kart başına @Query maliyeti pratik olarak yok.
struct M3UDownloadMenuItems: View {
    let id: String
    let playlistId: UUID
    let streamId: String
    let title: String
    let secondaryTitle: String?
    let imageURL: String?
    let remoteURL: URL
    let containerExtension: String?

    @ObservedObject private var manager = DownloadManager.shared
    @Query<DownloadedItemByIDRequest> private var item: DBDownloadedItem?

    init(
        id: String,
        playlistId: UUID,
        streamId: String,
        title: String,
        secondaryTitle: String?,
        imageURL: String?,
        remoteURL: URL,
        containerExtension: String?
    ) {
        self.id = id
        self.playlistId = playlistId
        self.streamId = streamId
        self.title = title
        self.secondaryTitle = secondaryTitle
        self.imageURL = imageURL
        self.remoteURL = remoteURL
        self.containerExtension = containerExtension
        _item = Query(DownloadedItemByIDRequest(id: id), in: \.appDatabase)
    }

    var body: some View {
        if let item = item {
            switch item.downloadStatus {
            case .downloading, .queued:
                Button(role: .destructive) {
                    manager.cancel(id: id)
                } label: {
                    Label(L("download.cancel"), systemImage: "xmark")
                }
            case .completed, .failed:
                Button(role: .destructive) {
                    Task { await manager.delete(id: id) }
                } label: {
                    Label(L("download.delete"), systemImage: "trash")
                }
            }
        } else {
            Button {
                Task {
                    await manager.enqueue(
                        id: id,
                        playlistId: playlistId,
                        streamId: streamId,
                        type: "vod",
                        title: title,
                        secondaryTitle: secondaryTitle,
                        imageURL: imageURL,
                        remoteURL: remoteURL,
                        containerExtension: containerExtension
                    )
                }
            } label: {
                Label(L("download.action"), systemImage: "arrow.down.circle")
            }
        }
    }
}

// MARK: - DB Requests

struct DownloadedItemByIDRequest: Queryable, Equatable {
    static var defaultValue: DBDownloadedItem? { nil }
    let id: String
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<DBDownloadedItem?, Never> {
        ValueObservation
            .tracking { db in
                try DBDownloadedItem.filter(Column("id") == id).fetchOne(db)
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just(nil) }
            .eraseToAnyPublisher()
    }
}

struct AllDownloadsRequest: Queryable, Equatable {
    static var defaultValue: [DBDownloadedItem] { [] }
    let playlistId: UUID
    func publisher(in appDatabase: AppDatabase) -> AnyPublisher<[DBDownloadedItem], Never> {
        ValueObservation
            .tracking { db in
                try DBDownloadedItem
                    .filter(Column("playlistId") == playlistId)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
            .publisher(in: appDatabase.reader)
            .catch { _ in Just([]) }
            .eraseToAnyPublisher()
    }
}
