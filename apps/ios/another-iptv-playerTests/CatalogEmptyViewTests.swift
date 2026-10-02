import Foundation
import Testing
@testable import another_iptv_player

/// What each kind of `CatalogEmptyView` shows.
@Suite("Catalog empty view")
struct CatalogEmptyViewTests {

    @Test
    func aSearchWithoutResultsUsesTheSharedTitleAndHint() {
        let content = CatalogEmptyView.content(for: .noSearchResults)

        #expect(content.title == L("favorites.empty.no_result.title"))
        #expect(content.systemImage == "magnifyingglass")
        #expect(content.description == L("category_picker.not_found.message"))
    }

    @Test
    func noCategoriesKeepsTheCallersSymbol() {
        let content = CatalogEmptyView.content(for: .noCategories(systemImage: "film"))

        #expect(content.title == L("category_picker.not_found.title"))
        #expect(content.systemImage == "film")
        #expect(content.description == nil)
    }

    @Test
    func noItemsShowsTheCallersTitleAsAHeadline() {
        let content = CatalogEmptyView.content(for: .noItems(title: "No movies found.", systemImage: "film"))

        #expect(content.title == "No movies found")
        #expect(content.systemImage == "film")
        #expect(content.description == nil)
    }

    @Test
    func aMessageKeepsItsDescriptionAsWritten() {
        let content = CatalogEmptyView.content(
            for: .message(title: "No favorite channels yet.", systemImage: "tv", description: "Add one from a channel's menu.")
        )

        #expect(content.title == "No favorite channels yet")
        #expect(content.description == "Add one from a channel's menu.")
        #expect(CatalogEmptyView.content(for: .message(title: "Empty", systemImage: "tv", description: nil)).description == nil)
    }

    /// The reused strings end in the full stop of their language.
    @Test(arguments: [
        ("No movies found.", "No movies found"),
        ("Hiç film bulunamadı.", "Hiç film bulunamadı"),
        ("未找到电影。", "未找到电影"),
        ("कोई फ़िल्म नहीं मिली।", "कोई फ़िल्म नहीं मिली"),
        ("لم يتم العثور على أفلام.", "لم يتم العثور على أفلام"),
        ("No history", "No history"),
        ("  Padded.  ", "Padded"),
        ("Loading...", "Loading..."),
        ("What now?", "What now?"),
        ("", ""),
        (".", ""),
    ])
    func headlineDropsTheFullStop(text: String, expected: String) {
        #expect(CatalogEmptyView.headline(text) == expected)
    }

    @Test
    func aFullStopInsideTheTitleStays() {
        #expect(CatalogEmptyView.headline("Vol. 2 is missing.") == "Vol. 2 is missing")
        #expect(CatalogEmptyView.headline("v1.5") == "v1.5")
    }
}
