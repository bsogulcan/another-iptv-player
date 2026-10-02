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
