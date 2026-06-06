import Foundation

/// Metadata shown in Control Center, Lock Screen, and device media surfaces (Now Playing).
struct PlaybackPresentation: Equatable {
    var title: String
    /// Örn. dizi adı, kanal grubu veya tür.
    var subtitle: String?
    var artworkURL: URL?
    /// Canlı yayın: süre/ilerleme çubuğu sistemde farklı işlenir.
    var isLive: Bool = false
}
