
@MainActor
final class DuoLandUITests: XCTestCase {
    private let outDir = ProcessInfo.processInfo.environment["STORE_OUT"] ?? "/tmp"
    private let languages: [(String, String, String)] = [
        ("en", "en_US", "Forward 15 seconds"),
        ("tr", "tr_TR", "15 saniye ileri"),
        ("de", "de_DE", "15 Sekunden vor"),
        ("es", "es_ES", "Avanzar 15 segundos"),
        ("fr", "fr_FR", "Avancer de 15 secondes"),
        ("pt-BR", "pt_BR", "Avançar 15 segundos"),
        ("ru", "ru_RU", "Вперёд на 15 секунд"),
        ("ar", "ar_SA", "تقديم 15 ثانية"),
        ("hi", "hi_IN", "15 सेकंड आगे"),
        ("zh-Hans", "zh_CN", "前进15秒")
    ]

    private func shot(_ name: String) {
        sleep(1)
        let req = URL(fileURLWithPath: outDir).appendingPathComponent("req-\(name)")
        try? Data().write(to: req)
        for _ in 0..<60 where FileManager.default.fileExists(atPath: req.path) { usleep(250_000) }
    }
    /// The simulator is left open and in landscape by hand; nothing here rotates it.
    func test_duoLand() {
        continueAfterFailure = true
        for (lang, locale, forwardLabel) in languages {
            let app = XCUIApplication()
            app.launchArguments = ["-UITests", "1", "-AppleLanguages", "(\(lang))", "-AppleLocale", locale,
                                   "-UITestsStreamURL", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"]
            app.launch()
            // In landscape the inner display moves the tab bar into a vertical strip:
            // tabs are found by their symbol identifiers, not as a tab bar.
            XCTAssertTrue(app.buttons["tv"].firstMatch.waitForExistence(timeout: 30))
            sleep(9); shot("\(lang)-10-live-land")
            app.buttons["film"].firstMatch.tap(); sleep(4)
            let movie = app.staticTexts["Midnight Horizon"].firstMatch
            if movie.waitForExistence(timeout: 8) { movie.tap(); sleep(7); shot("\(lang)-11-detail-land") }
            let play = app.buttons["detail.primaryAction"].firstMatch
            if play.waitForExistence(timeout: 8) {
                play.tap(); sleep(8)
                let surface = app.descendants(matching: .any).matching(identifier: "player.surface").firstMatch
                let fwd = app.buttons[forwardLabel].firstMatch
                for _ in 0..<5 {
                    if !fwd.isHittable { surface.tap(); sleep(1) }
                    if fwd.isHittable { fwd.tap(); usleep(400_000) }
                }
                sleep(7)
                if !app.buttons["player.close"].firstMatch.isHittable { surface.tap(); sleep(1) }
                shot("\(lang)-12-player-land")
            }
            app.terminate()
        }
    }
}
