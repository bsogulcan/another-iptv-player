
@MainActor
final class StoreShotsUITests: XCTestCase {
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
    /// Tabs by position (iPhone, Duo) or by symbol identifier (iPad): labels are localized.
    private func tab(_ app: XCUIApplication, _ index: Int, _ symbol: String) -> XCUIElement {
        XCUIApplication.isPad ? app.buttons[symbol].firstMatch : app.tabBars.buttons.element(boundBy: index)
    }
    func test_storeShots() {
        continueAfterFailure = true
        let only = ProcessInfo.processInfo.environment["STORE_LANGS"].map { Set($0.split(separator: ",").map(String.init)) }
        for (lang, locale, forwardLabel) in languages where only?.contains(lang) ?? true {
            let app = XCUIApplication()
            app.launchArguments = ["-UITests", "1", "-AppleLanguages", "(\(lang))", "-AppleLocale", locale,
                                   "-UITestsStreamURL", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"]
            app.launch()
            XCTAssertTrue(tab(app, 0, "tv").waitForExistence(timeout: 30))
            sleep(9); shot("\(lang)-01-live")
            tab(app, 1, "film").tap(); sleep(7); shot("\(lang)-02-movies")
            let movie = app.staticTexts["Midnight Horizon"].firstMatch
            if movie.waitForExistence(timeout: 8) { movie.tap(); sleep(7); shot("\(lang)-03-movie-detail") }
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
                let close = app.buttons["player.close"].firstMatch
                if !close.isHittable { surface.tap(); sleep(1) }
                shot("\(lang)-04-player")
                if !close.isHittable { surface.tap(); sleep(1) }
                if close.isHittable { close.tap() }
                sleep(2)
            }
            tab(app, 2, "play.tv").tap(); sleep(7); shot("\(lang)-05-series")
            let series = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hidden Truths'")).firstMatch
            if series.waitForExistence(timeout: 8) { series.tap(); sleep(8); app.scrollViews.firstMatch.swipeUp(velocity: .slow); sleep(3); shot("\(lang)-06-series-detail") }
            tab(app, 4, "magnifyingglass").tap(); sleep(2)
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 6) { field.tap(); field.typeText("the"); sleep(5)
                app.swipeDown(velocity: .slow); sleep(1)
                shot("\(lang)-07-search") }
            app.terminate()
        }
    }
}
