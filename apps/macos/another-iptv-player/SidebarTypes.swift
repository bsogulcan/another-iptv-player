import SwiftUI

// MARK: - Sidebar selection model

enum PlaylistSection: Hashable {
    case live, movies, series   // Xtream
    case channels               // M3U (Faz 4'te direkt kategorilerle değiştirilecek)
    case favorites
}

enum SidebarSelection: Hashable {
    case empty
    /// Üst seviye "App" section: global ayarlar.
    case appSettings
    /// Üst seviye "App" section: aktif playlist'in indirmeleri.
    case appDownloads
    /// Üst seviye "App" section: aktif playlist'in izleme geçmişi.
    case appHistory
    /// Üst seviye "App" section: aktif playlist'in çok tipli arama ekranı.
    case appSearch
    case playlist(UUID)
    case section(UUID, PlaylistSection)
    case category(UUID, PlaylistSection, String)
    /// (playlistId, section, categoryId, itemId) — itemId Live/VOD/Series için stream/series id'sinin string'i,
    /// M3U için DBM3UChannel.id (zaten String).
    case item(UUID, PlaylistSection, String, String)
    /// Series altındaki sezon. (playlistId, seriesId, seasonId)
    case season(UUID, Int, String)
    /// Series altındaki bölüm. (playlistId, seriesId, seasonId, episodeId)
    case episode(UUID, Int, String, String)
    /// Bir section'ın "Son eklenenler" sanal kategorisi (Movies/Series için).
    /// Sidebar'da row'u yok ama detail panel'de bir sayfa olarak hosted edilir.
    case recentlyAdded(UUID, PlaylistSection)
    /// Bir playlist'in ayarlar sayfası (iOS PlaylistSettingsView / M3UPlaylistSettingsView).
    /// Sidebar'da expanded playlist altında Favorites'in yanında "Settings" satırı olarak görünür.
    case playlistSettings(UUID)
}

struct CategoryExpansionKey: Hashable {
    let playlistId: UUID
    let section: PlaylistSection
    let categoryId: String
}

struct SeriesItemExpansionKey: Hashable {
    let playlistId: UUID
    let seriesId: Int
}

struct SeasonExpansionKey: Hashable {
    let playlistId: UUID
    let seriesId: Int
    let seasonId: String
}

// MARK: - Sidebar-driven kategori seçimi
//
// Detail panel içindeki shelf row'ları (LiveCategoryShelfRow vs.) kategori başlıklarını
// `NavigationLink` ile push ediyordu. Yeni mimaride sidebar 'tek doğru' kaynak olduğu için
// shelf'teki kategori tıklaması sidebar'daki selection'a yansımalı (ve disclosure auto-expand
// olmalı). Bu environment value, var olduğunda shelf row'ları NavigationLink yerine Button
// olarak render edip callback üzerinden ContentView'a haber verir.
struct SidebarCategorySelector {
    let select: (PlaylistSection, String) -> Void
    /// Generic navigasyon — kategori dışı (item, recentlyAdded vb.) durumlar için.
    /// Shelf row'larda card NavigationLink'leri yerine Button + bu callback kullanır;
    /// detail panel'in iç NavigationStack'ine push olmaz, duplicate back button önlenir.
    let navigate: (SidebarSelection) -> Void
}

private struct SidebarCategorySelectorKey: EnvironmentKey {
    static let defaultValue: SidebarCategorySelector? = nil
}

extension EnvironmentValues {
    var sidebarCategorySelector: SidebarCategorySelector? {
        get { self[SidebarCategorySelectorKey.self] }
        set { self[SidebarCategorySelectorKey.self] = newValue }
    }
}
