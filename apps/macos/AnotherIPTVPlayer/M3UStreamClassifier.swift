import Foundation

enum M3UStreamClassifier {
  struct Classification {
    /// `PlayerView.isLiveStream`'e verilir — false ise seek bar görünür, resume çalışır.
    let isLive: Bool
    /// `PlayerView.type` — watch history için ("live" | "vod").
    let playbackType: String
    /// URL'de belirgin bir dosya uzantısı varsa (mp4/mkv/...) player'a bilgi olarak iletilir.
    let containerExtension: String?
  }

  /// VOD göstergeleri: dosya uzantıları ve Xtream tarzı yollar.
  nonisolated private static let vodExtensions: Set<String> = [
    "mp4", "mkv", "avi", "mov", "webm", "flv", "m4v", "wmv", "3gp",
  ]
  nonisolated private static let vodPathHints: [String] = [
    "/movie/", "/movies/", "/series/", "/vod/", "/films/", "/film/",
  ]

  nonisolated static func classify(url: URL, groupTitle: String?) -> Classification {
    let path = url.path.lowercased()
    let ext = url.pathExtension.lowercased()

    if vodPathHints.contains(where: path.contains) {
      return Classification(
        isLive: false, playbackType: "vod", containerExtension: ext.isEmpty ? nil : ext)
    }
    if vodExtensions.contains(ext) {
      return Classification(isLive: false, playbackType: "vod", containerExtension: ext)
    }
    // Bilinen live indikatörleri veya uzantısız Xtream-style: canlı varsay.
    return Classification(
      isLive: true, playbackType: "live", containerExtension: ext.isEmpty ? nil : ext)
  }
}
