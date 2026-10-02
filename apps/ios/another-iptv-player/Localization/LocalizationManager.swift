import Foundation
import Combine
import SwiftUI
import os

/// Runtime dil değiştirme destekli localization yöneticisi.
/// Default = cihaz dili (ayar yoksa). Kullanıcı seçimi UserDefaults'ta saklanır.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Desteklenen diller — Flutter projesindeki l10n ARB dosyalarıyla aynı.
    nonisolated static let supportedLanguages: [AppLanguage] = [
        .init(code: "system", nativeName: "Sistem Dili", englishName: "System"),
        .init(code: "en", nativeName: "English", englishName: "English"),
        .init(code: "tr", nativeName: "Türkçe", englishName: "Turkish"),
        .init(code: "ar", nativeName: "العربية", englishName: "Arabic"),
        .init(code: "de", nativeName: "Deutsch", englishName: "German"),
        .init(code: "es", nativeName: "Español", englishName: "Spanish"),
        .init(code: "fr", nativeName: "Français", englishName: "French"),
        .init(code: "hi", nativeName: "हिन्दी", englishName: "Hindi"),
        .init(code: "pt", nativeName: "Português", englishName: "Portuguese"),
        .init(code: "ru", nativeName: "Русский", englishName: "Russian"),
        .init(code: "zh", nativeName: "中文", englishName: "Chinese"),
    ]

    /// UserDefaults key — "system" veya iki harfli ISO 639-1 kod.
    nonisolated private static let storageKey = "app.selected_language"

    /// Kullanıcı seçimi. Değişince tüm view'lar re-render olsun diye @Published.
    @Published var selectedLanguage: String {
        didSet {
            UserDefaults.standard.set(selectedLanguage, forKey: Self.storageKey)
            // `L()` remembers which language is in effect. @Published announces a change
            // before the value is stored, so this runs ahead of every re-render it causes.
            LocalizedStringCache.languageDidChange()
            // Tapping the language that is already selected rebuilds nothing.
            if oldValue != selectedLanguage {
                languageChangeUptime = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    private init() {
        self.selectedLanguage = UserDefaults.standard.string(forKey: Self.storageKey) ?? "system"
    }

    // MARK: - Rebuild after a language change

    /// When the language was last changed, on the uptime clock. Not published: nothing
    /// redraws because of it.
    private var languageChangeUptime: TimeInterval?

    /// How long a language change counts as the reason for the rebuild that follows it.
    /// The rebuilt dashboard is back within a frame or two; the margin is for a slow device.
    private static let languageChangeRebuildWindow: TimeInterval = 2

    /// True right after the language was changed. The root view is rebuilt for it, and a
    /// dashboard created during that rebuild opens on Settings, where the change was made,
    /// instead of on the last content tab.
    /// Reading it changes nothing, so a view initialiser may ask on every call. It also
    /// runs out by itself: a rebuild that never reaches a dashboard cannot send a later,
    /// unrelated one to Settings.
    var isRebuildingAfterLanguageChange: Bool {
        guard let changedAt = languageChangeUptime else { return false }
        return ProcessInfo.processInfo.systemUptime - changedAt < Self.languageChangeRebuildWindow
    }

    /// Called by a dashboard once it is on screen: the rebuild has arrived where it was going.
    func finishLanguageChangeRebuild() {
        languageChangeUptime = nil
    }

    /// Aktif kullanılan dil kodu — "system" ise cihaz diline çevrilir.
    var effectiveLanguageCode: String {
        if selectedLanguage == "system" {
            return Self.systemLanguageCode()
        }
        return selectedLanguage
    }

    /// Seçili dile göre .lproj bundle'ı; bulamazsa fallback olarak English, sonra main.
    var bundle: Bundle {
        if let b = loadBundle(for: effectiveLanguageCode) {
            return b
        }
        if let fallback = loadBundle(for: "en") {
            return fallback
        }
        return .main
    }

    private func loadBundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return bundle
    }

    /// Verilen key için mevcut dilde string dön. Seçili dilde yoksa İngilizce'ye, o da yoksa
    /// Main bundle'a, son çare olarak key'in kendisine düşer (debug için).
    func string(for key: String) -> String {
        Self.resolveLocalizedString(for: key)
    }

    /// Actor-bağımsız lookup — LocalizedError gibi nonisolated contexlerden de güvenle çağrılabilir.
    /// `languageCode` nil means the language in effect; a test passes the one it wants.
    nonisolated static func resolveLocalizedString(for key: String, languageCode: String? = nil) -> String {
        LocalizedStringCache.string(for: key, languageCode: languageCode).value
    }

    /// What `L(_:_:)` does, with its inputs spelled out so that a language and a device
    /// locale can be passed in. The format is applied with `AppLocale`, because the plural
    /// rule of a stringsdict entry is picked by the locale of the format call: with none,
    /// every count other than 1 takes the "other" form, which is wrong for Russian and
    /// Arabic on any device.
    nonisolated static func formattedString(
        for key: String,
        arguments: [CVarArg],
        languageCode: String? = nil,
        deviceLocale: Locale = .current
    ) -> String {
        let resolved = LocalizedStringCache.string(for: key, languageCode: languageCode)
        let locale = AppLocale.locale(languageCode: resolved.languageCode, device: deviceLocale)
        return withVaList(arguments) {
            NSString(format: resolved.value, locale: locale, arguments: $0) as String
        }
    }

    /// The language `L()` resolves against right now: the stored choice, with "system"
    /// turned into the first supported language of the device.
    nonisolated static var currentLanguageCode: String {
        LocalizedStringCache.currentCode
    }

    /// The stored choice as it is read without the manager. `selectedLanguage` writes the
    /// same key, and a launch argument can override it.
    nonisolated fileprivate static func storedLanguageCode() -> String {
        let stored = UserDefaults.standard.string(forKey: storageKey) ?? "system"
        return stored == "system" ? systemLanguageCode() : stored
    }

    // MARK: - System detection

    nonisolated private static func systemLanguageCode() -> String {
        // Tercih edilen diller sırasıyla; desteklenen ilk eşleşmeyi bul.
        let supportedCodes = Set(supportedLanguages.map { $0.code }).subtracting(["system"])
        for lang in Locale.preferredLanguages {
            let base = Locale(identifier: lang).language.languageCode?.identifier ?? lang
            if supportedCodes.contains(base) {
                return base
            }
        }
        return "en"
    }
}

struct AppLanguage: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let nativeName: String
    let englishName: String
}

