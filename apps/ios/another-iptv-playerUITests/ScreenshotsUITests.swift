import XCTest

@MainActor
final class ScreenshotsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-UITests", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testTakeScreenshots() throws {
        let app = XCUIApplication()
        _ = app.wait(for: .runningForeground, timeout: 20)

        // Wait for the dashboard to appear (Live TV tab is the default).
        let liveButton = firstMatch(in: app, label: "Live TV")
        _ = liveButton.waitForExistence(timeout: 25)

        // Let posters fetch over the network (picsum.photos).
        sleep(7)
        snapshot("01-Live")

        // --- Movies ---
        tapTab(named: "Movies", in: app)
        sleep(6)
        snapshot("02-Movies")

        // Drill into the first movie poster while the Movies tab is fresh
        // and reliable. The grid card title appears as a staticText below
        // the poster image.
        let poster = app.staticTexts["Midnight Horizon"].firstMatch
        if poster.waitForExistence(timeout: 6) {
            poster.tap()
            sleep(3)
            snapshot("03-MovieDetail")

            // Open the player on the demo Big Buck Bunny clip.
            let play = firstMatch(in: app, label: "Watch Now")
            if play.waitForExistence(timeout: 5) {
                play.tap()
                // Allow the player overlay to settle and the stream to
                // start decoding before grabbing the frame.
                sleep(12)
                // Reveal controls in case they auto-hid.
                app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.45)).tap()
                sleep(1)
                snapshot("04-Player")

                // Dismiss the player overlay so we can finish the rest of
                // the tab walkthrough.
                app.coordinate(withNormalizedOffset: .init(dx: 0.04, dy: 0.06)).tap()
                sleep(2)
                // Pop back to the Movies tab root.
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists { backButton.tap() }
                sleep(2)
            }
        }

        // --- Series ---
        tapTab(named: "Series", in: app)
        sleep(5)
        snapshot("05-Series")

        // --- Settings ---
        tapTab(named: "Settings", in: app)
        sleep(2)
        snapshot("06-Settings")
    }

    // MARK: - Helpers

    private func firstMatch(in app: XCUIApplication, label: String) -> XCUIElement {
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

    private func tapTab(named label: String, in app: XCUIApplication) {
        let el = firstMatch(in: app, label: label)
        if el.waitForExistence(timeout: 6), el.isHittable {
            el.tap()
        }
    }
}
