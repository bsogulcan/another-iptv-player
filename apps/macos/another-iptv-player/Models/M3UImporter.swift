import Foundation
import GRDB
import CryptoKit

/// M3U kanallarını veritabanına yazan tek kapı. Hem ekleme hem yenileme akışı aynı yolu kullanır.
///
/// Tüm işlem GRDB'nin write kuyruğunda tek transaction'da yapılır:
/// - Playlist (opsiyonel güncelleme ile) kaydedilir.
/// - Eski `m3uChannel` kayıtları silinir.
/// - Yeni kanallar `sortIndex`'e göre batch yazılır.
///
/// Kanal ID'si **deterministik** (SHA256 of `playlistId:url`). Reimport sonrası aynı URL aynı ID'yi
/// alır, böylece favoriler ve izleme geçmişi korunur.
enum M3UImporter {

    /// Playlist + kanallar için tam yenileme. Eski kayıtları siler, yenilerini yazar.
    ///
    /// - Parameter clearServerURL: Yerel dosya import'unda playlist URL'i boşaltılır (refresh tekrar dosya ister).
    static func replace(
        playlist: Playlist,
        channels: [ParsedM3UChannel],
        epgURL: String?,
        clearServerURL: Bool = false
    ) async throws {
        var updated = playlist
        updated.m3uEpgURL = epgURL
        if clearServerURL { updated.serverURL = "" }

        let pid = playlist.id
        try await AppDatabase.shared.write { db in
            try updated.save(db)
            try db.execute(sql: "DELETE FROM m3uChannel WHERE playlistId = ?", arguments: [pid])
            // Aynı (playlist, url) için aynı id üretirken hash çarpışmalarını engellemek için
            // sortIndex de fark gözetilmek istenirse hash girdisine eklenebilir; şu an URL yeterli.
            for (index, ch) in channels.enumerated() {
                let row = DBM3UChannel(
                    id: stableChannelID(playlistId: pid, url: ch.url, fallbackIndex: index),
                    playlistId: pid,
                    name: ch.name,
                    url: ch.url,
                    tvgId: ch.tvgId,
                    tvgName: ch.tvgName,
                    tvgLogo: ch.tvgLogo,
                    tvgCountry: ch.tvgCountry,
                    groupTitle: ch.groupTitle,
                    userAgent: ch.userAgent,
                    sortIndex: index
                )
                // Aynı URL birden fazla geçerse INSERT OR REPLACE — sonuncusu kalır.
                try row.save(db)
            }
        }
    }

    /// Deterministik kanal ID üretimi: reimport sonrası aynı URL aynı ID'yi alır.
    /// URL boşsa fallback olarak sortIndex kullanılır (nadir durum, ama güvence).
    static func stableChannelID(playlistId: UUID, url: String, fallbackIndex: Int = 0) -> String {
        let key: String
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            key = "\(playlistId.uuidString):__idx:\(fallbackIndex)"
        } else {
            key = "\(playlistId.uuidString):\(trimmed)"
        }
        let data = Data(key.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
