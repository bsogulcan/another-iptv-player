import SwiftUI

/// Tracks the visible detail independently of how it was pushed (card or player).
/// Ownership prevents a departing page from clearing the page that replaced it.
@MainActor
final class BrowseDetailPresence {
    static let shared = BrowseDetailPresence()

    struct Item: Equatable {
        let playlistId: UUID
        let type: String
        let streamId: Int
    }

    private var visible: (owner: UUID, item: Item)?

    func show(_ item: Item, owner: UUID) {
        visible = (owner, item)
    }

    func hide(owner: UUID) {
        if visible?.owner == owner { visible = nil }
    }

    func contains(_ item: Item) -> Bool {
        visible?.item == item
    }
}

private struct BrowseDetailPresenceModifier: ViewModifier {
    let item: BrowseDetailPresence.Item
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { BrowseDetailPresence.shared.show(item, owner: owner) }
            .onDisappear { BrowseDetailPresence.shared.hide(owner: owner) }
    }
}

extension View {
    func browseDetailPresence(playlistId: UUID, type: String, streamId: Int) -> some View {
        modifier(BrowseDetailPresenceModifier(item: .init(playlistId: playlistId, type: type, streamId: streamId)))
    }
}
