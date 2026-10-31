
@MainActor
final class SearchShotsUITests: XCTestCase {
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
    func test_searchShots() {
        for (lang, locale, _) in languages {
            let app = XCUIApplication()
            app.launchArguments = ["-UITests", "1", "-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
            app.launch()
            let search = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(search.waitForExistence(timeout: 30))
            sleep(4); search.tap(); sleep(2)
            let field = app.searchFields.firstMatch
            if field.waitForExistence(timeout: 6) {
                field.tap(); field.typeText("the\n"); sleep(5)
                shot("\(lang)-07-search")
            }
            app.terminate()
        }
    }
}
