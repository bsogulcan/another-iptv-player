import Testing
import UIKit
@testable import another_iptv_player

@MainActor
struct PlayerMoreMenuTests {
    @Test func playbackUpdatesPreservePresentedElementsAndRefreshNextOpening() {
        let button = PlayerMoreMenuUIKitButton(type: .system)
        let nativeMenu = button.menu
        var builds = 0
        func menu(selected: Int, count: Int) -> UIMenu {
            builds += 1
            return UIMenu(children: (0..<count).map { index in
                UIAction(title: "Subtitle \(index)", state: index == selected ? .on : .off) { _ in }
            })
        }
        button.makeMenu = { menu(selected: 0, count: 40) }
        let presented = button.menuElementsForPresentation()
        #expect(builds == 1)

        // Mirrors updateUIView during playback, including a track discovery and
        // selection change. Neither the installed menu nor open rows may change.
        for _ in 0..<100 {
            button.makeMenu = { menu(selected: 25, count: 42) }
        }
        #expect(button.menu === nativeMenu)
        #expect(builds == 1)
        #expect(presented.count == 40)
        #expect((presented[0] as? UIAction)?.state == .on)
        #expect((presented[25] as? UIAction)?.state == .off)

        let reopened = button.menuElementsForPresentation()
        #expect(builds == 2)
        #expect(reopened.count == 42)
        #expect((reopened[0] as? UIAction)?.state == .off)
        #expect((reopened[25] as? UIAction)?.state == .on)
    }

    @Test func menuLifecycleReportsOpeningAndCancellation() throws {
        let button = PlayerMoreMenuUIKitButton(type: .system)
        let interaction = try #require(button.contextMenuInteraction)
        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil)
        var presentationChanges: [Bool] = []
        button.onPresentationChange = { presentationChanges.append($0) }
        button.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: nil)
        button.contextMenuInteraction(interaction, willEndFor: configuration, animator: nil)
        #expect(presentationChanges == [true, false])
    }
}
