import Foundation
import Testing
@testable import another_iptv_player

@Suite("M3U grid updates")
struct M3UGridContentTests {
    @Test
    func anInteriorMetadataChangeInvalidatesTheGrid() {
        let playlist = UUID()
        let original = (0..<3).map {
            DBM3UChannel(id: "\($0)", playlistId: playlist, name: "Channel \($0)", url: "https://example.invalid/\($0)")
        }
        var refreshed = original
        refreshed[1].name = "Updated channel"
        refreshed[1].tvgLogo = "https://example.invalid/new.png"
        let before = M3UGroupGridContent(items: original, contentID: .catalog(playlist, 1, ""))
        let after = M3UGroupGridContent(items: refreshed, contentID: .catalog(playlist, 2, ""))
        #expect(before != after)
    }

    @Test
    func aNewFavoriteResultInvalidatesUnchangedEndpoints() {
        let playlist = UUID()
        let original = (0..<4).map {
            DBM3UChannel(id: "\($0)", playlistId: playlist, name: "Channel \($0)", url: "https://example.invalid/\($0)")
        }
        let before = M3UGroupGridContent(items: [original[0], original[1], original[3]], contentID: .favorites(playlist, 1))
        let after = M3UGroupGridContent(items: [original[0], original[2], original[3]], contentID: .favorites(playlist, 2))
        #expect(before != after)
    }
}
