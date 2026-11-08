import Foundation

struct LiveChannelCategorySection: Identifiable, Equatable {
    let id: String
    let title: String
    let streams: [DBLiveStream]
}

extension LiveChannelCategorySection {
    /// Full live queue + per-category sections for the current Xtream playlist.
    /// Players opened outside the main channel list (EPG guide, programme sheet)
    /// use this so prev/next channel and the channel side panel keep working instead
    /// of being disabled by a single-item queue.
    @MainActor
    static func xtreamLiveQueue() -> (queue: [DBLiveStream], sections: [LiveChannelCategorySection]) {
        let store = PlaylistContentStore.shared
        // One walk over the catalog fills both results; mapping the sections first and
        // flattening them afterwards visited every channel twice on each open.
        var queue: [DBLiveStream] = []
        queue.reserveCapacity(store.liveStreams.count)
        var sections: [LiveChannelCategorySection] = []
        sections.reserveCapacity(store.liveCategories.count)
        for cat in store.liveCategories {
            guard let items = store.liveStreamsByCategoryId[cat.id], !items.isEmpty else { continue }
            var streams: [DBLiveStream] = []
            streams.reserveCapacity(items.count)
            for item in items {
                streams.append(item.stream)
                queue.append(item.stream)
            }
            sections.append(LiveChannelCategorySection(id: cat.id, title: cat.name, streams: streams))
        }
        return (queue, sections)
    }
}
