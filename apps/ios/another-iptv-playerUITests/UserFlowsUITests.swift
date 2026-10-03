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

    // MARK: - Player
    //
    // These tests play the demo stream (`MockFixture.demoPlaybackURL`, a public HLS test
    // stream), so they need network access. Only the play / pause test waits for the
    // stream itself; the others exercise the player's own UI, which is there from the
    // moment the player is presented.

    func test_player_opensFromMovieDetail_tapTogglesControls_playPauseToggles() {
        openMoviePlayer()

        // A tap on the video hides the visible controls, a second one brings them back.
        showPlayerChrome()
        tapVideoSurface()
        XCTAssertTrue(
            playerCloseButton.waitForNonExistence(timeout: 3),
            "A tap on the video should hide the visible controls"
        )
        tapVideoSurface()
        XCTAssertTrue(
            playerCloseButton.waitForExistence(timeout: 3),
            "A tap on the video should show the hidden controls"
        )
        chromeShownAt = Date()
        XCTAssertTrue(playerPlayPauseButton.exists, "The transport button should come back with the controls")

        waitForPlaybackToStart()

        // The timeline follows the playing stream.
        let positionAtStart = timelineValue()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertNotEqual(
            timelineValue(), positionAtStart,
            "The timeline should advance while the stream plays"
        )

        showPlayerChrome()
        playerPlayPauseButton.tap()
        XCTAssertTrue(
            waitForLabel("Play", of: playerPlayPauseButton, timeout: 5),
            "Tapping the transport button while playing should pause"
        )
        // Paused playback keeps its controls up, so the button and the timeline are
        // still there, and the position stands still.
        Thread.sleep(forTimeInterval: 1)
        let positionWhilePaused = timelineValue(refreshingChrome: false)
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(playerCloseButton.exists, "Paused playback should keep its controls on screen")
        XCTAssertEqual(
            timelineValue(refreshingChrome: false), positionWhilePaused,
            "The timeline should stand still while playback is paused"
        )

        playerPlayPauseButton.tap()
        XCTAssertTrue(
            waitForLabel("Pause", of: playerPlayPauseButton, timeout: 10),
            "Tapping the transport button while paused should resume"
        )
    }

    func test_player_pullDownFromMiddle_minimizesToCard_tapExpands() {
        openMoviePlayer()
        waitForPlaybackToStart()

        // The normal viewing state: the stream plays and the controls are hidden.
        showPlayerChrome()
        tapVideoSurface()
        XCTAssertTrue(playerCloseButton.waitForNonExistence(timeout: 3))
        pullDownFromMiddleOfScreen()
        assertMiniCardIsDocked()
        XCTAssertTrue(
            waitForLabel("Pause", of: miniPlayerPlayPauseButton, timeout: 5),
            "Minimizing should not interrupt playback"
        )

        // The catalog under the card is usable.
        let seriesTab = tabButton(named: "Series")
        XCTAssertTrue(seriesTab.waitForExistence(timeout: 5), "The tab bar should be reachable next to the mini card")
        XCTAssertTrue(seriesTab.isHittable, "The tab bar should take taps next to the mini card")
        seriesTab.tap()
        XCTAssertTrue(
            app.staticTexts["Northern Lights"].firstMatch.waitForExistence(timeout: 10),
            "Switching tabs should work while the mini card is docked"
        )
        XCTAssertTrue(miniPlayerCard.exists, "The mini card should survive a tab switch")

        // A tap on the card brings the fullscreen player back, with its controls.
        miniPlayerCard.tap()
        XCTAssertTrue(
            playerCloseButton.waitForExistence(timeout: 6),
            "Tapping the mini card should return to the fullscreen player with its controls"
        )
        chromeShownAt = Date()
        XCTAssertTrue(
            waitForLabel("Pause", of: playerPlayPauseButton, timeout: 5),
            "The fullscreen transport should be back after the expand, with playback still running"
        )
        XCTAssertTrue(
            miniPlayerCard.waitForNonExistence(timeout: 4),
            "The mini card chrome should be gone once the player is fullscreen"
        )
    }

    func test_player_pullDownStartingOnTransport_minimizesWithoutPausing() {
        openMoviePlayer()
        waitForPlaybackToStart()

        // With the controls visible, a drag from the middle of the screen starts on the
        // play / pause button. It is a drag, not a tap: playback has to go on.
        showPlayerChrome()
        pullDownFromMiddleOfScreen()
        assertMiniCardIsDocked()
        XCTAssertTrue(
            waitForLabel("Pause", of: miniPlayerPlayPauseButton, timeout: 5),
            "A pull-down that starts on the play / pause button should minimize without pausing"
        )

        // The card's own close button ends playback and removes the card.
        miniPlayerCloseButton.tap()
        XCTAssertTrue(
            miniPlayerCard.waitForNonExistence(timeout: 5),
            "The mini card's close button should remove the player"
        )
        XCTAssertFalse(playerSurface.exists, "No player should be left after closing the mini card")
    }

    func test_player_closeButton_removesPlayerAndCatalogIsInteractive() {
        openMoviePlayer()

        showPlayerChrome()
        playerCloseButton.tap()

        XCTAssertTrue(
            playerCloseButton.waitForNonExistence(timeout: 5),
            "The close button should remove the fullscreen player"
        )
        XCTAssertTrue(playerSurface.waitForNonExistence(timeout: 3), "The player surface should be gone after close")
        XCTAssertFalse(miniPlayerCard.exists, "Close must not leave a mini card behind")

        // Back on the movie detail the player was opened from, and it takes taps.
        XCTAssertTrue(tabButton(named: "Movies").waitForExistence(timeout: 5), "The tab bar should be back after close")
        XCTAssertTrue(tabButton(named: "Movies").isHittable)
        let watchButton = moviePlayButton
        XCTAssertTrue(watchButton.waitForExistence(timeout: 5), "The movie detail should be visible again after close")
        XCTAssertTrue(watchButton.isHittable, "The movie detail should take taps after close")

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.exists)
        backButton.tap()
        XCTAssertTrue(
            app.staticTexts["Midnight Horizon"].firstMatch.waitForExistence(timeout: 5),
            "The catalog should navigate normally after the player closed"
        )
        tabButton(named: "Series").tap()
        XCTAssertTrue(
            app.staticTexts["Northern Lights"].firstMatch.waitForExistence(timeout: 10),
            "The tab bar should switch tabs after the player closed"
        )
    }

    func test_player_moreMenu_listsAspectSpeedAndSleepTimer() throws {
        openMoviePlayer()
        try skipWhereToolbarShadowsMoreMenuRows()

        showPlayerChrome()
        XCTAssertTrue(playerMoreButton.exists, "The More menu button should be in the top chrome")
        playerMoreButton.tap()

        let aspect = menuEntry(startingWith: "Aspect ratio")
        XCTAssertTrue(aspect.waitForExistence(timeout: 5), "The More menu should list the aspect ratio entry")
        XCTAssertTrue(menuEntry(startingWith: "Playback speed").exists, "The More menu should list the speed entry")
        XCTAssertTrue(menuEntry(startingWith: "Sleep timer").exists, "The More menu should list the sleep timer entry")

        // A tap outside closes the menu and leaves the player in place.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
        XCTAssertTrue(aspect.waitForNonExistence(timeout: 5), "A tap outside should close the More menu")
        showPlayerChrome()
    }

    func test_player_trackSettingsSheet_opensAndDismisses() throws {
        openMoviePlayer()
        try skipWhereToolbarShadowsMoreMenuRows()

        showPlayerChrome()
        playerMoreButton.tap()
        let trackSettings = menuEntry(startingWith: "Audio and subtitle tracks")
        XCTAssertTrue(trackSettings.waitForExistence(timeout: 5), "The More menu should offer the track settings")
        trackSettings.tap()

        let sheetBar = app.navigationBars["Playback Tracks"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 6), "The track settings sheet should present")
        let closeSheet = sheetBar.buttons["Close"]
        XCTAssertTrue(closeSheet.exists, "The track settings sheet should have a Close button")
        closeSheet.tap()
        XCTAssertTrue(sheetBar.waitForNonExistence(timeout: 6), "The track settings sheet should dismiss")

        // The player is still there and still answers taps.
        showPlayerChrome()
        XCTAssertTrue(playerPlayPauseButton.exists)
    }

    func test_search_openingLiveResult_presentsPlayerWithoutKeyboard() throws {
        XCTAssertTrue(tabButton(named: "Search").waitForExistence(timeout: 25))
        tabButton(named: "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("World News")

        // A live result opens the player straight from the list, with the search field
        // still being edited.
        let result = app.staticTexts["World News 24"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 6), "Search should list the mock live channel")
        let keyboardWasUp = recordKeyboardState()
        result.tap()

        XCTAssertTrue(playerCloseButton.waitForExistence(timeout: 10), "The live result should open the player")
        assertNoKeyboardOverPlayer()
        try skipUnlessKeyboardWasUp(keyboardWasUp)
    }

    func test_search_openingMovieResult_presentsPlayerWithoutKeyboard() throws {
        XCTAssertTrue(tabButton(named: "Search").waitForExistence(timeout: 25))
        tabButton(named: "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("Midnight")

        let result = app.staticTexts["Midnight Horizon"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 6), "Search should list the mock movie")
        let keyboardWasUp = recordKeyboardState()
        result.tap()

        let watchButton = moviePlayButton
        XCTAssertTrue(watchButton.waitForExistence(timeout: 8), "The movie result should open its detail screen")
        watchButton.tap()

        XCTAssertTrue(playerCloseButton.waitForExistence(timeout: 10), "The detail screen should open the player")
        assertNoKeyboardOverPlayer()
        try skipUnlessKeyboardWasUp(keyboardWasUp)
    }

    func test_player_moreMenu_staysOpenPastAutoHideWindow() throws {
        openMoviePlayer()
        try skipWhereToolbarShadowsMoreMenuRows()
        // Auto-hide only runs while the stream plays: a paused, failed or still loading
        // player keeps its controls up whatever the menu does.
        waitForPlaybackToStart()

        showPlayerChrome()
        playerMoreButton.tap()
        let aspect = menuEntry(startingWith: "Aspect ratio")
        XCTAssertTrue(aspect.waitForExistence(timeout: 5), "The More menu should open")

        // The controls that host the menu hide themselves 5 s after the last touch.
        Thread.sleep(forTimeInterval: 7)
        XCTAssertTrue(aspect.exists, "The More menu should still be open after the auto-hide window has passed")
        XCTAssertTrue(
            menuEntry(startingWith: "Sleep timer").exists,
            "The More menu should still list its rows after the auto-hide window has passed"
        )

        // Choosing a row closes the menu and ends its hold on the controls. A menu
        // that is opened again has to be held again.
        chooseAspectMode("Fill", from: aspect)
        XCTAssertTrue(playerMoreButton.waitForExistence(timeout: 3), "The controls should still be up after a choice")
        playerMoreButton.tap()
        XCTAssertTrue(aspect.waitForExistence(timeout: 5), "The More menu should open again")
        Thread.sleep(forTimeInterval: 7)
        XCTAssertTrue(aspect.exists, "A More menu that was opened again should stay open as well")

        // Back to the default mode: the choice is stored and outlives this test.
        chooseAspectMode("Fit", from: aspect)
        showPlayerChrome()
    }

    /// Picks a mode from the aspect ratio entry of the open More menu, which closes the menu.
    private func chooseAspectMode(
        _ title: String, from aspect: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        aspect.tap()
        let mode = app.buttons[title].firstMatch
        XCTAssertTrue(
            mode.waitForExistence(timeout: 5),
            "The aspect ratio entry should list \(title)", file: file, line: line
        )
        mode.tap()
        XCTAssertTrue(
            aspect.waitForNonExistence(timeout: 5),
            "Choosing an aspect mode should close the More menu", file: file, line: line
        )
    }

    // MARK: - Player, right-to-left
    //
    // The mini card and the edge-back slide are moved by a finger translation, which is
    // physical, while the app's layout is mirrored in Arabic. Both have to follow the
    // finger there as well.

    func test_player_rightToLeft_miniCardDragFollowsFinger() {
        relaunchInArabic()
        openMoviePlayer(moviesTab: Arabic.moviesTab, playLabels: Arabic.playLabels)

        // The pull-down that minimizes drifts 60 pt to the left on its way down. The
        // shrinking player stays under the finger, so it has to drift left as well.
        let screen = app.windows.firstMatch.frame
        let fullscreen = playerSurface.frame
        let drift: CGFloat = -60
        let pullStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let pullEnd = pullStart.withOffset(CGVector(dx: drift, dy: screen.height * 0.4))
        let pullSamples = frames(of: playerSurface) {
            pullStart.press(forDuration: 0.05, thenDragTo: pullEnd, withVelocity: 400, thenHoldForDuration: 3)
        }
        let pullTravel = largestHorizontalTravel(of: pullSamples, from: fullscreen)
        note("Pull-down drifted \(drift) pt sideways, player moved \(pullTravel) pt sideways")
        XCTAssertLessThan(
            pullTravel, drift * 0.5,
            "The player should follow a pull-down sideways (finger \(drift) pt, player \(pullTravel) pt)"
        )

        XCTAssertTrue(miniPlayerCard.waitForExistence(timeout: 5), "A pull-down should dock the mini card")
        XCTAssertTrue(miniPlayerCloseButton.waitForExistence(timeout: 3), "The mini card should have its controls")
        // The dock spring has to be over before the rest frame is read.
        Thread.sleep(forTimeInterval: 1.5)

        let docked = miniPlayerCard.frame
        // Toward the middle of the screen, so a card that follows the finger stays on
        // screen and re-docks in the same corner.
        let direction: CGFloat = docked.midX < screen.midX ? 1 : -1
        let distance: CGFloat = 80
        // Lower half of the card: the upper corners hold its two buttons.
        let start = miniPlayerCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = start.withOffset(CGVector(dx: direction * distance, dy: 0))
        let samples = frames(of: miniPlayerCard) {
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 4)
        }

        let travel = largestHorizontalTravel(of: samples, from: docked)
        note("Mini card docked at \(docked), finger moved \(direction * distance) pt, card moved \(travel) pt")
        XCTAssertFalse(samples.isEmpty, "The card's frame should be readable while the finger is down")
        XCTAssertGreaterThan(
            travel * direction, distance * 0.5,
            "The mini card should move with the finger (finger \(direction * distance) pt, card \(travel) pt)"
        )

        // An 80 pt drag is a reposition, not a dismiss: the card goes back to its corner.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(miniPlayerCard.exists, "A short sideways drag should not close the mini card")
        XCTAssertEqual(
            miniPlayerCard.frame.midX, docked.midX, accuracy: 4,
            "A short sideways drag should leave the card in its corner"
        )

        // The card takes taps where it is drawn.
        miniPlayerCard.tap()
        XCTAssertTrue(
            playerCloseButton.waitForExistence(timeout: 6),
            "Tapping the mini card should return to the fullscreen player"
        )
    }

    func test_player_rightToLeft_edgeBackSwipeFollowsFinger() {
        relaunchInArabic()
        openMoviePlayer(moviesTab: Arabic.moviesTab, playLabels: Arabic.playLabels)

        let screen = app.windows.firstMatch.frame
        let rest = playerSurface.frame
        // In right-to-left the back swipe starts at the right screen edge and travels
        // left. 90 pt is short of the distance that closes the player, so it springs back.
        let distance: CGFloat = 90
        // Between the top row and the volume capsule, which owns drags that start on it.
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: screen.maxX - 8, dy: screen.height * 0.3))
        let end = start.withOffset(CGVector(dx: -distance, dy: 0))
        let samples = frames(of: playerSurface) {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 4)
        }

        let travel = largestHorizontalTravel(of: samples, from: rest)
        note("Player at \(rest), finger moved \(-distance) pt from the right edge, player moved \(travel) pt")
        XCTAssertFalse(samples.isEmpty, "The player's frame should be readable while the finger is down")
        XCTAssertLessThan(
            travel, -distance * 0.3,
            "The player should slide with the finger (finger \(-distance) pt, player \(travel) pt)"
        )

        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(playerSurface.exists, "A short edge swipe should not close the player")
        XCTAssertEqual(
            playerSurface.frame.midX, rest.midX, accuracy: 4,
            "A short edge swipe should spring back"
        )
    }

    // MARK: - Right-to-left helpers

    /// Labels of the Arabic localization that the right-to-left tests navigate by.
    private enum Arabic {
        static let moviesTab = "الأفلام"
        /// "Watch now", or "Resume where you left off" once the movie has a saved position.
        static let playLabels = ["شاهد الآن", "المتابعة"]
    }

    /// `setUp` launched the app in English; start it again in Arabic.
    private func relaunchInArabic() {
        app.terminate()
        let arabic = XCUIApplication()
        arabic.launchArguments += ["-UITests", "1", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        arabic.launch()
        _ = arabic.wait(for: .runningForeground, timeout: 20)
        app = arabic
    }

    /// Frames of `element` read while `gesture` runs. An XCUITest gesture returns only
    /// after the finger is up, but it waits on the main run loop, so a timer there fires
    /// while the finger is still down.
    private func frames(of element: XCUIElement, during gesture: () -> Void) -> [CGRect] {
        let log = FrameLog()
        let timer = Timer(timeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard element.exists else { return }
                log.frames.append(element.frame)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        gesture()
        timer.invalidate()
        return log.frames
    }

    private final class FrameLog: @unchecked Sendable {
        var frames: [CGRect] = []
    }

    /// The sideways distance of the sample that lies farthest from `rest`; 0 without samples.
    private func largestHorizontalTravel(of samples: [CGRect], from rest: CGRect) -> CGFloat {
        samples
            .map { $0.midX - rest.midX }
            .max { abs($0) < abs($1) } ?? 0
    }

    private func note(_ text: String) {
        XCTContext.runActivity(named: text) { _ in }
    }

    // MARK: - Player helpers

    /// When this test last saw the chrome appear. The fullscreen chrome hides itself 5 s
    /// after its last interaction while playback runs; see `showPlayerChrome()`.
    private var chromeShownAt: Date?

    private var playerCloseButton: XCUIElement { app.buttons["player.close"] }
    private var playerPlayPauseButton: XCUIElement { app.buttons["player.playPause"] }
    private var playerMoreButton: XCUIElement { element(withIdentifier: "player.more") }
    private var playerSurface: XCUIElement { element(withIdentifier: "player.surface") }
    private var miniPlayerCard: XCUIElement { element(withIdentifier: "miniPlayer.expand") }
    private var miniPlayerCloseButton: XCUIElement { app.buttons["miniPlayer.close"] }
    private var miniPlayerPlayPauseButton: XCUIElement { app.buttons["miniPlayer.playPause"] }

    /// "Watch Now", or "Resume …" once the movie has a saved position.
    private var moviePlayButton: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Watch Now", "Resume")
        ).firstMatch
    }

    private func element(withIdentifier identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Rows of the More menu. A picker row reads as its title plus the current value,
    /// so match on the title only.
    private func menuEntry(startingWith title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", title)
        ).firstMatch
    }

    /// Opens the first seeded movie from the Movies grid and waits for the fullscreen
    /// player. The player opens with its controls visible.
    private func openMoviePlayer(
        moviesTab: String = "Movies",
        playLabels: [String] = ["Watch Now", "Resume"],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(tabButton(named: moviesTab).waitForExistence(timeout: 25), file: file, line: line)
        tabButton(named: moviesTab).tap()

        let firstMovie = app.staticTexts["Midnight Horizon"].firstMatch
        XCTAssertTrue(firstMovie.waitForExistence(timeout: 10), file: file, line: line)
        firstMovie.tap()

        // The detail screen's primary button, by the start of its label in the launch language.
        let watchButton = app.buttons.matching(
            NSCompoundPredicate(orPredicateWithSubpredicates: playLabels.map {
                NSPredicate(format: "label BEGINSWITH %@", $0)
            })
        ).firstMatch
        XCTAssertTrue(watchButton.waitForExistence(timeout: 8), file: file, line: line)
        watchButton.tap()

        XCTAssertTrue(
            playerCloseButton.waitForExistence(timeout: 10),
            "The player should open with its close button visible",
            file: file, line: line
        )
        chromeShownAt = Date()
    }

    /// A point on the picture that no control covers in portrait: below the top row,
    /// above the transport, between the edge sliders, and in the centre band, where a
    /// tap never counts toward a double-tap seek.
    private func tapVideoSurface() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    }

    /// Leaves the fullscreen chrome on screen with most of its auto-hide window still
    /// ahead, so the next tap on a control cannot land on a control that has just
    /// faded away. A chrome that has been up for a while is hidden and shown again.
    private func showPlayerChrome(file: StaticString = #filePath, line: UInt = #line) {
        if playerCloseButton.exists {
            if let shownAt = chromeShownAt, Date().timeIntervalSince(shownAt) < 2 { return }
            let tappedAt = Date()
            tapVideoSurface()
            guard playerCloseButton.waitForNonExistence(timeout: 1.5) else {
                // The chrome had hidden itself in between and this tap showed it again.
                chromeShownAt = tappedAt
                return
            }
        }
        tapVideoSurface()
        XCTAssertTrue(
            playerCloseButton.waitForExistence(timeout: 5),
            "A tap on the video should show the player controls",
            file: file, line: line
        )
        chromeShownAt = Date()
    }

    /// Waits until the demo stream plays (the transport button reads "Pause"). The
    /// stream is fetched from the network, so the start can be slow.
    private func waitForPlaybackToStart(
        timeout: TimeInterval = 60, file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastLabel = "(transport button not found)"
        while Date() < deadline {
            showPlayerChrome(file: file, line: line)
            if playerPlayPauseButton.exists {
                lastLabel = playerPlayPauseButton.label
                if lastLabel == "Pause" { return }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail(
            "The demo stream did not start playing within \(Int(timeout)) s "
                + "(transport button: \(lastLabel)); playback needs network access",
            file: file, line: line
        )
    }

    /// The timeline's spoken value, "elapsed / duration". The timeline is part of the
    /// chrome, so the chrome is brought up first unless the caller knows it is held.
    private func timelineValue(
        refreshingChrome: Bool = true, file: StaticString = #filePath, line: UInt = #line
    ) -> String {
        if refreshingChrome { showPlayerChrome(file: file, line: line) }
        let timeline = element(withIdentifier: "player.timeline")
        XCTAssertTrue(
            timeline.waitForExistence(timeout: 3),
            "The timeline should be part of the controls of a movie",
            file: file, line: line
        )
        return timeline.value as? String ?? ""
    }

    private func waitForLabel(_ label: String, of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", label),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The pull-down that minimizes the player: a downward drag that starts in the
    /// middle of the screen. The press is short, so it cannot turn into the 2x hold.
    private func pullDownFromMiddleOfScreen() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)
    }

    private func assertMiniCardIsDocked(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            miniPlayerCard.waitForExistence(timeout: 5),
            "A pull-down from the middle of the screen should dock the mini card",
            file: file, line: line
        )
        XCTAssertTrue(
            miniPlayerCloseButton.waitForExistence(timeout: 3),
            "The mini card should have a close button",
            file: file, line: line
        )
        XCTAssertTrue(
            playerCloseButton.waitForNonExistence(timeout: 3),
            "The fullscreen controls should be gone while the player is a mini card",
            file: file, line: line
        )
        XCTAssertTrue(
            tabButton(named: "Movies").waitForExistence(timeout: 5),
            "The tab bar should be reachable while the player is a mini card",
            file: file, line: line
        )
    }

    /// Notes in the test log whether the software keyboard was up while typing, and
    /// returns it. It is not asserted: a simulator with a hardware keyboard connected
    /// shows none. The check after the player opened then holds trivially, so the
    /// caller ends with `skipUnlessKeyboardWasUp(_:)` instead of reporting a pass.
    private func recordKeyboardState() -> Bool {
        let isUp = app.keyboards.firstMatch.exists
        XCTContext.runActivity(named: "Software keyboard on screen while typing: \(isUp)") { _ in }
        return isUp
    }

    /// Last line of a keyboard-dismissal test, after its assertions (so the player
    /// checks still run and can fail): with no software keyboard while typing, the
    /// dismissal was not tested and the test is reported as skipped.
    private func skipUnlessKeyboardWasUp(_ keyboardWasUp: Bool) throws {
        try XCTSkipUnless(
            keyboardWasUp,
            "Software keyboard was not shown while typing; turn off I/O > Keyboard > "
                + "Connect Hardware Keyboard to test the dismissal"
        )
    }

    /// The regular-width toolbar has buttons with the same labels as two rows of the
    /// More menu (aspect ratio, track settings), which `menuEntry(startingWith:)`
    /// cannot tell apart. Call once the player is open.
    private func skipWhereToolbarShadowsMoreMenuRows() throws {
        try XCTSkipIf(
            UIDevice.current.userInterfaceIdiom == .pad
                || app.windows.firstMatch.horizontalSizeClass == .regular,
            "On regular width the toolbar has buttons with the same labels as the More menu "
                + "rows; menuEntry(startingWith:) cannot tell them apart"
        )
    }

    /// The keyboard must be gone once the player is up, and must not come back.
    private func assertNoKeyboardOverPlayer(file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(
            keyboard.waitForNonExistence(timeout: 4),
            "The keyboard should not stay on screen over the player",
            file: file, line: line
        )
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(keyboard.exists, "The keyboard should not come back over the player", file: file, line: line)
        XCTAssertTrue(playerSurface.exists, "The player should still be on screen", file: file, line: line)
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

// MARK: - Browse behaviour

/// Browse behaviour that the native-feel pass changed. Every test here failed on the
/// build before that pass; together they pin the behaviour it guarantees.
@MainActor
final class BrowseBehaviourUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        XCTAssertTrue(app.tabBars.buttons["Live TV"].waitForExistence(timeout: 25), "Dashboard did not appear")
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// A pushed category grid keeps the tab bar, as pushed lists do in the system apps.
    func test_categoryGrid_keepsTabBar() {
        app.tabBars.buttons["Movies"].tap()
        let header = app.buttons["Action"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        header.tap()
        XCTAssertTrue(app.navigationBars["Action"].waitForExistence(timeout: 6))
        let moviesTab = app.tabBars.buttons["Movies"]
        XCTAssertTrue(moviesTab.waitForExistence(timeout: 3), "The tab bar should stay on a pushed category grid")
        XCTAssertTrue(moviesTab.isHittable, "The tab bar should stay on a pushed category grid")
    }

    /// The Search tab lists a title that starts with the query above one that only contains it.
    func test_search_listsPrefixMatchesFirst() {
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("mi")
        let prefixHit = app.staticTexts["Midnight Horizon"].firstMatch
        let containsHit = app.staticTexts["Family Ties"].firstMatch
        XCTAssertTrue(prefixHit.waitForExistence(timeout: 8))
        XCTAssertTrue(containsHit.waitForExistence(timeout: 2))
        XCTAssertLessThan(prefixHit.frame.minY, containsHit.frame.minY,
                          "'Midnight Horizon' starts with the query and should be listed first")
    }

    /// The Search tab's type filter is the search field's system scope bar.
    func test_search_typeFilterIsTheSystemScopeBar() {
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("mi")
        XCTAssertTrue(app.segmentedControls.buttons["Movies"].waitForExistence(timeout: 6),
                      "The type filter should be the system scope bar")
    }

    /// The + button of the playlist list is a menu with both kinds of playlist; no sheet in between.
    func test_addPlaylist_plusButtonIsAMenu() {
        app.tabBars.buttons["Settings"].tap()
        let backRow = app.buttons["Back to Playlists"]
        XCTAssertTrue(backRow.waitForExistence(timeout: 6))
        backRow.tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 6))
        app.navigationBars.buttons["plus"].firstMatch.tap()
        let xtream = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Xtream Code")).firstMatch
        XCTAssertTrue(xtream.waitForExistence(timeout: 4))
        XCTAssertFalse(app.navigationBars["Add Playlist"].exists, "Choosing the kind of playlist should not open a sheet")
    }

    /// The series page keeps its title when its seasons cannot be loaded; the failure and
    /// Try Again sit in the seasons section. The demo panel cannot serve seasons.
    func test_seriesDetail_keepsThePageWhenSeasonsFail() {
        app.tabBars.buttons["Series"].tap()
        let poster = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Northern Lights")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 8))
        poster.tap()
        XCTAssertTrue(app.buttons["Try Again"].waitForExistence(timeout: 20), "The seasons request should fail and offer Try Again")
        XCTAssertTrue(app.staticTexts["Northern Lights"].exists, "The series title should stay on the page next to the failure")
    }

    /// Switching the adult-content filter of an Xtream playlist asks before the catalog is downloaded again.
    func test_adultFilter_asksBeforeDownloadingAgain() {
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "Filter Adult Content")).firstMatch
        var swipes = 0
        while !(toggle.exists && toggle.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.isHittable, "The adult-content switch should be in Settings")
        let before = toggle.value as? String
        // The row is the switch element; its inner switch is what reliably takes the tap.
        if toggle.switches.firstMatch.exists {
            toggle.switches.firstMatch.tap()
        } else {
            toggle.tap()
        }
        // The question is an action sheet; on iOS 26 it is a popover without a Cancel
        // button, dismissed by tapping outside it.
        let dialog = app.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 4), "Switching the filter should ask first")
        if dialog.buttons["Cancel"].exists {
            dialog.buttons["Cancel"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
        XCTAssertFalse(dialog.waitForExistence(timeout: 2) && dialog.isHittable, "The question should close")
        XCTAssertEqual(toggle.value as? String, before, "Cancelling should leave the filter as it was")
    }

    /// A poster offers Add to Favorites in its context menu, without opening the detail.
    func test_movieCard_contextMenuOffersFavourite() {
        app.tabBars.buttons["Movies"].tap()
        let poster = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Midnight Horizon")).firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 8))
        poster.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Add to Favorites"].waitForExistence(timeout: 4),
                      "A long press on a poster should offer Add to Favorites")
        XCTAssertFalse(app.buttons["Watch Now"].exists, "The long press should not open the detail")
    }
}

