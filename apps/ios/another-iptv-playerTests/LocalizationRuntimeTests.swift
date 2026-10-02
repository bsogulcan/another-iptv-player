import Foundation
import Testing
@testable import another_iptv_player

/// `L()` at run time: plural rules follow the app language, the lookup cache returns
/// what the string tables hold, and `AppLocale` joins the app language to the device's
/// region.
///
/// Every test names its language and device locale, so nothing here depends on, or
/// changes, the language the host app is running in.
@Suite("Localization at run time")
struct LocalizationRuntimeTests {

    private let usDevice = Locale(identifier: "en_US")

    private func episodes(_ count: Int, in language: String, device: Locale? = nil) -> String {
        LocalizationManager.formattedString(
            for: "detail.episode_count_plural",
            arguments: [count],
            languageCode: language,
            deviceLocale: device ?? usDevice
        )
    }

    // MARK: Plural rules

    @Test
    func russianCountsUseAllFourForms() {
        #expect(episodes(1, in: "ru") == "1 серия")
        #expect(episodes(2, in: "ru") == "2 серии")
        #expect(episodes(5, in: "ru") == "5 серий")
        #expect(episodes(11, in: "ru") == "11 серий")
        #expect(episodes(21, in: "ru") == "21 серия")
        #expect(episodes(100, in: "ru") == "100 серий")
    }

    @Test
    func arabicCountsUseTheDualAndThePluralForms() {
        #expect(episodes(1, in: "ar") == "حلقة واحدة")
        #expect(episodes(2, in: "ar") == "حلقتان")
        #expect(episodes(5, in: "ar") == "5 حلقات")
        #expect(episodes(11, in: "ar") == "11 حلقة")
    }

    /// The rule comes from the app language, not from the device: an English phone
    /// showing the app in Russian still needs the Russian forms, and a Russian phone
    /// showing it in English must not apply them.
    @Test
    func thePluralRuleIgnoresTheDeviceLanguage() {
        let russianDevice = Locale(identifier: "ru_RU")
        #expect(episodes(5, in: "ru", device: russianDevice) == "5 серий")
        #expect(episodes(21, in: "en", device: russianDevice) == "21 Episodes")
        #expect(episodes(1, in: "en", device: russianDevice) == "1 Episode")
    }

    /// The first call fills the cache, the following ones are answered from it. A
    /// stringsdict entry only keeps its rules while the cached value is the object the
    /// bundle returned.
    @Test
    func aCachedPluralEntryStillInflects() {
        for _ in 0..<3 {
            #expect(episodes(1, in: "ru") == "1 серия")
            #expect(episodes(5, in: "ru") == "5 серий")
            #expect(episodes(2, in: "ar") == "حلقتان")
        }
    }

    @Test
    func countsTakeTheDigitsOfTheDeviceRegion() {
        #expect(episodes(5, in: "ar", device: Locale(identifier: "ar_SA")) == "٥ حلقات")
        #expect(episodes(5, in: "ar", device: usDevice) == "5 حلقات")
    }

    @Test
    func plainDigitsKeepsNumbersUngroupedAndASCII() {
        let name = L(plainDigits: "misc.channel_fallback_name", 12345)
        #expect(name.contains("12345"))
        let status = L(plainDigits: "net.error.server", 404)
        #expect(status.contains("404"))
    }

    // MARK: Lookup and fallback

    @Test
    func aStringIsReadFromTheLanguageAskedFor() {
        let english = LocalizationManager.resolveLocalizedString(for: "common.cancel", languageCode: "en")
        let turkish = LocalizationManager.resolveLocalizedString(for: "common.cancel", languageCode: "tr")
        #expect(english == "Cancel")
        #expect(turkish == "İptal")
        // And again, from the cache.
        #expect(LocalizationManager.resolveLocalizedString(for: "common.cancel", languageCode: "tr") == turkish)
        #expect(LocalizationManager.resolveLocalizedString(for: "common.cancel", languageCode: "en") == english)
    }

    @Test
    func aLanguageWithoutATableFallsBackToEnglish() {
        #expect(LocalizationManager.resolveLocalizedString(for: "common.cancel", languageCode: "xx") == "Cancel")
    }

