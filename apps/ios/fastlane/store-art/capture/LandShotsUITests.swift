
@MainActor
final class LandShotsUITests: XCTestCase {
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
    private func tab(_ app: XCUIApplication, _ index: Int, _ symbol: String) -> XCUIElement {
        XCUIApplication.isPad ? app.buttons[symbol].firstMatch : app.tabBars.buttons.element(boundBy: index)
    }
    func test_landShots() {
        continueAfterFailure = true
        let only = ProcessInfo.processInfo.environment["STORE_LANGS"].map { Set($0.split(separator: ",").map(String.init)) }
        for (lang, locale, forwardLabel) in languages where only?.contains(lang) ?? true {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["-UITests", "1", "-AppleLanguages", "(\(lang))", "-AppleLocale", locale,
                                   "-UITestsStreamURL", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"]
            app.launch()
            XCTAssertTrue(tab(app, 0, "tv").waitForExistence(timeout: 30))
            if XCUIApplication.isPad {
                XCUIDevice.shared.orientation = .landscapeLeft
                sleep(9); shot("\(lang)-09-live-land")
                XCUIDevice.shared.orientation = .portrait; sleep(2)
            }
            tab(app, 1, "film").tap(); sleep(4)
            let movie = app.staticTexts["Midnight Horizon"].firstMatch
            if movie.waitForExistence(timeout: 8) { movie.tap(); sleep(3) }
            let play = app.buttons["detail.primaryAction"].firstMatch
            if play.waitForExistence(timeout: 8) {
                play.tap(); sleep(8)
                let surface = app.descendants(matching: .any).matching(identifier: "player.surface").firstMatch
                let fwd = app.buttons[forwardLabel].firstMatch
                for _ in 0..<5 {
                    if !fwd.isHittable { surface.tap(); sleep(1) }
                    if fwd.isHittable { fwd.tap(); usleep(400_000) }
                }
                XCUIDevice.shared.orientation = .landscapeLeft
                sleep(8)
                let close = app.buttons["player.close"].firstMatch
                if !close.isHittable { surface.tap(); sleep(1) }
                shot("\(lang)-08-player-land")
            }
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
