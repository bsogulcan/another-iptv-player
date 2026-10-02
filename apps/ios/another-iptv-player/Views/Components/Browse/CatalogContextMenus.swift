import SwiftUI
import GRDB

// Items for the context menus of catalog cards and shelf headers.
//
// The `menuItems` closure of `.contextMenu` is not escaping: it runs with the body
// of every card, in a shelf or a grid of thousands. So each item here is a view
// whose initialiser only stores a few values. Reading state, building labels and
// everything else happens in `body`.
//
// Attach the menu to the button or link of a card, outside its label, and never
// read a store in the card itself for it: a card that observes the favourites
// re-renders with every toggle, together with all the others a lazy stack keeps.
//
// None of these items offers Share or Copy Link: Xtream stream URLs carry the
// account's credentials.

/// "Add to Favorites" / "Remove from Favorites" for a channel, movie or series of an
/// Xtream playlist. `type` is "live", "vod" or "series", as `DBFavorite` stores it.
///
/// The state comes from `XtreamFavoriteStore`, which the dashboard has to point at
/// the active playlist (`track(playlistId:)`). The tap writes the state the label
/// promised, so a label and its action cannot disagree.
struct FavoriteMenuButton: View {
    private let streamId: Int
    private let type: String
    private let playlistId: UUID

    @ObservedObject private var store = XtreamFavoriteStore.shared

    init(streamId: Int, type: String, playlistId: UUID) {
        self.streamId = streamId
        self.type = type
        self.playlistId = playlistId
    }

    var body: some View {
        let state = store.favoriteState(streamId, type: type, playlistId: playlistId)
        let isFavorite = state ?? false
        Button {
            Task {
                if state == nil {
                    // The store follows another playlist or has not read this one
                    // yet. The label could not know, so the database decides.
                    await store.toggle(streamId, type: type, playlistId: playlistId)
                } else {
                    await store.setFavorite(!isFavorite, streamId: streamId, type: type, playlistId: playlistId)
                }
            }
        } label: {
            Label(
                isFavorite ? L("favorites.remove") : L("favorites.add"),
                systemImage: isFavorite ? "star.slash" : "star"
            )
        }
    }
}

/// "Hide Category" for a shelf header. `type` is the content type of the category
/// ("live", "vod", "series", "m3u"). The category comes back through the category
/// picker, where hidden ones are listed.
struct HideCategoryMenuButton: View {
    private let categoryId: String
    private let type: String
    private let playlistId: UUID

    init(categoryId: String, type: String, playlistId: UUID) {
        self.categoryId = categoryId
        self.type = type
        self.playlistId = playlistId
    }

    var body: some View {
        Button {
            HiddenCategoryStore.shared.setHidden(true, playlistId: playlistId, type: type, categoryId: categoryId)
        } label: {
            Label(L("kit.menu.hide_category"), systemImage: "eye.slash")
        }
    }
}

/// "Remove from History" for a Continue Watching or history card: deletes that one
/// row, and with it the resume position of the item.
///
/// Not styled as destructive, like "Remove from Up Next" in the TV app: the item
/// itself stays in the catalog and can be watched again.
struct RemoveFromHistoryMenuButton: View {
    /// Only the key is kept: the row itself is a dozen fields that would be copied
    /// for every card.
    private let historyId: String

    @Environment(\.appDatabase) private var appDatabase

    init(item: DBWatchHistory) {
        self.historyId = item.id
    }

    var body: some View {
        Button {
            let database = appDatabase
            let id = historyId
            Task {
                do {
                    try await WatchHistoryWriter.remove(id: id, in: database)
                } catch {
                    Log.error("History", "remove failed: \(error)")
                }
            }
        } label: {
            Label(L("kit.menu.remove_from_history"), systemImage: "minus.circle")
        }
    }
}

/// "Play" as the first item of a card's menu. The card supplies what a tap on it
/// does.
struct PlayMenuButton: View {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(L("movie.play"), systemImage: "play")
        }
    }
}

/// "Schedule" for a live channel: opens the channel's programme list. Offer it only
/// when the playlist has a guide.
struct ScheduleMenuButton: View {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(L("kit.menu.schedule"), systemImage: "calendar")
        }
    }
}

extension View {
    /// Gives the platter the system lifts for a context menu the rounded shape of
    /// the card. The lift shows the card as it is on screen (no custom preview), so
    /// nothing is loaded or decoded for it.
    func cardContextMenuShape(cornerRadius: CGFloat) -> some View {
        contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Deletes single rows of the watch history.
///
/// `nonisolated`: the statement runs on the database's writer queue.
nonisolated enum WatchHistoryWriter {
    /// Removes one history row by its id. A row that is already gone is not an error.
    static func remove(id: String, in database: AppDatabase) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM watchHistory WHERE id = ?", arguments: [id])
        }
    }
}