@MainActor
final class M3UFavoritesBrowseUITests: XCTestCase {
    func test_favoriteChannelTapPresentsPlayer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-UITestsStartPlaylist", "m3u",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Channels"].waitForExistence(timeout: 25))
        let favorites = app.buttons["Favorites"].firstMatch
        XCTAssertTrue(favorites.waitForExistence(timeout: 8))
        favorites.tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 8))
        let channel = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Harbor News")).firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 8))
        channel.tap()
        XCTAssertTrue(app.buttons["player.close"].waitForExistence(timeout: 10),
                      "Selecting an M3U favorite should present the player")
    }
}

@MainActor
final class BrowseAccessibilityUITests: XCTestCase {
    func test_movieGridExposesTitleRatingAndWatchProgress() {
        checkMovieGrid(accessibilityTextSize: false)
    }

    func test_movieGridRemainsActionableAtLargestTextSize() {
        checkMovieGrid(accessibilityTextSize: true)
    }

    private func checkMovieGrid(accessibilityTextSize: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if accessibilityTextSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let movies = app.tabBars.buttons["Movies"]
        XCTAssertTrue(movies.waitForExistence(timeout: 25))
        movies.tap()
        let category = app.buttons["Sci-Fi"].firstMatch
        for _ in 0..<10 {
            if category.exists && category.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(category.isHittable)
        category.tap()
        let card = app.buttons["card.vod.1002"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(card.label.hasPrefix("Echoes of Tomorrow"), card.label)
        XCTAssertTrue(card.label.contains("Rating"), card.label)
        XCTAssertTrue(NSPredicate(format: "value CONTAINS %@", "40").evaluate(with: card),
                      "The watched percentage should be exposed as the card's value")
        card.tap()
        let primary = app.buttons["detail.primaryAction"]
        for _ in 0..<6 {
            if primary.exists && primary.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(primary.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = accessibilityTextSize ? "Detail-largest-text" : "Detail-default-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if !accessibilityTextSize {
            let poster = app.buttons["detail.poster"]
            XCTAssertTrue(poster.isHittable)
            poster.tap()
            let close = app.buttons["artwork.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertEqual(close.label, "Close")
            close.tap()
            XCTAssertTrue(primary.waitForExistence(timeout: 5))
        }
    }
}

@MainActor
final class GuideAccessibilityUITests: XCTestCase {
    func test_guideAndScheduleAtLargestTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-UITestsStartPlaylist", "m3u",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Channels"].waitForExistence(timeout: 25))
        let guide = app.buttons["TV Guide"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 8))
        guide.tap()
        let channel = app.staticTexts["Harbor News"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 15))
        let grid = XCTAttachment(screenshot: app.screenshot())
        grid.name = "Guide-largest-text"
        grid.lifetime = .keepAlways
        add(grid)
        channel.press(forDuration: 1)
        let schedule = app.buttons["Schedule"].firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        XCTAssertTrue(app.navigationBars["Harbor News"].waitForExistence(timeout: 8))
        let rows = app.cells
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 8))
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "Schedule-largest-text"
        list.lifetime = .keepAlways
        add(list)
        let programme = rows.buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? rows.buttons.firstMatch
        XCTAssertTrue(programme.isHittable)
        programme.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
    }
}

