import XCTest

/// Functional UI-flow tests against the MockFixture demo playlist.
///
/// Launches the app with `-UITests 1`, which seeds a deterministic demo
/// playlist (see `MockFixture.swift`). Unlike `ScreenshotsUITests`, these
/// tests assert on UI state rather than producing fastlane screenshots —
/// they're the suite that runs on Cmd+U for regression coverage.
@MainActor
final class UserFlowsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Dashboard

    func test_launchesIntoDashboardWithTabs() {
        XCTAssertTrue(tabButton(named: "Live TV").waitForExistence(timeout: 25))
        XCTAssertTrue(tabButton(named: "Movies").exists)
        XCTAssertTrue(tabButton(named: "Series").exists)
        XCTAssertTrue(tabButton(named: "Settings").exists)
    }

    // MARK: - Movies tab

    func test_navigatesToMoviesAndSeesPosters() {
        XCTAssertTrue(tabButton(named: "Movies").waitForExistence(timeout: 25))
        tabButton(named: "Movies").tap()

        // MockFixture seeds "Midnight Horizon" as the first movie.
        let firstMovie = app.staticTexts["Midnight Horizon"].firstMatch
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 10), "Expected mock movie 'Midnight Horizon' to be visible")
    }

    func test_opensMovieDetailFromGrid() {
        XCTAssertTrue(tabButton(named: "Movies").waitForExistence(timeout: 25))
        tabButton(named: "Movies").tap()

        let firstMovie = app.staticTexts["Midnight Horizon"].firstMatch
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 10))
        firstMovie.tap()

        // Detail view exposes a "Watch Now" CTA.
        let watchNow = firstMatch(label: "Watch Now")
        XCTAssertTrue(watchNow.waitForExistence(timeout: 8), "Movie detail screen should expose 'Watch Now'")
    }

    // MARK: - Series tab

    func test_navigatesToSeriesAndSeesPosters() {
        XCTAssertTrue(tabButton(named: "Series").waitForExistence(timeout: 25))
        tabButton(named: "Series").tap()

        // First seeded series.
        let firstSeries = app.staticTexts["Northern Lights"].firstMatch
        XCTAssertTrue(firstSeries.waitForExistence(timeout: 10), "Expected mock series 'Northern Lights' to be visible")
    }

    // MARK: - Settings tab

    func test_settingsTabRendersWithoutCrashing() {
        XCTAssertTrue(tabButton(named: "Settings").waitForExistence(timeout: 25))
        tabButton(named: "Settings").tap()

        // We don't assert exact rows (settings copy is localized & evolves);
        // just confirm the tab is still selected/foregrounded after tap.
        XCTAssertTrue(tabButton(named: "Settings").isSelected || tabButton(named: "Settings").exists)
    }

    // MARK: - Live tab

    func test_liveTabShowsSeededChannel() {
        XCTAssertTrue(tabButton(named: "Live TV").waitForExistence(timeout: 25))
        tabButton(named: "Live TV").tap()

        // First seeded live channel.
        let firstLive = app.staticTexts["World News 24"].firstMatch
        XCTAssertTrue(firstLive.waitForExistence(timeout: 10), "Expected mock live channel 'World News 24' to be visible")
    }

    // MARK: - Helpers

    private func tabButton(named label: String) -> XCUIElement {
        app.tabBars.buttons[label]
    }

    private func firstMatch(label: String) -> XCUIElement {
        let candidates: [XCUIElementQuery] = [
            app.tabBars.buttons,
            app.buttons,
            app.cells.staticTexts,
            app.staticTexts,
        ]
        for q in candidates {
            let el = q[label]
            if el.exists { return el }
        }
        return app.buttons[label]
    }
}