    @Test
    func aKeyNoTableHasComesBackAsTheKey() {
        let key = "localization.tests.no_such_key"
        #expect(LocalizationManager.resolveLocalizedString(for: key, languageCode: "tr") == key)
        #expect(LocalizationManager.resolveLocalizedString(for: key, languageCode: "en") == key)
        #expect(LocalizationManager.resolveLocalizedString(for: key, languageCode: "tr") == key)
    }

    @Test
    func theLanguageInEffectIsOneTheAppShips() {
        let codes = LocalizationManager.supportedLanguages.map(\.code).filter { $0 != "system" }
        #expect(codes.contains(LocalizationManager.currentLanguageCode))
        #expect(L("common.cancel") == LocalizationManager.resolveLocalizedString(
            for: "common.cancel", languageCode: LocalizationManager.currentLanguageCode
        ))
    }

    @Test
    func concurrentLookupsAgree() async {
        let keys = ["common.ok", "common.cancel", "dashboard.live", "favorites.title", "search.title"]
        let languages = ["en", "tr", "ru", "ar"]
        var expected: [String: String] = [:]
        for language in languages {
            for key in keys {
                expected["\(language)/\(key)"] = LocalizationManager.resolveLocalizedString(for: key, languageCode: language)
            }
        }
        let reference = expected

        let mismatches = await withTaskGroup(of: Int.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    var wrong = 0
                    for round in 0..<2_000 {
                        let language = languages[(round + worker) % languages.count]
                        let key = keys[round % keys.count]
                        let value = LocalizationManager.resolveLocalizedString(for: key, languageCode: language)
                        if value != reference["\(language)/\(key)"] { wrong += 1 }
                    }
                    return wrong
                }
            }
            return await group.reduce(0, +)
        }
        #expect(mismatches == 0)
    }

    // MARK: App locale

    @Test
    func aDeviceThatAlreadySpeaksTheLanguageIsLeftAlone() {
        for identifier in ["en_GB", "de_CH", "ar_SA", "pt_BR", "zh_CN"] {
            let device = Locale(identifier: identifier)
            let code = device.language.languageCode?.identifier ?? ""
            #expect(AppLocale.locale(languageCode: code, device: device) == device, "\(identifier)")
        }
    }

    @Test
    func anotherLanguageKeepsTheDeviceRegion() {
        let turkish = AppLocale.locale(languageCode: "tr", device: usDevice)
        #expect(turkish.language.languageCode?.identifier == "tr")
        #expect(turkish.region?.identifier == "US")
        // The region decides the clock, as it does for a per-app language in Settings.
        #expect(turkish.hourCycle == usDevice.hourCycle)

        let german = AppLocale.locale(languageCode: "de", device: Locale(identifier: "en_GB"))
        #expect(german.language.languageCode?.identifier == "de")
        #expect(german.region?.identifier == "GB")
    }

    @Test
    func digitsFollowTheDeviceRegion() {
        #expect(AppLocale.locale(languageCode: "ar", device: usDevice).numberingSystem.identifier == "latn")
        #expect(AppLocale.locale(languageCode: "ar", device: Locale(identifier: "ar_SA")).numberingSystem.identifier == "arab")
        #expect(AppLocale.locale(languageCode: "en", device: Locale(identifier: "ar_SA")).numberingSystem.identifier == "latn")
    }

    /// The Chinese table is Simplified; a Traditional-script device must not format
    /// dates in the other script next to it.
    @Test
    func chineseIsPinnedToTheSimplifiedScript() {
        for identifier in ["zh_TW", "zh-Hant_TW", "zh_HK", "en_US"] {
            let locale = AppLocale.locale(languageCode: "zh", device: Locale(identifier: identifier))
            #expect(locale.language.languageCode?.identifier == "zh", "\(identifier)")
            #expect(locale.language.script == .hanSimplified, "\(identifier)")
        }
        let taiwan = AppLocale.locale(languageCode: "zh", device: Locale(identifier: "zh_TW"))
        #expect(taiwan.region?.identifier == "TW")
        // A device script is not carried into another language.
        let turkish = AppLocale.locale(languageCode: "tr", device: Locale(identifier: "zh-Hant_TW"))
        #expect(turkish.language.script == .latin)
        #expect(turkish.region?.identifier == "TW")
    }
}