@MainActor
final class SearchPickerAccessibilityUITests: XCTestCase {
    private func launchLargestText() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Movies"].waitForExistence(timeout: 25))
        return app
    }

    func test_searchResultOpensDetailAtLargestTextSize() {
        let app = launchLargestText()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText("Echoes\n")
        let title = app.staticTexts["Echoes of Tomorrow"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Search-largest-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        title.tap()
        XCTAssertTrue(app.buttons["detail.primaryAction"].waitForExistence(timeout: 8))
    }

    func test_categorySelectionAtLargestTextSize() {
        let app = launchLargestText()
        app.tabBars.buttons["Movies"].tap()
        let picker = app.buttons["Jump to category"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        picker.tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("Sci-Fi\n")
        let category = app.staticTexts["Sci-Fi"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 6))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Category-picker-largest-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        category.tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sci-Fi"].firstMatch.isHittable)
    }
}

@MainActor
final class SettingsAccessibilityUITests: XCTestCase {
    func test_xtreamSettingsAtLargestTextSize() { checkSettings(m3u: false) }
    func test_m3uSettingsAtLargestTextSize() { checkSettings(m3u: true) }

    private func checkSettings(m3u: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        if m3u { app.launchArguments += ["-UITestsStartPlaylist", "m3u"] }
        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 25))
        settings.tap()
        capture(app, name: m3u ? "M3U-settings-top" : "Xtream-settings-top")
        let language = app.staticTexts["App Language"].firstMatch
        for _ in 0..<12 {
            if language.exists && language.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        }
        XCTAssertTrue(language.isHittable)
        capture(app, name: m3u ? "M3U-settings-language" : "Xtream-settings-language")
        language.tap()
        XCTAssertTrue(app.navigationBars["App Language"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let info = app.staticTexts["Name"].firstMatch
        for _ in 0..<35 {
            if info.exists && info.frame.minY > 120 && info.frame.maxY < app.frame.height - 100 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        }
        XCTAssertTrue(info.exists && info.frame.minY > 120 && info.frame.maxY < app.frame.height - 100)
        capture(app, name: m3u ? "M3U-settings-info" : "Xtream-settings-info")
        if !m3u {
            let password = app.buttons["Password"].firstMatch
            for _ in 0..<6 {
                if password.exists && password.isHittable { break }
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
            }
            XCTAssertTrue(password.isHittable)
            password.tap()
            XCTAssertFalse((password.value as? String ?? "").isEmpty)
            password.tap()
            XCTAssertEqual(password.value as? String ?? "", "")
        }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class GuideToolbarAccessibilityUITests: XCTestCase {
    func test_guideActionsAtDefaultTextSize() { checkToolbar(largest: false) }
    func test_guideActionsAtLargestTextSize() { checkToolbar(largest: true) }

    private func checkToolbar(largest: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-UITestsStartPlaylist", "m3u",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largest {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Channels"].waitForExistence(timeout: 25))
        app.buttons["TV Guide"].firstMatch.tap()
        let channel = app.staticTexts["Harbor News"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 15))
        let actions = app.buttons
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = largest ? "Guide-bottom-actions-largest-text" : "Guide-top-actions-default-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for label in ["Categories", "Search", "Now", "Refresh guide"] {
            let action = actions[label].firstMatch
            XCTAssertTrue(action.isHittable, label)
            if largest {
                XCTAssertGreaterThan(action.frame.minY, app.frame.height / 2, label)
            } else {
                XCTAssertLessThan(action.frame.maxY, app.frame.height / 2, label)
            }
        }
        actions["Categories"].firstMatch.tap()
        app.buttons["Collapse all"].firstMatch.tap()
        XCTAssertTrue(channel.waitForNonExistence(timeout: 5))
        actions["Categories"].firstMatch.tap()
        app.buttons["Expand all"].firstMatch.tap()
        XCTAssertTrue(channel.waitForExistence(timeout: 5))
        actions["Now"].firstMatch.tap()
        actions["Search"].firstMatch.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }
}

