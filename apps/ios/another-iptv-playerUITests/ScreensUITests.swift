import XCTest

/// Screen-by-screen smoke coverage: open every reachable screen and assert
/// a defining element renders. Complements `UserFlowsUITests` which exercises
/// the critical journeys.
///
/// All tests share the MockFixture demo playlist via `-UITests 1`.
@MainActor
final class ScreensUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        XCTAssertTrue(tabButton("Live TV").waitForExistence(timeout: 25), "Dashboard did not appear")
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Search tab

    func test_searchTab_opensSearchField() {
        tabButton("Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "Search field should appear on Search tab")
    }

    func test_searchTab_typingQueryShowsResults() {
        tabButton("Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("Midnight")

        // The mock catalog has "Midnight Horizon" — the result row should appear.
        let result = app.staticTexts["Midnight Horizon"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 6), "Search results should include the mock movie")
    }

    // MARK: - Favorites screen

    func test_moviesTab_starToolbarButton_opensFavoritesScreen() {
        tabButton("Movies").tap()
        // Toolbar star button has no localized label — locate by symbol-derived identifier.
        let starButton = app.navigationBars.buttons["star.fill"].firstMatch
        XCTAssertTrue(starButton.waitForExistence(timeout: 6), "Star toolbar button should be present")
        starButton.tap()
        XCTAssertTrue(
            app.navigationBars["Favorites"].waitForExistence(timeout: 6),
            "Favorites screen should appear after tapping star"
        )
    }

    // MARK: - Category picker sheet

    func test_moviesTab_categoryPickerButton_opensSheet() {
        tabButton("Movies").tap()
        let pickerButton = app.buttons["Jump to category"]
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 8), "'Jump to category' button should exist")
        pickerButton.tap()
        // The sheet header echoes the same string in CategoryPickerSheet.
        XCTAssertTrue(
            app.staticTexts["Jump to category"].waitForExistence(timeout: 4) ||
            app.otherElements["Jump to category"].waitForExistence(timeout: 2),
            "Category picker sheet should present"
        )
    }

    // MARK: - Series detail navigation

    func test_seriesTab_tappingPoster_opensDetail() {
        tabButton("Series").tap()
        // Poster accessibility label combines rating + name: "8.5, Northern Lights".
        let firstSeries = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Northern Lights")
        ).firstMatch
        XCTAssertTrue(firstSeries.waitForExistence(timeout: 10))
        firstSeries.tap()
        // Mock series has `seasonsLoaded: false` so detail fires a network fetch that
        // will fail against example.com — verify we're on the detail screen by the
        // presence of a back button in the nav bar (push navigation completed).
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 6) && backButton.isHittable,
            "After tapping series poster, a back button should appear in the nav bar"
        )
    }

    // MARK: - Movie detail back navigation

    func test_movieDetail_backNavigationReturnsToGrid() {
        tabButton("Movies").tap()
        let firstMovie = app.staticTexts["Midnight Horizon"].firstMatch
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 10))
        firstMovie.tap()

        let watchNow = app.buttons["Watch Now"].firstMatch
        XCTAssertTrue(watchNow.waitForExistence(timeout: 8))

        // Back button is the first nav-bar leading button.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.exists)
        backButton.tap()
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 5), "Should return to Movies grid")
    }

    // MARK: - Settings sections

    func test_settingsTab_showsCoreSections() {
        tabButton("Settings").tap()
        let pred: (String) -> NSPredicate = { keyword in
            NSPredicate(format: "label CONTAINS[c] %@", keyword)
        }
        XCTAssertTrue(
            app.descendants(matching: .any).matching(pred("Downloads")).firstMatch.waitForExistence(timeout: 8),
            "Settings should expose a Downloads section/row"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(pred("Player Settings")).firstMatch.exists,
            "Settings should expose a Player Settings section"
        )
        // 'Playlist Information' lives below the fold — scroll to surface it.
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(pred("Playlist Information")).firstMatch.waitForExistence(timeout: 4),
            "Settings should expose a Playlist Information section (after scroll)"
        )
    }

    func test_settingsTab_refreshAllButton_exists() {
        tabButton("Settings").tap()
        XCTAssertTrue(
            app.buttons["Re-download All Content"].waitForExistence(timeout: 6),
            "Refresh-all button should be present"
        )
    }

    func test_settingsTab_downloadsRow_opensDownloadsScreen() {
        tabButton("Settings").tap()
        // The Form row label is the same key as the section header — disambiguate.
        let downloadsRow = app.buttons["Downloads"].firstMatch
        XCTAssertTrue(downloadsRow.waitForExistence(timeout: 6))
        downloadsRow.tap()
        XCTAssertTrue(
            app.navigationBars["Downloads"].waitForExistence(timeout: 6),
            "Downloads screen should appear"
        )
    }

    // MARK: - Playlist list ("Back to playlists" flow)

    func test_settings_backToList_opensPlaylistList() {
        tabButton("Settings").tap()
        let backRow = app.buttons["Back to Playlists"]
        XCTAssertTrue(backRow.waitForExistence(timeout: 6))
        backRow.tap()
        XCTAssertTrue(
            app.navigationBars["Playlists"].waitForExistence(timeout: 6),
            "Playlist list screen should appear after 'Back to Playlists'"
        )
    }

    // MARK: - Add Playlist flow

    func test_playlistList_addButton_opensTypeSelectionSheet() {
        navigateToPlaylistList()
        // Toolbar "plus" — locate by symbol identifier.
        let plus = app.navigationBars.buttons["plus"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 6))
        plus.tap()

        // Type selection sheet header.
        XCTAssertTrue(
            app.navigationBars["Add Playlist"].waitForExistence(timeout: 4) ||
            staticText("Playlist Type").waitForExistence(timeout: 4),
            "Type selection sheet should present"
        )
    }

    func test_playlistTypeSelection_xtream_opensXtreamForm() {
        navigateToPlaylistList()
        app.navigationBars.buttons["plus"].firstMatch.tap()

        // PlaylistTypeSelection uses Button with custom row labels; the row's
        // accessibility label combines title + subtitle, so match by predicate.
        let xtreamRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Xtream Code")
        ).firstMatch
        XCTAssertTrue(xtreamRow.waitForExistence(timeout: 6))
        xtreamRow.tap()

        // Xtream form has sections "Playlist Information" / "Credentials".
        let credentialsSection = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Credentials")
        ).firstMatch
        XCTAssertTrue(
            credentialsSection.waitForExistence(timeout: 8),
            "Xtream add-playlist form should appear with a Credentials section"
        )
    }

    func test_playlistTypeSelection_m3u_opensM3UForm() {
        navigateToPlaylistList()
        app.navigationBars.buttons["plus"].firstMatch.tap()

        let m3uRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "M3U")
        ).firstMatch
        XCTAssertTrue(m3uRow.waitForExistence(timeout: 6))
        m3uRow.tap()

        // M3U form is a sheet — at minimum we should see an editable text field
        // appear after the type selection sheet dismisses.
        XCTAssertTrue(
            app.textFields.firstMatch.waitForExistence(timeout: 8),
            "M3U add-playlist form should appear with editable fields"
        )
    }

    // MARK: - Helpers

    private func tabButton(_ label: String) -> XCUIElement {
        app.tabBars.buttons[label]
    }

    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts[text]
    }

    private func navigateToPlaylistList() {
        tabButton("Settings").tap()
        let backRow = app.buttons["Back to Playlists"]
        XCTAssertTrue(backRow.waitForExistence(timeout: 6))
        backRow.tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 6))
    }
}
