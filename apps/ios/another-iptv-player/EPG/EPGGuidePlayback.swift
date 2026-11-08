import Foundation

enum EPGGuidePlayback {
    /// The live catalog as the Live tab lists it: categories the user hid are left
    /// out, so channel up/down and the channel panel cannot walk into them.
    static func xtreamLiveQueue(
        playlistId: UUID, including stream: DBLiveStream
    ) -> (queue: [DBLiveStream], sections: [LiveChannelCategorySection]) {
        let hidden = HiddenCategoryStore.shared.hiddenIds(playlistId: playlistId, type: "live")
        return visible(LiveChannelCategorySection.xtreamLiveQueue(), hiding: hidden, including: stream)
    }

    /// `live` without the sections whose id is in `hidden`. The section holding
    /// `stream` always stays: the channel being started must have a place in its
    /// own queue, whatever the hidden set says by the time it is tapped.
    static func visible(
        _ live: (queue: [DBLiveStream], sections: [LiveChannelCategorySection]),
        hiding hidden: Set<String>,
        including stream: DBLiveStream
    ) -> (queue: [DBLiveStream], sections: [LiveChannelCategorySection]) {
        guard !hidden.isEmpty else { return live }
        let sections = live.sections.filter { section in
            !hidden.contains(section.id) || section.streams.contains { $0.streamId == stream.streamId }
        }
        guard sections.count != live.sections.count else { return live }
        return (sections.flatMap(\.streams), sections)
    }
}