// MARK: - App locale

/// The one locale the app formats with: the in-app language with the device's region and
/// preferences (calendar, 12/24-hour clock, digits, first weekday, units). It is what iOS
/// itself builds for a per-app language, so "Turkish on a US-region phone" reads `ÖS 7:30`,
/// and plural rules, dates, sizes and counts all agree with the strings next to them.
/// `Locale.current` alone follows the device language, a bare `Locale(identifier: "tr")`
/// loses the region.
nonisolated enum AppLocale {
    static var current: Locale {
        locale(languageCode: LocalizedStringCache.currentCode, device: .current)
    }

    /// `device` itself when it already speaks `code`, so nothing of it is lost; otherwise
    /// `device` with the language swapped.
    static func locale(languageCode code: String, device: Locale) -> Locale {
        // The Chinese string table is Simplified. A device set to Traditional Chinese
        // still resolves to it, and must not format dates in the other script.
        let pinsSimplified = code == "zh"
        if device.language.languageCode?.identifier == code,
           !pinsSimplified || device.language.script == .hanSimplified {
            return device
        }
        var components = Locale.Components(locale: device)
        components.languageComponents.languageCode = Locale.LanguageCode(code)
        // The device's script belongs to the device's language.
        components.languageComponents.script = pinsSimplified ? .hanSimplified : nil
        return Locale(components: components)
    }
}

// MARK: - Lookup cache

