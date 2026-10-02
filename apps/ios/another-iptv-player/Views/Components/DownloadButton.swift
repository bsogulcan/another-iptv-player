import SwiftUI
import Combine
import GRDB
import GRDBQuery

/// İçerik detay ekranlarında gösterilen, 4 state'li indirme butonu.
/// State'ler DB + DownloadManager ilerlemesinden türetilir, item düşüyor/geliyor
/// diye view'da state tutmaya gerek yok.
///
/// The button itself follows only its own database row. `DownloadManager` publishes once
/// per percent of any running download, and a season mounts one button per episode, so
/// the manager is observed by `DownloadFraction` alone, which exists only inside the
/// button that is downloading.
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

    @Query<DownloadedItemByIDRequest> private var item: DBDownloadedItem?
    /// Side of the square every state draws its icon into. With one footprint for all of
    /// them, neither the compact chip nor the title next to the icon moves when the
    /// state changes.
    @ScaledMetric(relativeTo: .footnote) private var glyphSide: CGFloat = 17
    /// Off until the stored state has been drawn once. The row arrives a moment after
    /// the first frame, and that is the button catching up, not the item changing state:
    /// a film that is already downloaded must not fade in from "Download" each time its
    /// button is mounted, least of all one episode row after another while scrolling.
    @State private var animatesPhase = false
    /// The manager is adding this item and its row is not written yet. Fed by a
    /// deduplicated publisher, so progress ticks of other downloads never reach the button.
    @State private var isEnqueueing = false

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

    private enum Phase: Equatable { case idle, queued, downloading, completed, failed }
    private var phase: Phase {
        guard let item else { return isEnqueueing ? .queued : .idle }
        switch item.downloadStatus {
        case .completed: return .completed
        case .failed: return .failed
        case .queued: return .queued
        case .downloading: return .downloading
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .idle, .failed:
                Button(action: startDownload) {
                    label
                }
                .buttonStyle(.plain)
                .contextMenu { menuItems }
            case .queued, .downloading, .completed:
                // There is nothing to start in these states. A tap that did nothing
                // would hide Cancel and Delete behind a long press nobody tries.
                Menu {
                    menuItems
                } label: {
                    label
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier(compact ? "" : "detail.download")
        // Drives the symbol replace inside a label, and cross-fades the two controls
        // when the state moves between them.
        .animation(animatesPhase ? .snappy(duration: 0.25) : nil, value: phase)
        .onReceive(enqueueingPublisher) { pending in
            if isEnqueueing != pending { isEnqueueing = pending }
        }
        .onChange(of: phase) { _, _ in
            // Runs once the change is on screen, so the first one is drawn as it is and
            // every later one animates.
            if !animatesPhase { animatesPhase = true }
        }
    }

    private var enqueueingPublisher: AnyPublisher<Bool, Never> {
        let id = id
        return DownloadManager.shared.$pendingEnqueueIds
            .map { $0.contains(id) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: Label

    private var symbolName: String {
        switch phase {
        // Hidden under the ring while downloading; it keeps the idle symbol so that the
        // ring gives way to the next state's symbol, not to a leftover one.
        case .idle, .downloading: return "arrow.down.circle"
        case .queued: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch phase {
        case .idle, .queued, .downloading: return .primary
        case .completed: return .green
        case .failed: return .orange
        }
    }

    private var titleText: String {
        switch phase {
        case .idle: return L("download.action")
        case .queued: return L("download.status.queued")
        case .downloading: return L("download.status.downloading")
        case .completed: return L("download.completed")
        case .failed: return L("download.retry")
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            glyph
            if !compact {
                titleView
            }
        }
        .foregroundStyle(tint)
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
        // The compact chip is smaller than a finger. It sits in a 44 pt slot that is
        // part of the label, so the slot is the tap target and the row next to it keeps
        // one width in every state. Pinned to the slot's top trailing corner, the chip
        // stays level with the first line of a top-aligned row and at its trailing edge;
        // the extra room grows down and towards the text.
        .frame(
            minWidth: compact ? 44 : nil,
            minHeight: compact ? 44 : nil,
            alignment: .topTrailing
        )
        .contentShape(Rectangle())
    }

    /// One image for every state, so a change of state replaces the symbol in place
    /// instead of swapping views. The ring covers it while the download runs.
    private var glyph: some View {
        ZStack {
            Image(systemName: symbolName)
                .font(.footnote.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .opacity(phase == .downloading ? 0 : 1)
            if phase == .downloading {
                DownloadFraction(id: id) { fraction in
                    DownloadRing(fraction: fraction, side: glyphSide, speaksPercentage: compact)
                }
                .transition(.opacity)
            }
        }
        .frame(width: glyphSide, height: glyphSide)
    }

    @ViewBuilder
    private var titleView: some View {
        Group {
            if phase == .downloading {
                DownloadFraction(id: id) { fraction in
                    Text(DetailFormatting.percent(fraction))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: fraction))
                        .animation(.default, value: Int(fraction * 100))
                }
            } else {
                Text(titleText)
            }
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
    }

    // MARK: Actions

    @ViewBuilder
    private var menuItems: some View {
        switch phase {
        case .idle:
            Button { startDownload() } label: {
                Label(L("download.action"), systemImage: "arrow.down.circle")
            }
        case .downloading, .queued:
            Button(role: .destructive) {
                DownloadManager.shared.cancel(id: id)
            } label: {
                Label(L("download.cancel"), systemImage: "xmark")
            }
        case .completed:
            Button(role: .destructive) {
                Task { await DownloadManager.shared.delete(id: id) }
            } label: {
                Label(L("download.delete"), systemImage: "trash")
            }
        case .failed:
            Button { startDownload() } label: {
                Label(L("download.retry"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive) {
                Task { await DownloadManager.shared.delete(id: id) }
            } label: {
                Label(L("download.delete"), systemImage: "trash")
            }
        }
    }

    private func startDownload() {
        // A menu item can outlive the state it was built for.
        guard phase == .idle || phase == .failed else { return }
        // An item without a row never had a first change to wait for, and what follows
        // this tap is a real one.
        animatesPhase = true
        Task {
            await DownloadManager.shared.enqueue(
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
    }
}

/// Hands the fraction of one running download to `content`. This is the part of a
/// download button that re-evaluates on every progress tick of the manager, which is why
/// it is kept this small and mounted only while the item downloads.
private struct DownloadFraction<Content: View>: View {
    let id: String
    @ViewBuilder let content: (Double) -> Content

    @ObservedObject private var manager = DownloadManager.shared

    var body: some View {
        // 0 until the first tick: the row turns to "downloading" before the session
        // reports any bytes.
        content(manager.progress[id]?.fraction ?? 0)
    }
}

/// Determinate ring with the footprint of the icon it replaces. The circular
/// `ProgressView` style is free to ignore its value on iOS and spin instead.
private struct DownloadRing: View {
    let fraction: Double
    let side: CGFloat
    /// The compact button has no percentage text, so there the ring is what VoiceOver
    /// reads; next to the text it would say the same thing twice.
    let speaksPercentage: Bool

    var body: some View {
        let lineWidth = max(1.5, side * 0.12)
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // The manager reports whole percents; the ring glides between them.
                .animation(.linear(duration: 0.3), value: fraction)
            // A tap offers Cancel, and this is the glyph the system's own download
            // controls use to say so.
            Image(systemName: "stop.fill")
                .font(.system(size: side * 0.34))
        }
        .padding(lineWidth / 2)
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DetailFormatting.percent(fraction))
        .accessibilityHidden(!speaksPercentage)
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
            // The observation re-fetches on every write to the downloads table. Without
            // this, a status change of one item re-renders the button of every other.
            .removeDuplicates()
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