@MainActor
final class BrowseRTLVerificationUITests: XCTestCase {
    func test_arabicGuideOnEnglishDevice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich", "-UITestsStartPlaylist", "m3u",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-app.selected_language", "ar"]
        app.launch()
        let guide = app.buttons["دليل التلفزيون"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 25))
        guide.tap()
        let channel = app.staticTexts["Harbor News"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 15))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Arabic-guide-English-device"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertGreaterThan(channel.frame.midX, app.frame.width / 2)
        channel.press(forDuration: 1)
        let schedule = app.buttons["جدول البرامج"].firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        XCTAssertTrue(app.navigationBars["Harbor News"].waitForExistence(timeout: 5))
        let scheduleImage = XCTAttachment(screenshot: app.screenshot())
        scheduleImage.name = "Arabic-schedule-English-device"
        scheduleImage.lifetime = .keepAlways
        add(scheduleImage)
    }
}

@MainActor
final class BrowseDetailTimingUITests: XCTestCase {
    func test_cachedMoviePushAndPopWallClock() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let movies = app.tabBars.buttons["Movies"]
        XCTAssertTrue(movies.waitForExistence(timeout: 25))
        movies.tap()
        let category = app.buttons["Sci-Fi"].firstMatch
        for _ in 0..<10 {
            if category.exists && category.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(category.isHittable)
        category.tap()
        let card = app.buttons["card.vod.1002"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            startMeasuring()
            card.tap()
            XCTAssertTrue(app.buttons["detail.primaryAction"].waitForExistence(timeout: 8))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            stopMeasuring()
        }
    }
}

