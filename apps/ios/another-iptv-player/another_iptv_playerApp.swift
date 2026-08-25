import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Varsayılan: tüm yönler. `LiveChannelBrowserScreen` açıkken `.landscape` yapılır.
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    /// Background URLSession olayları için sistem çağırır. Completion handler'ı DownloadManager'a iletiriz;
    /// tüm delegate çağrıları dağıtılınca `urlSessionDidFinishEvents` tetikler.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            DownloadManager.shared.backgroundCompletionHandler = completionHandler
        }
    }
}

@main
struct another_iptv_playerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        IPTVRemoteImagePipeline.installAsShared()
        _ = AppDatabase.shared
        MockFixture.seedIfNeeded()
        UserDefaults.standard.register(defaults: [
            "player.pipEnabled": true,
            "player.continuePlayingInBackground": true,
            "player.speedUpOnLongPress": true,
            "player.autoPlayNextEpisode": true
        ])
        Task { @MainActor in
            SyncEngine.shared.bootSync()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

/// Uygulama kökü dil seçimini gözler: değişimde `.id` tüm hiyerarşiyi yeniden kurar,
/// böylece L() ile çözülen her metin anında yeni dile geçer (yalnızca 3-4 view'ın
/// manager'ı gözlemesine güvenmek çoğu ekranı eski dilde bırakıyordu). `.locale` ve
/// `.layoutDirection` da seçime göre ayarlanır — Arapça'da sayı/tarih biçimleri ve
/// RTL yerleşim cihaz diline değil, seçilen dile uyar.
private struct AppRootView: View {
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        let code = localization.effectiveLanguageCode
        let isRTL = Locale.Language(identifier: code).characterDirection == .rightToLeft
        ContentView()
            .environment(\.appDatabase, .shared)
            .environment(\.locale, Locale(identifier: code))
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .id(localization.selectedLanguage)
    }
}
