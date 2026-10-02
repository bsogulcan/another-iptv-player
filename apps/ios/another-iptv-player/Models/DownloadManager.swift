import Foundation
import GRDB
import Combine
import os.log

private let downloadLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Downloads")

/// İndirme ilerlemesinin bellek içi temsili — UI sıkça değiştiği için DB'ye yazmayız.
struct DownloadProgress: Equatable {
    let totalBytes: Int64
    let downloadedBytes: Int64
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(downloadedBytes) / Double(totalBytes))
    }
}

/// Seri kuyruk: aynı anda yalnızca 1 indirme çalışır. Gerisi `.queued` DB status'üyle bekler.
/// `createdAt`'a göre sıralanır; biri bitince bir sonraki otomatik başlar. Uygulama yeniden
/// açıldığında yarım kalan indirmeler kuyruğun başına geri alınıp tek tek devam ettirilir.
///
/// Background indirme için `URLSessionConfiguration.background` kullanır; OS uygulamayı
/// sonlandırsa bile iOS indirmeyi sürdürür ve bitince app'i uyandırarak delegate'i çağırır.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    static let sessionIdentifier = (Bundle.main.bundleIdentifier ?? "app") + ".downloads"
    /// Aynı playlist için aynı anda kaç indirme paralel çalışabilir. Üstü kuyruğa alınır.
    /// Başka playlist'lerin kuyruğu etkilenmez — her playlist'in kendi slotu vardır.
    /// Server connection limitinin playlist bazlı olduğunu varsayıyoruz.
    static let maxConcurrentPerPlaylist = 1
    /// Bir indirme hata alınca kaç kez otomatik kuyruğun sonuna geri eklenir. Aşılınca `.failed`.
    private static let maxAutoRetries = 3
    /// Disk dolmadan bırakılacak güvenlik payı — sistem ve diğer uygulamalar için.
    private static let minFreeDiskMargin: Int64 = 200 * 1024 * 1024

    /// Aktif indirmelerin ilerlemesi, view'ların gözlemlemesi için.
    @Published private(set) var progress: [String: DownloadProgress] = [:]
    /// DB yazmalarından sonra artan counter — GRDBQuery dışındaki view'ların refresh tetiği.
    @Published private(set) var dbVersion: Int = 0

    private var session: URLSession!
    /// URLSessionTask.taskIdentifier → downloadedItem.id haritası.
    private var taskToId: [Int: String] = [:]
    /// downloadedItem.id → URLSessionDownloadTask (iptal için).
    private var idToTask: [String: URLSessionDownloadTask] = [:]
    /// downloadedItem.id → playlistId; per-playlist slot sayımı için.
    private var idToPlaylistId: [String: UUID] = [:]
    /// URLSessionTask.taskIdentifier → hedef relative path (delegate'de DB lookup yapmamak için).
    private var taskToRelativePath: [Int: String] = [:]
    /// `enqueue` async DB write yaparken — aynı id'ye ikinci çağrı gelmesin diye in-memory guard.
    private var enqueueInFlight: Set<String> = []
    /// Aynı task için didWriteData defalarca tetiklenir; totalBytes'i sadece ilk gerçek değerde DB'ye yazıyoruz.
    private var totalBytesPersistedFor: Set<Int> = []
    /// Son yayınlanan yüzde (taskIdentifier → 0…100). didWriteData saniyede onlarca kez
    /// tetiklenir; her seferinde @Published progress'e yazmak tüm DownloadButton'ları ve
    /// DownloadsView'ı yeniden render eder. Yüzde değişmeden publish edilmez.
    private var lastPublishedPercent: [Int: Int] = [:]
    /// Hata alan indirmelerin bellek içi yeniden-deneme sayacı.
    private var autoRetryCountById: [String: Int] = [:]
    /// Disk alanı yetmediği için bizim iptal ettiğimiz indirmeler: delegate'in cancelled
    /// dalında requeue yerine kalıcı failed işaretlenir.
    private var spaceFailedIds: Set<String> = []
    /// `pumpQueue` aynı anda bir kere çalışsın diye — paralel çağrılar `pumpPending`'ı set eder.
    private var pumpInFlight = false
    /// Pump çalışırken başka bir pump tetiklendiyse, mevcut pump bitmeden önce bir kez daha döner.
    private var pumpPending = false
    /// AppDelegate'in verdiği background completion handler; `urlSessionDidFinishEvents` çağırınca tetiklenir.
    var backgroundCompletionHandler: (() -> Void)?

    override private init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        Task { await restoreOutstandingTasks() }
    }

    // MARK: - App lifecycle

    /// App açıldığında: background session'da hâlâ canlı task varsa eşleştir, yoksa DB'de
    /// "downloading" olarak kalmış kayıtları tekrar `.queued`'e çevir (createdAt korunur →
    /// kuyruk sırası kaybolmaz). Sonra kuyruğu çalıştır.
    private func restoreOutstandingTasks() async {
        let downloadingRows: [DBDownloadedItem] = (try? await AppDatabase.shared.read { db in
            try DBDownloadedItem
                .filter(Column("status") == DownloadStatus.downloading.rawValue)
                .fetchAll(db)
        }) ?? []

        var matchedIds: Set<String> = []
        if !downloadingRows.isEmpty {
            let tasks = await session.allTasks
            for task in tasks {
                guard let url = task.originalRequest?.url?.absoluteString,
                      let match = downloadingRows.first(where: { $0.remoteURL == url }),
                      let downloadTask = task as? URLSessionDownloadTask else {
                    continue
                }
                taskToId[downloadTask.taskIdentifier] = match.id
                taskToRelativePath[downloadTask.taskIdentifier] = match.localPath
                idToTask[match.id] = downloadTask
                idToPlaylistId[match.id] = match.playlistId
                progress[match.id] = DownloadProgress(
                    totalBytes: Int64(match.totalBytes),
                    downloadedBytes: Int64(match.downloadedBytes)
                )
                matchedIds.insert(match.id)
            }
        }

        // Force-kill / OS-terminate sonrası iOS background task'i de düşürmüş olabilir.
        // DB "downloading" diyor ama session'da karşılık yok → kuyruğa geri al, sırayla devam etsin.
        // createdAt DEĞİŞTİRİLMEZ ki kullanıcının orjinal sırası korunsun.
        let orphans = downloadingRows.filter { !matchedIds.contains($0.id) }
        if !orphans.isEmpty {
            _ = try? await AppDatabase.shared.write { db in
                for orphan in orphans {
                    if var row = try DBDownloadedItem.filter(Column("id") == orphan.id).fetchOne(db) {
                        row.status = DownloadStatus.queued.rawValue
                        row.errorMessage = nil
                        // Keep byte counters when resume data exists — the restart will
                        // continue from the downloaded prefix, not from zero.
                        if !DownloadStorage.hasResumeData(forId: orphan.id) {
                            row.totalBytes = 0
                            row.downloadedBytes = 0
                        }
                        try row.update(db)
                    }
                }
            }
            for orphan in orphans {
                downloadLog.info("restore orphan id=\(orphan.id, privacy: .public) — DB downloading, task yok; kuyruğa geri alındı")
            }
            dbVersion &+= 1
        }

        await pumpQueue()
    }

    // MARK: - Public API

    /// İndirmeyi kuyruğa ekler. Kuyruk boşsa hemen başlar, değilse `.queued` olarak bekler.
    /// Aynı `id` zaten indiriliyor/kuyrukta ise çağrı yok sayılır.
    func enqueue(
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
        episodeNumber: Int? = nil
    ) async {
        if idToTask[id] != nil || enqueueInFlight.contains(id) { return }
        enqueueInFlight.insert(id)
        defer { enqueueInFlight.remove(id) }
        autoRetryCountById.removeValue(forKey: id)

        let ext = containerExtension ?? "mp4"
        let relPath = DownloadStorage.relativePath(playlistId: playlistId, type: type, streamId: streamId, ext: ext)

        do {
            _ = try DownloadStorage.ensureParentDirectory(for: relPath)
        } catch {
            await persistFailed(
                id: id, playlistId: playlistId, streamId: streamId, type: type,
                title: title, secondaryTitle: secondaryTitle, imageURL: imageURL,
                remoteURL: remoteURL.absoluteString, relPath: relPath,
                containerExtension: containerExtension, seriesId: seriesId,
                seasonNumber: seasonNumber, episodeNumber: episodeNumber,
                errorMessage: error.localizedDescription
            )
            return
        }

        // Her indirmeyi önce `.queued` olarak yaz; pump hemen sonra kuyruğu çalıştırır.
        // Bu sayede slot atama tek bir yerde (pumpQueue) olur, yarış durumu olmaz.
        do {
            try await AppDatabase.shared.write { db in
                let item = DBDownloadedItem(
                    id: id,
                    playlistId: playlistId,
                    streamId: streamId,
                    type: type,
                    title: title,
                    secondaryTitle: secondaryTitle,
                    imageURL: imageURL,
                    remoteURL: remoteURL.absoluteString,
                    localPath: relPath,
                    containerExtension: containerExtension,
                    totalBytes: 0,
                    downloadedBytes: 0,
                    status: DownloadStatus.queued.rawValue,
                    errorMessage: nil,
                    createdAt: Date(),
                    completedAt: nil,
                    seriesId: seriesId,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber
                )
                try item.save(db)
            }
        } catch {
            // Sessiz yutma: kullanıcı Download'a bastı, buton idle kaldı, hiçbir iz yok.
            // failed satırı yaz ki DownloadsView'da görünsün ve retry edilebilsin.
            downloadLog.error("enqueue id=\(id, privacy: .public) — DB insert failed: \(error.localizedDescription, privacy: .public)")
            await persistFailed(
                id: id, playlistId: playlistId, streamId: streamId, type: type,
                title: title, secondaryTitle: secondaryTitle, imageURL: imageURL,
                remoteURL: remoteURL.absoluteString, relPath: relPath,
                containerExtension: containerExtension, seriesId: seriesId,
                seasonNumber: seasonNumber, episodeNumber: episodeNumber,
                errorMessage: error.localizedDescription
            )
            return
        }
        dbVersion &+= 1
        downloadLog.info("enqueue id=\(id, privacy: .public) — kuyruğa alındı")
        await pumpQueue()
    }

    /// Devam eden veya kuyruktaki bir indirmeyi iptal eder; kısmi dosyayı ve DB row'unu siler.
    /// Aktif task iptal edildiyse kuyruktan sıradaki başlar.
    func cancel(id: String) {
        let hadActiveTask = idToTask[id] != nil
        if let task = idToTask[id] {
            task.cancel()
            idToTask.removeValue(forKey: id)
            taskToId.removeValue(forKey: task.taskIdentifier)
        }
        idToPlaylistId.removeValue(forKey: id)
        progress.removeValue(forKey: id)
        autoRetryCountById.removeValue(forKey: id)
        DownloadStorage.removeResumeData(forId: id)
        Task { [id] in
            await self.deleteRow(id: id, removeFile: true)
            if hadActiveTask { await self.pumpQueue() }
        }
    }

    /// Tamamlanmış/başarısız/kuyruktaki bir kaydı ve dosyasını siler.
    func delete(id: String) async {
        let hadActiveTask = idToTask[id] != nil
        if let task = idToTask[id] {
            task.cancel()
            idToTask.removeValue(forKey: id)
            taskToId.removeValue(forKey: task.taskIdentifier)
        }
        idToPlaylistId.removeValue(forKey: id)
        progress.removeValue(forKey: id)
        autoRetryCountById.removeValue(forKey: id)
        DownloadStorage.removeResumeData(forId: id)
        await deleteRow(id: id, removeFile: true)
        if hadActiveTask { await pumpQueue() }
    }

    /// Bir playlist silindiğinde çağrılır: ilgili task'leri iptal eder ve klasörü siler.
    func cleanupPlaylist(playlistId: UUID) {
        // Aktif task'ler: idToPlaylistId'den playlist eşleşmesiyle bul. `idToTask.keys`'i
        // string parse ile süzmek yerine playlist map'i daha güvenilir.
        let idsToCancel = idToPlaylistId.filter { $0.value == playlistId }.map(\.key)
        var hadAny = false
        for id in idsToCancel {
            if let task = idToTask[id] {
                task.cancel()
                taskToId.removeValue(forKey: task.taskIdentifier)
                hadAny = true
            }
            idToTask.removeValue(forKey: id)
            idToPlaylistId.removeValue(forKey: id)
            progress.removeValue(forKey: id)
            autoRetryCountById.removeValue(forKey: id)
        }
        DownloadStorage.removePlaylistDirectory(playlistId: playlistId)
        DownloadStorage.removeResumeData(playlistId: playlistId)
        dbVersion &+= 1
        if hadAny { Task { await pumpQueue() } }
    }

    /// Tamamlanmış bir indirmenin local file URL'i (oynatma için).
    func localURL(forId id: String) async -> URL? {
        do {
            let row: DBDownloadedItem? = try await AppDatabase.shared.read { db in
                try DBDownloadedItem.filter(Column("id") == id).fetchOne(db)
            }
            guard let row, row.downloadStatus == .completed else { return nil }
            let url = try DownloadStorage.absoluteURL(forRelativePath: row.localPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    /// Sadece belirli bir playlist'e ait tüm indirmeleri (her statüde) siler.
    /// Aktif task'leri iptal eder, dosyaları diskten kaldırır, DB row'larını siler.
    func deleteAll(playlistId: UUID) async {
        // Aktif task'ler
        let activeIds = idToPlaylistId.filter { $0.value == playlistId }.map(\.key)
        var hadAny = false
        for id in activeIds {
            if let task = idToTask[id] {
                task.cancel()
                taskToId.removeValue(forKey: task.taskIdentifier)
                hadAny = true
            }
            idToTask.removeValue(forKey: id)
            idToPlaylistId.removeValue(forKey: id)
            progress.removeValue(forKey: id)
            autoRetryCountById.removeValue(forKey: id)
        }
        // DB row'ları (bu playlist'e ait olanlar) ve dosyalar
        let rows: [DBDownloadedItem] = (try? await AppDatabase.shared.read { db in
            try DBDownloadedItem.filter(Column("playlistId") == playlistId).fetchAll(db)
        }) ?? []
        for row in rows {
            DownloadStorage.removeFile(relativePath: row.localPath)
        }
        // Playlist klasörünü tamamen kaldır (subdir + olası boş klasörler).
        DownloadStorage.removePlaylistDirectory(playlistId: playlistId)
        DownloadStorage.removeResumeData(playlistId: playlistId)
        _ = try? await AppDatabase.shared.write { db in
            try DBDownloadedItem.filter(Column("playlistId") == playlistId).deleteAll(db)
        }
        dbVersion &+= 1
        if hadAny { await pumpQueue() }
    }

    /// Tüm playlist'lerin indirmelerini (her statüde) siler.
    func deleteAll() async {
        for (id, task) in idToTask {
            task.cancel()
            taskToId.removeValue(forKey: task.taskIdentifier)
            progress.removeValue(forKey: id)
        }
        idToTask.removeAll()
        idToPlaylistId.removeAll()
        autoRetryCountById.removeAll()

        let all: [DBDownloadedItem] = (try? await AppDatabase.shared.read { db in
            try DBDownloadedItem.fetchAll(db)
        }) ?? []
        for row in all {
            DownloadStorage.removeFile(relativePath: row.localPath)
        }
        _ = try? await AppDatabase.shared.write { db in
            try DBDownloadedItem.deleteAll(db)
        }
        DownloadStorage.removeAllResumeData()
        dbVersion &+= 1
    }

    // MARK: - ID helpers
    static func idFor(vod playlistId: UUID, streamId: Int) -> String {
        "vod.\(playlistId.uuidString).\(streamId)"
    }
    static func idFor(episode playlistId: UUID, episodeId: String) -> String {
        "episode.\(playlistId.uuidString).\(episodeId)"
    }
    /// M3U channel id'si UUID ile karışmasın diye `m3u_` prefix'i kullanırız.
    static func idFor(m3uChannel playlistId: UUID, channelId: String) -> String {
        "vod.\(playlistId.uuidString).m3u_\(channelId)"
    }

    // MARK: - Settings
    private static var wifiOnly: Bool {
        UserDefaults.standard.bool(forKey: "download.wifi_only")
    }

    // MARK: - Queue pump

    /// Playlist için aktif (indiriliyor) download sayısı.
    private func activeDownloadCount(for playlistId: UUID) -> Int {
        idToPlaylistId.values.reduce(into: 0) { $0 += ($1 == playlistId ? 1 : 0) }
    }

    /// Verilen playlist için aktif bir indirme var mı — player warning'i için.
    func hasActiveDownload(playlistId: UUID) -> Bool {
        activeDownloadCount(for: playlistId) > 0
    }

    /// Kuyruğu işler: her playlist için `maxConcurrentPerPlaylist` kadar aktif task'e
    /// kadar `.queued` row'ları `.downloading`'e çeker. createdAt artan sırayla bakılır —
    /// playlist'inde slot varsa başlat, yoksa atla ve sonraki row'a bak.
    /// Aynı anda yalnızca bir pump çalışır; çakışan çağrılar `pumpPending` ile işaretlenir.
    private func pumpQueue() async {
        if pumpInFlight {
            pumpPending = true
            return
        }
        pumpInFlight = true
        defer { pumpInFlight = false }

        repeat {
            pumpPending = false

            let queuedRows: [DBDownloadedItem] = (try? await AppDatabase.shared.read { db in
                try DBDownloadedItem
                    .filter(Column("status") == DownloadStatus.queued.rawValue)
                    .order(Column("createdAt"))
                    .fetchAll(db)
            }) ?? []

            var remaining = queuedRows
            while !remaining.isEmpty {
                // İlk playlist'inde boş slot olan row'u al.
                guard let idx = remaining.firstIndex(where: { row in
                    activeDownloadCount(for: row.playlistId) < Self.maxConcurrentPerPlaylist
                }) else { break }
                let next = remaining.remove(at: idx)

                guard let url = URL(string: next.remoteURL) else {
                    downloadLog.error("pumpQueue id=\(next.id, privacy: .public) — URL bozuk, failed işaretleniyor")
                    await markFailed(
                        id: next.id,
                        error: NSError(domain: "Download", code: -3,
                                       userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
                    )
                    continue
                }

                // Boyut önceki denemeden biliniyorsa başlamadan sığacağını doğrula.
                if next.totalBytes > 0 {
                    let remainingBytes = Int64(max(next.totalBytes - next.downloadedBytes, 0))
                    if let available = DownloadStorage.availableCapacityBytes(),
                       available < remainingBytes + Self.minFreeDiskMargin {
                        downloadLog.error("pumpQueue no-space id=\(next.id, privacy: .public) needed=\(remainingBytes) available=\(available)")
                        await markFailed(
                            id: next.id,
                            error: NSError(domain: "Download", code: -4,
                                           userInfo: [NSLocalizedDescriptionKey: L("download.error.no_space")])
                        )
                        continue
                    }
                }

                _ = try? await AppDatabase.shared.write { db in
                    if var row = try DBDownloadedItem.filter(Column("id") == next.id).fetchOne(db) {
                        row.status = DownloadStatus.downloading.rawValue
                        try row.update(db)
                    }
                }
                startTask(id: next.id, playlistId: next.playlistId, remoteURL: url, relPath: next.localPath)
                dbVersion &+= 1
            }
        } while pumpPending
    }

    /// DB row'u zaten var kabul edilir. URLSession task'ini kurar ve bellek içi haritalara yazar.
    /// Önceki denemeden resume data varsa kaldığı yerden devam eder, yoksa sıfırdan başlar.
    private func startTask(id: String, playlistId: UUID, remoteURL: URL, relPath: String) {
        // The remote URL carries the panel credentials; a public log line only gets the redacted form.
        downloadLog.info("start id=\(id, privacy: .public) playlist=\(playlistId.uuidString, privacy: .public) url=\(Log.redact(remoteURL), privacy: .public)")
        let task: URLSessionDownloadTask
        if let resumeData = DownloadStorage.loadResumeData(forId: id) {
            // Consume the blob up front: if this attempt fails again we either get
            // fresh resume data (persisted anew in didCompleteWithError) or the next
            // retry falls back to a clean full download.
            DownloadStorage.removeResumeData(forId: id)
            downloadLog.info("start id=\(id, privacy: .public) — resuming with \(resumeData.count) bytes of resume data")
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: remoteURL)
            request.allowsCellularAccess = !Self.wifiOnly
            task = session.downloadTask(with: request)
        }
        taskToId[task.taskIdentifier] = id
        taskToRelativePath[task.taskIdentifier] = relPath
        idToTask[id] = task
        idToPlaylistId[id] = playlistId
        if progress[id] == nil {
            progress[id] = DownloadProgress(totalBytes: 0, downloadedBytes: 0)
        }
        task.resume()
    }

    // MARK: - DB helpers

    private func deleteRow(id: String, removeFile: Bool) async {
        do {
            let existing: DBDownloadedItem? = try await AppDatabase.shared.read { db in
                try DBDownloadedItem.filter(Column("id") == id).fetchOne(db)
            }
            if removeFile, let relPath = existing?.localPath {
                DownloadStorage.removeFile(relativePath: relPath)
            }
            _ = try await AppDatabase.shared.write { db in
                try DBDownloadedItem.filter(Column("id") == id).deleteAll(db)
            }
            dbVersion &+= 1
        } catch {
            // ignore
        }
    }

    private func persistFailed(
        id: String,
        playlistId: UUID,
        streamId: String,
        type: String,
        title: String,
        secondaryTitle: String?,
        imageURL: String?,
        remoteURL: String,
        relPath: String,
        containerExtension: String?,
        seriesId: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        errorMessage: String
    ) async {
        _ = try? await AppDatabase.shared.write { db in
            let item = DBDownloadedItem(
                id: id,
                playlistId: playlistId,
                streamId: streamId,
                type: type,
                title: title,
                secondaryTitle: secondaryTitle,
                imageURL: imageURL,
                remoteURL: remoteURL,
                localPath: relPath,
                containerExtension: containerExtension,
                totalBytes: 0,
                downloadedBytes: 0,
                status: DownloadStatus.failed.rawValue,
                errorMessage: errorMessage,
                createdAt: Date(),
                completedAt: nil,
                seriesId: seriesId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber
            )
            try item.save(db)
        }
        dbVersion &+= 1
    }
}

// MARK: - URLSessionDownloadDelegate
// Delegate queue = main queue olarak yapılandırıldığı için main-actor state'ine direkt erişebiliriz.

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        MainActor.assumeIsolated {
            let taskId = downloadTask.taskIdentifier
            guard let id = self.taskToId[taskId] else { return }
            let newProgress = DownloadProgress(
                totalBytes: max(0, totalBytesExpectedToWrite),
                downloadedBytes: max(0, totalBytesWritten)
            )
            let percent = Int(newProgress.fraction * 100)
            let totalJustBecameKnown = totalBytesExpectedToWrite > 0
                && !self.totalBytesPersistedFor.contains(taskId)
            if self.lastPublishedPercent[taskId] != percent || totalJustBecameKnown {
                self.lastPublishedPercent[taskId] = percent
                self.progress[id] = newProgress
            }
            // Content-Length öğrenilir öğrenilmez sığmayacak dosyayı kes: 2 GB boş alana
            // 6 GB film indirmek saatler sonra disk-dolu hatasıyla (ve 3 retry ile) bitiyordu.
            if totalJustBecameKnown {
                let remaining = totalBytesExpectedToWrite - totalBytesWritten
                if let available = DownloadStorage.availableCapacityBytes(),
                   available < remaining + Self.minFreeDiskMargin {
                    downloadLog.error("no-space id=\(id, privacy: .public) needed=\(remaining) available=\(available)")
                    self.spaceFailedIds.insert(id)
                    downloadTask.cancel()
                    return
                }
            }
            if totalBytesExpectedToWrite > 0,
               !self.totalBytesPersistedFor.contains(taskId) {
                self.totalBytesPersistedFor.insert(taskId)
                let total = totalBytesExpectedToWrite
                Task {
                    _ = try? await AppDatabase.shared.write { db in
                        if var row = try DBDownloadedItem.filter(Column("id") == id).fetchOne(db) {
                            row.totalBytes = Int(total)
                            try row.update(db)
                        }
                    }
                }
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Dosya bu delegate metodu dönünce silinir; SENKRON taşımak zorundayız.
        let (id, relPath) = MainActor.assumeIsolated { () -> (String?, String?) in
            let taskId = downloadTask.taskIdentifier
            return (self.taskToId[taskId], self.taskToRelativePath[taskId])
        }
        guard let id, let relPath else { return }

        let fm = FileManager.default
        let sourceSize: Int64 = {
            guard let attrs = try? fm.attributesOfItem(atPath: location.path) else { return 0 }
            return (attrs[.size] as? Int64) ?? 0
        }()
        guard sourceSize > 0 else {
            MainActor.assumeIsolated {
                _ = Task { await self.markFailed(
                    id: id,
                    error: NSError(domain: "Download", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Empty download payload"])
                ) }
            }
            return
        }

        do {
            let destination = try DownloadStorage.ensureParentDirectory(for: relPath)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
        } catch {
            MainActor.assumeIsolated {
                _ = Task { await self.markFailed(id: id, error: error) }
            }
            return
        }

        MainActor.assumeIsolated {
            _ = Task { await self.markCompleted(id: id, fallbackSize: sourceSize) }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        MainActor.assumeIsolated {
            let taskId = task.taskIdentifier
            self.totalBytesPersistedFor.remove(taskId)
            self.lastPublishedPercent.removeValue(forKey: taskId)
            // Guard'dan ÖNCE temizle: cancel/delete yolları taskToId'yi çoktan silmiş
            // olabilir; aksi halde her iptal edilen indirme bir path girdisi sızdırır.
            self.taskToRelativePath.removeValue(forKey: taskId)
            let resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            guard let id = self.taskToId[taskId] else {
                // No in-memory mapping — typically a delegate event delivered right after a
                // relaunch (force-quit cancels background tasks and hands us their resume
                // data here, before restoreOutstandingTasks could match anything). Re-attach
                // the resume data to the matching DB row so the download continues from
                // where it stopped instead of restarting at byte 0.
                if let resumeData,
                   let url = task.originalRequest?.url?.absoluteString ?? task.currentRequest?.url?.absoluteString {
                    Task { await self.adoptOrphanResumeData(resumeData, remoteURL: url) }
                }
                return
            }
            self.taskToId.removeValue(forKey: taskId)
            self.idToTask.removeValue(forKey: id)
            self.idToPlaylistId.removeValue(forKey: id)

            if let error = error {
                let ns = error as NSError
                // User cancellation removes the id mappings before calling task.cancel(),
                // so reaching here with a known id means the SYSTEM cancelled the task
                // (session invalidation, OS reclaim). Keep the resume data and requeue;
                // for a genuine user cancel there is nothing to do (row already deleted).
                if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                    // Disk alanı yetmediği için bizim kestiğimiz task: requeue etme.
                    if self.spaceFailedIds.remove(id) != nil {
                        DownloadStorage.removeResumeData(forId: id)
                        self.autoRetryCountById.removeValue(forKey: id)
                        Task {
                            await self.markFailed(id: id, error: NSError(
                                domain: "Download", code: -4,
                                userInfo: [NSLocalizedDescriptionKey: L("download.error.no_space")]
                            ))
                            await self.pumpQueue()
                        }
                        return
                    }
                    if let resumeData {
                        DownloadStorage.saveResumeData(resumeData, forId: id)
                        downloadLog.info("system-cancel id=\(id, privacy: .public) — resume data saklandı, kuyruğa geri alındı")
                        Task {
                            await self.requeueAfterError(id: id, errorMessage: error.localizedDescription, preserveProgress: true)
                            await self.pumpQueue()
                        }
                    }
                    return
                }
                // Disk dolu hatası retry ile düzelmez — 3 kez baştan indirmeye çalışmak
                // gigabaytlarca boşa trafik demek. Doğrudan failed işaretle.
                let isDiskFull = (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError)
                    || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC))
                if isDiskFull {
                    self.autoRetryCountById.removeValue(forKey: id)
                    if let resumeData {
                        DownloadStorage.saveResumeData(resumeData, forId: id)
                    }
                    Task {
                        await self.markFailed(id: id, error: NSError(
                            domain: "Download", code: -4,
                            userInfo: [NSLocalizedDescriptionKey: L("download.error.no_space")]
                        ))
                        await self.pumpQueue()
                    }
                    return
                }
                // Persist resume data so the retry (or a later manual retry) resumes
                // from the downloaded prefix instead of restarting the whole file.
                if let resumeData {
                    DownloadStorage.saveResumeData(resumeData, forId: id)
                }
                let attempts = (self.autoRetryCountById[id] ?? 0) + 1
                self.autoRetryCountById[id] = attempts
                if attempts <= Self.maxAutoRetries {
                    downloadLog.info("retry id=\(id, privacy: .public) attempt=\(attempts) resume=\(resumeData != nil) — kuyruğun sonuna eklendi: \(error.localizedDescription, privacy: .public)")
                    Task {
                        await self.requeueAfterError(id: id, errorMessage: error.localizedDescription, preserveProgress: resumeData != nil)
                        await self.pumpQueue()
                    }
                } else {
                    self.autoRetryCountById.removeValue(forKey: id)
                    Task {
                        await self.markFailed(id: id, error: error)
                        await self.pumpQueue()
                    }
                }
            } else {
                // Başarılı tamamlanma: markCompleted didFinishDownloadingTo'da çağrıldı.
                self.autoRetryCountById.removeValue(forKey: id)
                Task { await self.pumpQueue() }
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated {
            let handler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            handler?()
        }
    }

    /// Hata alan bir indirmeyi kuyruğun sonuna geri koyar. `createdAt` güncellenir ki
    /// diğer bekleyenler bloklanmasın.
    /// `preserveProgress`: resume data saklandıysa true — byte sayaçları korunur ki
    /// UI "kaldığı yerden devam edecek" durumunu doğru göstersin.
    private func requeueAfterError(id: String, errorMessage: String, preserveProgress: Bool = false) async {
        _ = try? await AppDatabase.shared.write { db in
            if var row = try DBDownloadedItem.filter(Column("id") == id).fetchOne(db) {
                row.status = DownloadStatus.queued.rawValue
                row.errorMessage = errorMessage
                if !preserveProgress {
                    row.totalBytes = 0
                    row.downloadedBytes = 0
                }
                row.createdAt = Date()
                try row.update(db)
            }
        }
        progress.removeValue(forKey: id)
        dbVersion &+= 1
    }

    /// Relaunch sonrası eşleşmesiz gelen delegate hatasındaki resume data'yı, URL üzerinden
    /// DB row'una bağlar ve row'u kuyruğa geri alır. Best-effort: eşleşme yoksa sessizce düşer.
    private func adoptOrphanResumeData(_ data: Data, remoteURL: String) async {
        let row: DBDownloadedItem? = try? await AppDatabase.shared.read { db in
            try DBDownloadedItem
                .filter(Column("remoteURL") == remoteURL)
                .filter([DownloadStatus.downloading.rawValue, DownloadStatus.queued.rawValue].contains(Column("status")))
                .fetchOne(db)
        }
        guard let row else { return }
        // Skip if an in-memory task is already re-downloading this item.
        guard idToTask[row.id] == nil else { return }
        DownloadStorage.saveResumeData(data, forId: row.id)
        downloadLog.info("adopt-resume id=\(row.id, privacy: .public) — relaunch sonrası resume data kurtarıldı")
        if row.downloadStatus == .downloading {
            await requeueAfterError(id: row.id, errorMessage: "Interrupted", preserveProgress: true)
        }
        await pumpQueue()
    }

    private func markCompleted(id: String, fallbackSize: Int64 = 0) async {
        let now = Date()
        let row: DBDownloadedItem? = try? await AppDatabase.shared.read { db in
            try DBDownloadedItem.filter(Column("id") == id).fetchOne(db)
        }
        guard let row else {
            progress.removeValue(forKey: id)
            return
        }
        let actualSize: Int64 = {
            guard let url = try? DownloadStorage.absoluteURL(forRelativePath: row.localPath),
                  let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                return 0
            }
            return (attrs[.size] as? Int64) ?? 0
        }()
        let finalSize = max(actualSize, fallbackSize)
        if finalSize == 0 {
            await markFailed(
                id: id,
                error: NSError(domain: "Download", code: -2,
                               userInfo: [NSLocalizedDescriptionKey: "Downloaded file missing or empty"])
            )
            return
        }
        _ = try? await AppDatabase.shared.write { db in
            if var r = try DBDownloadedItem.filter(Column("id") == id).fetchOne(db) {
                r.status = DownloadStatus.completed.rawValue
                r.completedAt = now
                r.totalBytes = Int(finalSize)
                r.downloadedBytes = Int(finalSize)
                r.errorMessage = nil
                try r.update(db)
            }
        }
        DownloadStorage.removeResumeData(forId: id)
        progress.removeValue(forKey: id)
        dbVersion &+= 1
    }

    private func markFailed(id: String, error: Error) async {
        _ = try? await AppDatabase.shared.write { db in
            if var row = try DBDownloadedItem.filter(Column("id") == id).fetchOne(db) {
                row.status = DownloadStatus.failed.rawValue
                row.errorMessage = error.localizedDescription
                try row.update(db)
            }
        }
        progress.removeValue(forKey: id)
        dbVersion &+= 1
    }
}