@MainActor
final class BrowseScaleVerificationUITests: XCTestCase {
    func test_largeCatalogJumpDetailAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsCatalogScale", "200",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let movies = app.buttons["Movies"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 120))
        movies.tap()
        let picker = app.buttons["Jump to category"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 30))
        picker.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Movies Canyon 215\n")
        let category = app.cells.buttons["Movies Canyon 215"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 10))
        category.tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForNonExistence(timeout: 8))
        let header = app.buttons["Movies Canyon 215"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "240k-catalog-category-jump"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        header.tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card.vod."))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        app.swipeUp()
        let card = cards.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(card)
        guard let card else { return }
        let identifier = card.identifier
        let originalY = card.frame.midY
        card.tap()
        XCTAssertTrue(app.buttons["detail.primaryAction"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        let returned = app.buttons[identifier].firstMatch
        XCTAssertTrue(returned.waitForExistence(timeout: 8))
        XCTAssertTrue(returned.isHittable)
        XCTAssertEqual(returned.frame.midY, originalY, accuracy: 5)
    }
}

@MainActor
final class BrowseWideLayoutUITests: XCTestCase {
    func test_detailAndFavoritesAcrossOrientations() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsFixture", "rich",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let movies = app.buttons["Movies"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 30))
        movies.tap()
        let favorite = app.buttons["star.fill"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 8))
        favorite.tap()
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(picker.frame.width, 421)
        capture(app, "Wide-favorites-portrait")
        rotate(.landscapeLeft, app: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(picker.frame.width, 421)
        capture(app, "Wide-favorites-landscape")
        let card = app.buttons["card.vod.1001"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["detail.primaryAction"].waitForExistence(timeout: 10))
        capture(app, "Wide-movie-detail-landscape")
        rotate(.portrait, app: app)
        XCTAssertTrue(app.buttons["detail.primaryAction"].waitForExistence(timeout: 8))
        capture(app, "Wide-movie-detail-portrait")
    }

    private func rotate(_ orientation: UIDeviceOrientation, app: XCUIApplication) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class BrowseShelfRetentionUITests: XCTestCase {
    func test_shelfOffsetSurvivesDistantCategoryJump() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsCatalogScale", "200",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let movies = app.buttons["Movies"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 120))
        movies.tap()
        jump(to: "Movies River 1", app: app)
        let row = shelf(below: "home.shelf.header.vod-cat-0", app: app)
        row.swipeLeft()
        row.swipeLeft()
        let before = firstVisibleCard(in: row)
        XCTAssertNotNil(before)
        guard let before else { return }
        let id = before.identifier
        jump(to: "Movies Soldier 40", app: app)
        jump(to: "Movies River 1", app: app)
        let returned = shelf(below: "home.shelf.header.vod-cat-0", app: app)
        let after = firstVisibleCard(in: returned)
        XCTAssertEqual(after?.identifier, id, "The category shelf must retain its horizontal anchor")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shelf-return-after-40-category-jump"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func test_liveShelfOffsetSurvivesDistantCategoryJump() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-UITests", "1", "-UITestsCatalogScale", "200",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let live = app.buttons["Live TV"].firstMatch
        XCTAssertTrue(live.waitForExistence(timeout: 120))
        live.tap()
        jump(to: "Channels River 1", app: app)
        let row = shelf(below: "home.shelf.header.live-cat-0", app: app)
        row.swipeLeft()
        row.swipeLeft()
        let before = firstVisibleCard(in: row, prefix: "card.live.")
        XCTAssertNotNil(before)
        guard let before else { return }
        let id = before.identifier
        jump(to: "Channels Soldier 40", app: app)
        jump(to: "Channels River 1", app: app)
        let returned = shelf(below: "home.shelf.header.live-cat-0", app: app)
        XCTAssertEqual(firstVisibleCard(in: returned, prefix: "card.live.")?.identifier, id)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Live-shelf-return-after-40-category-jump"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func firstVisibleCard(in row: XCUIElement, prefix: String = "card.vod.") -> XCUIElement? {
        let viewport = row.frame
        return row.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.first { card in
                let frame = card.frame
                // Offscreen lazy cells can have no activation point. Query hittability
                // only after excluding those cells by their visible intersection.
                return frame.width > 0 && frame.intersection(viewport).width > frame.width / 2
                    && card.isHittable
            }
    }

    private func jump(to name: String, app: XCUIApplication) {
        app.buttons["Jump to category"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText(name + "\n")
        let result = app.cells.buttons[name].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(result.waitForNonExistence(timeout: 8), "The picker row must leave the hierarchy before shelf gestures")
        XCTAssertTrue(app.navigationBars["Categories"].waitForNonExistence(timeout: 8))
    }

    private func shelf(below headerID: String, app: XCUIApplication) -> XCUIElement {
        let header = app.buttons[headerID].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 8))
        let y = header.frame.maxY
        let row = app.scrollViews.allElementsBoundByIndex.first {
            $0.frame.minY >= y - 2 && $0.frame.minY < y + 40 && $0.frame.height < 400
        }
        XCTAssertNotNil(row)
        return row ?? app.scrollViews.firstMatch
    }
}


