import Foundation
import SwiftUI
import Testing
@testable import another_iptv_player

/// The overlay boundary between the browse screens and the player: what a continuation
/// of the same session may change, and how a title tap finds the item to show.
@Suite("Player overlay controller")
struct PlayerOverlayControllerTests {

    private let playlist = PlaylistCatalogFixture.playlist()

    private func present(_ controller: PlayerOverlayController) {
        controller.present(skipDownloadCheck: true) { EmptyView() }
    }

    // MARK: Continuation

    @Test
    func aContinuationKeepsADockedCardDocked() throws {
        let controller = PlayerOverlayController(database: .empty())
        present(controller)
        let first = try #require(controller.presentation?.id)
        controller.minimize()

        controller.replaceContent { EmptyView() }

        #expect(controller.mode == .mini)
        #expect(controller.pendingPresentation == nil)
        // A new id is what makes the mounted player adopt the new item.
        let second = try #require(controller.presentation?.id)
        #expect(second != first)
    }

    @Test
    func aContinuationKeepsAFullscreenPlayerFullscreen() {
        let controller = PlayerOverlayController(database: .empty())
        present(controller)

        controller.replaceContent { EmptyView() }

        #expect(controller.mode == .fullscreen)
        #expect(controller.presentation != nil)
    }

    @Test
    func aContinuationDoesNotReopenAClosedPlayer() {
        let controller = PlayerOverlayController(database: .empty())
        controller.replaceContent { EmptyView() }
        #expect(controller.presentation == nil)

        present(controller)
        controller.dismiss()
        controller.replaceContent { EmptyView() }
        #expect(controller.presentation == nil)
        #expect(controller.pendingPresentation == nil)
    }

    @Test
    func aContinuationTakesOverTheDismissCallback() {
        let controller = PlayerOverlayController(database: .empty())
        var closed: [String] = []
        controller.present(onDismiss: { closed.append("first") }, skipDownloadCheck: true) { EmptyView() }

        controller.replaceContent(onDismiss: { closed.append("second") }) { EmptyView() }
        controller.dismiss()

        #expect(closed == ["second"])
    }

    @Test
    func aNewPickAlwaysOpensFullscreen() {
        let controller = PlayerOverlayController(database: .empty())
        present(controller)
        controller.minimize()

        present(controller)

        #expect(controller.mode == .fullscreen)
    }

    @Test
    func expandNeedsAPresentation() {
        let controller = PlayerOverlayController(database: .empty())
        controller.mode = .mini
        controller.expand()
        #expect(controller.mode == .mini)

        present(controller)
        controller.minimize()
        controller.expand()
        #expect(controller.mode == .fullscreen)
    }

    // MARK: Detail request

    private func seededDatabase() async throws -> AppDatabase {
        let database = try await PlaylistCatalogFixture.database(with: playlist)
        let movie = PlaylistCatalogFixture.vod(7, category: nil, in: playlist)
        let series = PlaylistCatalogFixture.series(9, category: nil, in: playlist)
        try await database.write { db in
            try movie.insert(db)
            try series.insert(db)
        }
        return database
    }

    @Test
    func aMovieTitleTapAsksForTheMovie() async throws {
        let controller = PlayerOverlayController(database: try await seededDatabase())

        await controller.requestDetail(type: "vod", id: "7", playlistId: playlist.id)

        guard case .movie(let movie) = controller.detailRequest else {
            Issue.record("expected a movie request, got \(String(describing: controller.detailRequest))")
            return
        }
        #expect(movie.streamId == 7)
        #expect(movie.playlistId == playlist.id)
    }

    @Test
    func aSeriesTitleTapAsksForTheSeries() async throws {
        let controller = PlayerOverlayController(database: try await seededDatabase())

        await controller.requestDetail(type: "series", id: "9", playlistId: playlist.id)

        guard case .series(let series) = controller.detailRequest else {
            Issue.record("expected a series request, got \(String(describing: controller.detailRequest))")
            return
        }
        #expect(series.seriesId == 9)
    }

    /// The request stays until the screen that shows it takes it, and nothing that
    /// cannot be shown replaces or clears it.
    @Test
    func whatCannotBeShownLeavesTheRequestAlone() async throws {
        let controller = PlayerOverlayController(database: try await seededDatabase())

        await controller.requestDetail(type: "live", id: "7", playlistId: playlist.id)
        await controller.requestDetail(type: "vod", id: "not-a-number", playlistId: playlist.id)
        await controller.requestDetail(type: "vod", id: "8", playlistId: playlist.id)
        await controller.requestDetail(type: "vod", id: "7", playlistId: UUID())
        // The ids of the two tables are separate number spaces.
        await controller.requestDetail(type: "series", id: "7", playlistId: playlist.id)
        #expect(controller.detailRequest == nil)

        await controller.requestDetail(type: "vod", id: "7", playlistId: playlist.id)
        let pending = controller.detailRequest
        #expect(pending != nil)
        await controller.requestDetail(type: "vod", id: "8", playlistId: playlist.id)
        #expect(controller.detailRequest == pending)
    }

    // MARK: Environment

    @Test
    func theEnvironmentCarriesTheControllerWithoutSubscribing() {
        var values = EnvironmentValues()
        #expect(values.playerOverlayController == nil)
        let controller = PlayerOverlayController(database: .empty())
        values.playerOverlayController = controller
        #expect(values.playerOverlayController === controller)
        #expect(values.playerOverlayController.injected === controller)
    }
}
