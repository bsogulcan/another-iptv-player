import Foundation
import Testing
@testable import another_iptv_player

@MainActor
struct BrowseDetailPresenceTests {
    @Test func departingPageCannotClearItsReplacement() {
        let presence = BrowseDetailPresence()
        let playlistId = UUID()
        let first = BrowseDetailPresence.Item(playlistId: playlistId, type: "vod", streamId: 1)
        let second = BrowseDetailPresence.Item(playlistId: playlistId, type: "vod", streamId: 2)
        let firstOwner = UUID()
        let secondOwner = UUID()
        presence.show(first, owner: firstOwner)
        #expect(presence.contains(first))
        presence.show(second, owner: secondOwner)
        presence.hide(owner: firstOwner)
        #expect(presence.contains(second))
        #expect(!presence.contains(first))
        #expect(!presence.contains(.init(playlistId: playlistId, type: "series", streamId: 2)))
        #expect(!presence.contains(.init(playlistId: UUID(), type: "vod", streamId: 2)))
        presence.hide(owner: secondOwner)
        #expect(!presence.contains(second))
    }
}
