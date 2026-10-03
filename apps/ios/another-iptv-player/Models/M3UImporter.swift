import Foundation
import GRDB
import CryptoKit

/// M3U kanallarını veritabanına yazan tek kapı. Hem ekleme hem yenileme akışı aynı yolu kullanır.
///
/// Tüm işlem GRDB'nin write kuyruğunda tek transaction'da yapılır:
/// - Playlist (opsiyonel güncelleme ile) kaydedilir.
/// - Eski `m3uChannel` kayıtları silinir.
/// - Yeni kanallar `sortIndex`'e göre batch yazılır.
/// The rows themselves are built before the transaction opens (`makeRows`).
///
/// Kanal ID'si **deterministik** (SHA256 of `playlistId:url`). Reimport sonrası aynı URL aynı ID'yi
/// alır, böylece favoriler ve izleme geçmişi korunur.
enum M3UImporter {

    /// Playlist + kanallar için tam yenileme. Eski kayıtları siler, yenilerini yazar.
    ///
    /// The playlist row is an upsert that owns three columns: `name`, `serverURL`
    /// and `m3uEpgURL`. Everything else stays as stored. Callers pass the value their
    /// screen was opened with, and writing that whole value back undid whatever
    /// settings had saved since (adult filter, manual EPG URL, guide switch, cached
    /// timezone and timeshift style). A playlist that is not stored yet is inserted
    /// as given, which is the add flow.
    ///
    /// - Parameter clearServerURL: Yerel dosya import'unda playlist URL'i boşaltılır (refresh tekrar dosya ister).
    /// - Parameter database: Injected by tests; the app writes to the shared database.
    static func replace(
        playlist: Playlist,
        channels: [ParsedM3UChannel],
        epgURL: String?,
        clearServerURL: Bool = false,
        in database: AppDatabase = .shared
    ) async throws {
        let pid = playlist.id
        // Built before the transaction and away from the main actor: hashing an id
        // per channel is the slow part of a large import, and while it ran inside
        // the write it kept the single database writer from everything else (a
        // favourite, a download, the player's progress).
        let rows = try await prepareRows(playlistId: pid, channels: channels)
        try Task.checkCancellation()
        try await database.write { db in
            var stored = try Playlist.fetchOne(db, key: pid) ?? playlist
            stored.name = playlist.name
            stored.serverURL = clearServerURL ? "" : playlist.serverURL
            stored.m3uEpgURL = epgURL
            try stored.save(db)

            try db.execute(sql: "DELETE FROM m3uChannel WHERE playlistId = ?", arguments: [pid])
            for row in rows {
                // The playlist's rows were deleted just above, so there is nothing to
                // update: `save` paid for a failed UPDATE before every INSERT. Replace
                // on conflict keeps its outcome for an id that repeats: the last row wins.
                try row.insert(db, onConflict: .replace)
            }
        }
    }

    /// Keeps hashing off the caller's actor while inheriting its cancellation.
    @concurrent
    private static func prepareRows(playlistId: UUID, channels: [ParsedM3UChannel]) async throws -> [DBM3UChannel] {
        try makeRows(playlistId: playlistId, channels: channels)
    }

    /// The rows of an import, in playlist order (`sortIndex` is the position).
    nonisolated static func makeRows(playlistId pid: UUID, channels: [ParsedM3UChannel]) throws -> [DBM3UChannel] {
        try Task.checkCancellation()
        // Aynı URL birden çok grupta geçebilir ("ALL" + ülke grubu gibi) — eskiden
        // INSERT OR REPLACE hepsini tek satıra indiriyordu ve kanallar gruplardan
        // sessizce kayboluyordu. İlk geçiş URL bazlı eski kimliğini korur (favoriler
        // ve izleme geçmişi reimport'ta yaşasın diye), sonraki tekrarlar deterministik
        // `#n` son ekiyle ayrı satır olur.
        var urlOccurrences: [String: Int] = [:]
        var rows: [DBM3UChannel] = []
        rows.reserveCapacity(channels.count)
        for (index, ch) in channels.enumerated() {
            if index.isMultiple(of: 2048) { try Task.checkCancellation() }
            let trimmedURL = ch.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let occurrence = urlOccurrences[trimmedURL, default: 0]
            urlOccurrences[trimmedURL] = occurrence + 1
            rows.append(DBM3UChannel(
                id: stableChannelID(playlistId: pid, url: ch.url, fallbackIndex: index, occurrence: occurrence),
                playlistId: pid,
                name: ch.name,
                url: ch.url,
                tvgId: ch.tvgId,
                tvgName: ch.tvgName,
                tvgLogo: ch.tvgLogo,
                tvgCountry: ch.tvgCountry,
                groupTitle: ch.groupTitle,
                userAgent: ch.userAgent,
                sortIndex: index,
                catchup: ch.catchup,
                catchupSource: ch.catchupSource,
                catchupDays: ch.catchupDays
            ))
        }
        return rows
    }

    /// Deterministik kanal ID üretimi: reimport sonrası aynı URL aynı ID'yi alır.
    /// URL boşsa fallback olarak sortIndex kullanılır (nadir durum, ama güvence).
    /// `occurrence`: aynı URL'nin kaçıncı tekrarı (0 = ilk). İlk geçiş eski formatla
    /// aynı kimliği üretir; tekrarlar `#n` son ekiyle ayrışır ve playlist sırası
    /// değişmedikçe reimport'ta da aynı kimliği alır.
    /// `nonisolated`: called for every channel from `makeRows`, off the main actor.
    nonisolated static func stableChannelID(playlistId: UUID, url: String, fallbackIndex: Int = 0, occurrence: Int = 0) -> String {
        var key: String
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            key = "\(playlistId.uuidString):__idx:\(fallbackIndex)"
        } else {
            key = "\(playlistId.uuidString):\(trimmed)"
        }
        if occurrence > 0 {
            key += "#\(occurrence)"
        }
        let data = Data(key.utf8)
        let digest = SHA256.hash(data: data)
        // Lowercase hex through a table. `String(format:)` per byte gave the same
        // text but cost seconds on a large list. The output must stay identical:
        // favourites and watch history are keyed by these ids.
        var hex = [UInt8]()
        hex.reserveCapacity(SHA256.byteCount * 2)
        for byte in digest {
            hex.append(hexDigits[Int(byte >> 4)])
            hex.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: hex, as: UTF8.self)
    }

    nonisolated private static let hexDigits = Array("0123456789abcdef".utf8)
}