/// What `L()` has resolved so far: the language in effect and, per language, its `.lproj`
/// bundle and the strings already looked up. Without it every call read the defaults,
/// matched the system languages and searched the bundle for the folder again, which was
/// most of the cost of putting a text on screen (a settings form asks for some sixty).
/// Behind a lock because `L()` is called from the main actor, from database queues and
/// from detached tasks alike.
nonisolated private enum LocalizedStringCache {
    private struct Language {
        /// nil when the app has no `.lproj` for the code.
        let bundle: Bundle?
        var strings: [String: String] = [:]
    }

    private struct State: @unchecked Sendable {
        /// nil until first use and again after a language change.
        var currentCode: String?
        var languages: [String: Language] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// The tables stay: a bundle's content does not change while the app runs. Only the
    /// answer to "which language" is taken again.
    static func languageDidChange() {
        state.withLock { $0.currentCode = nil }
    }

    static var currentCode: String {
        state.withLock { code(in: &$0) }
    }

    /// The string for `key`, and the language it was resolved for (so a caller that goes on
    /// to format it uses the same one even if the language changes in between).
    static func string(for key: String, languageCode: String?) -> (value: String, languageCode: String) {
        state.withLock { state in
            let code = languageCode ?? code(in: &state)
            if let hit = state.languages[code]?.strings[key] { return (hit, code) }
            // Stored as returned: a stringsdict entry is a string object that carries its
            // plural rules, and they survive only as long as it is not re-encoded.
            let value = lookUp(key, languageCode: code, in: &state)
            state.languages[code]?.strings[key] = value
            return (value, code)
        }
    }

    private static func code(in state: inout State) -> String {
        if let code = state.currentCode { return code }
        let code = LocalizationManager.storedLanguageCode()
        state.currentCode = code
        return code
    }

    /// The selected language, then English, then the key itself (which shows up in the UI
    /// and so gets noticed).
    private static func lookUp(_ key: String, languageCode code: String, in state: inout State) -> String {
        let sentinel = "\u{1e}__missing__\u{1e}"
        if let bundle = bundle(for: code, in: &state) {
            let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
            if value != sentinel { return value }
        }
        if code != "en", let english = bundle(for: "en", in: &state) {
            let value = english.localizedString(forKey: key, value: sentinel, table: nil)
            if value != sentinel { return value }
        }
        return key
    }

    private static func bundle(for code: String, in state: inout State) -> Bundle? {
        if let known = state.languages[code] { return known.bundle }
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) }
        state.languages[code] = Language(bundle: bundle)
        return bundle
    }
}

// MARK: - L()

/// Global helper — tüm view'larda kullanılır: `L("settings.title")` gibi.
/// Dil değiştiğinde LocalizationManager @Published yayar, view re-render olur, L() yeni değeri çeker.
/// `nonisolated` — LocalizedError gibi actor-bağımsız contextlerden de çağrılabilir.
nonisolated func L(_ key: String) -> String {
    LocalizationManager.resolveLocalizedString(for: key)
}

/// Parametreli format helper: `L("episode_count", 10)` → `"10 episodes"`.
/// Formatted with `AppLocale.current`, so the plural rules of Localizable.stringsdict
/// (one/few/many/other) follow the app language, and numbers get that locale's digits and
/// grouping separators: right for a count that is read, wrong for a number that is stored
/// or quoted (see `L(plainDigits:_:)`).
nonisolated func L(_ key: String, _ args: CVarArg...) -> String {
    LocalizationManager.formattedString(for: key, arguments: args)
}

/// The same lookup, formatted without a locale: ASCII digits and no grouping separators.
/// For text that is stored or has to stay recognisable whatever the region (a generated
/// channel name, an HTTP status code). Not for counts: without a locale a stringsdict
/// entry only tells 1 from everything else.
nonisolated func L(plainDigits key: String, _ args: CVarArg...) -> String {
    let format = LocalizationManager.resolveLocalizedString(for: key)
    return withVaList(args) { NSString(format: format, locale: nil, arguments: $0) as String }
}