/// iPhone-only relative simulator measurements. Clock values include XCUI dispatch
/// and idling; they are not animation duration or a physical-device frame budget.
@MainActor
final class BrowsePerformanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("These tab-bar measurements target iPhone; iPad has a separate layout test.")
        }
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITests", "1", "-UITestsCatalogScale", "200",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    private var options: XCTMeasureOptions {
        let result = XCTMeasureOptions()
        result.iterationCount = 3
        result.invocationOptions = [.manuallyStart, .manuallyStop]
        return result
    }

    private var interactionMetrics: [XCTMetric] {
        var metrics: [XCTMetric] = [XCTClockMetric(), XCTCPUMetric(application: app),
                                    XCTMemoryMetric(application: app)]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        return metrics
    }

    private func launchMovies() {
        app.launch()
        let movies = app.tabBars.buttons["Movies"]
        XCTAssertTrue(movies.waitForExistence(timeout: 120))
        movies.tap()
        XCTAssertTrue(app.buttons["home.shelf.header.vod-cat-0"].waitForExistence(timeout: 30))
    }

    private func fling(up: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.75 : 0.30))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.25 : 0.80))
        from.press(forDuration: 0.02, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
    }

    func test_p01_processLaunchToFirstShelf() {
        // Seed outside the measurement. Process-cold launches retain database/disk caches.
        launchMovies()
        app.terminate()
        measure(metrics: [XCTClockMetric(), XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            startMeasuring()
            app.launch()
            let movies = app.tabBars.buttons["Movies"]
            XCTAssertTrue(movies.waitForExistence(timeout: 60))
            movies.tap()
            XCTAssertTrue(app.buttons["home.shelf.header.vod-cat-0"].waitForExistence(timeout: 30))
            stopMeasuring()
            app.terminate()
        }
    }

    func test_p02_moviesHomeFling() {
        launchMovies()
        measure(metrics: interactionMetrics, options: options) {
            startMeasuring()
            for _ in 0..<3 { fling(up: true) }
            stopMeasuring()
            // Swiping past the top triggers pull-to-refresh. Reset outside the
            // measured window so the next sample never waits on a refresh alert.
            app.terminate()
            launchMovies()
        }
    }

    func test_p03_allMoviesGridFling() {
        launchMovies()
        app.buttons["All Movies"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["All Movies"].waitForExistence(timeout: 20))
        measure(metrics: interactionMetrics, options: options) {
            startMeasuring()
            for _ in 0..<5 { fling(up: true) }
            stopMeasuring()
            for _ in 0..<6 { fling(up: false) }
        }
    }

    func test_p04_warmContentTabSwitches() {
        launchMovies()
        let names = ["Live TV", "Series", "Movies"]
        for name in names { app.tabBars.buttons[name].tap() }
        measure(metrics: interactionMetrics, options: options) {
            startMeasuring()
            for name in names { app.tabBars.buttons[name].tap() }
            stopMeasuring()
        }
    }

    func test_p05_searchTypingToResults() {
        launchMovies()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        let results = app.descendants(matching: .any).matching(identifier: "search.results").firstMatch
        // Intentionally no CPU metric: typeText includes runner-driven accessibility traffic.
        measure(metrics: [XCTClockMetric()], options: options) {
            startMeasuring()
            field.typeText("the")
            XCTAssertTrue(results.waitForExistence(timeout: 15))
            stopMeasuring()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
            XCTAssertTrue(results.waitForNonExistence(timeout: 8))
        }
    }

    func test_p06_movieDetailPushPop() {
        launchMovies()
        app.buttons["home.shelf.header.vod-cat-0"].tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "card.vod."))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let card = cards.firstMatch
        measure(metrics: interactionMetrics, options: options) {
            startMeasuring()
            card.tap()
            XCTAssertTrue(app.buttons["detail.primaryAction"].waitForExistence(timeout: 10))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            stopMeasuring()
        }
    }

    func test_p07_openLargeGuide() {
        launchMovies()
        app.tabBars.buttons["Live TV"].tap()
        let guide = app.buttons["TV Guide"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 15))
        let grid = app.descendants(matching: .any).matching(identifier: "epg.guide.grid").firstMatch
        measure(metrics: interactionMetrics, options: options) {
            startMeasuring()
            guide.tap()
            XCTAssertTrue(grid.waitForExistence(timeout: 30))
            stopMeasuring()
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(guide.waitForExistence(timeout: 10))
        }
    }
}
