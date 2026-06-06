import Foundation
import Combine
import SwiftUI

/// Runtime dil değiştirme destekli localization yöneticisi.
/// Default = cihaz dili (ayar yoksa). Kullanıcı seçimi UserDefaults'ta saklanır.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Desteklenen diller — Flutter projesindeki l10n ARB dosyalarıyla aynı.
    static let supportedLanguages: [AppLanguage] = [
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
    private let storageKey = "app.selected_language"

    /// Kullanıcı seçimi. Değişince tüm view'lar re-render olsun diye @Published.
    @Published var selectedLanguage: String {
        didSet {
            UserDefaults.standard.set(selectedLanguage, forKey: storageKey)
        }
    }

    private init() {
        self.selectedLanguage = UserDefaults.standard.string(forKey: storageKey) ?? "system"
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
    /// Seçili dil UserDefaults'tan okunur (`selectedLanguage` @Published değeri zaten UserDefaults'a yazılıyor).
    nonisolated static func resolveLocalizedString(for key: String) -> String {
        let sentinel = "\u{1e}__missing__\u{1e}"
        let stored = UserDefaults.standard.string(forKey: "app.selected_language") ?? "system"
        let effective = stored == "system" ? systemLanguageCode() : stored

        if let bundle = nonisolatedBundle(for: effective) {
            let primary = bundle.localizedString(forKey: key, value: sentinel, table: nil)
            if primary != sentinel { return primary }
        }

        // Seçili dilde key yoksa İngilizce fallback.
        if effective != "en", let en = nonisolatedBundle(for: "en") {
            let enValue = en.localizedString(forKey: key, value: sentinel, table: nil)
            if enValue != sentinel { return enValue }
        }

        return key
    }

    nonisolated private static func nonisolatedBundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return bundle
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

/// Global helper — tüm view'larda kullanılır: `L("settings.title")` gibi.
/// Dil değiştiğinde LocalizationManager @Published yayar, view re-render olur, L() yeni değeri çeker.
/// `nonisolated` — LocalizedError gibi actor-bağımsız contextlerden de çağrılabilir.
func L(_ key: String) -> String {
    LocalizationManager.resolveLocalizedString(for: key)
}

/// Parametreli format helper: `L("episode_count", 10)` → `"10 episodes"`.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = LocalizationManager.resolveLocalizedString(for: key)
    return String(format: format, arguments: args)
}
