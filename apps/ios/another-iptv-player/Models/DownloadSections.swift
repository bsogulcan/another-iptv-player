import Foundation

/// The list as the screen shows it: one section per unfinished status, the
/// finished films, then the finished episodes grouped by series.
nonisolated struct DownloadSections: Equatable {
    struct EpisodeGroup: Equatable, Identifiable {
        struct ID: Hashable {
            let seriesID: String?
            let title: String
        }
        let id: ID
        var title: String { id.title }
        let episodes: [DBDownloadedItem]
    }

    var inProgress: [DBDownloadedItem] = []
    /// Kuyruk `createdAt` artan sırayla gösterilir — sıradaki (en eski) en üstte.
    /// `AllDownloadsRequest` varsayılan olarak desc döner, burada özellikle ters çeviriyoruz.
    var queued: [DBDownloadedItem] = []
    var failed: [DBDownloadedItem] = []
    var completedMovies: [DBDownloadedItem] = []
    /// The title also groups older downloads that have no series ID.
    var completedEpisodeGroups: [EpisodeGroup] = []

    var isEmpty: Bool {
        inProgress.isEmpty && queued.isEmpty && failed.isEmpty
            && completedMovies.isEmpty && completedEpisodeGroups.isEmpty
    }

    /// Filters and splits the list in one pass. The body runs again for every
    /// published percent of a running download, so the search match is done once
    /// per item here instead of once per section.
    static func make(from items: [DBDownloadedItem], matching search: String) -> Self {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = q.isEmpty ? nil : CatalogTextSearch.Query(q)
        var sections = Self()
        var episodes: [EpisodeGroup.ID: [DBDownloadedItem]] = [:]
        for item in items {
            if let query, !query.matches(item.title), !query.matches(item.secondaryTitle ?? "") { continue }
            switch item.downloadStatus {
            case .downloading: sections.inProgress.append(item)
            case .queued: sections.queued.append(item)
            case .failed: sections.failed.append(item)
            case .completed:
                if item.type == "vod" {
                    sections.completedMovies.append(item)
                } else if item.type == "episode" {
                    let name = item.secondaryTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = EpisodeGroup.ID(seriesID: item.seriesId, title: name.flatMap { $0.isEmpty ? nil : $0 } ?? item.seriesId ?? "—")
                    episodes[key, default: []].append(item)
                }
            }
        }
        sections.queued.sort { $0.createdAt < $1.createdAt }
        sections.completedEpisodeGroups = episodes
            .map { key, items in
                let sorted = items.sorted { lhs, rhs in
                    let ls = lhs.seasonNumber ?? 0, rs = rhs.seasonNumber ?? 0
                    if ls != rs { return ls < rs }
                    return (lhs.episodeNumber ?? 0) < (rhs.episodeNumber ?? 0)
                }
                return EpisodeGroup(id: key, episodes: sorted)
            }
            .sorted {
                let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                if order != .orderedSame { return order == .orderedAscending }
                if $0.title != $1.title { return $0.title < $1.title }
                return ($0.id.seriesID ?? "") < ($1.id.seriesID ?? "")
            }
        return sections
    }
}

enum DownloadFormatting {
    /// A file size in the app's language and the device's region.
    static func byteCount(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(AppLocale.current))
    }

    /// The stored reason of a failed download. Only the text survives the failure, so
    /// an empty or missing one falls back to the generic sentence `NetworkErrorText`
    /// uses for an error it cannot name.
    static func failureText(_ stored: String?) -> String {
        let text = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L("kit.error.generic") : text
    }
}
