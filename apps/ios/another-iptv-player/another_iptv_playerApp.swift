import SwiftUI
import KSPlayer

class AppDelegate: NSObject, UIApplicationDelegate {
    private var diagnosticBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    func flushDiagnosticsInBackground() {
        guard diagnosticBackgroundTask == .invalid else { return }
        diagnosticBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Flush diagnostics") { [weak self] in
            self?.finishDiagnosticFlush()
        }
        let identifier = diagnosticBackgroundTask
        Task.detached(priority: .utility) { [weak self] in
            APIDiagnostics.flush()
            Log.flush()
            DiagnosticArchive.shared.flush()
            await self?.finishDiagnosticFlush(expected: identifier)
        }
    }

    private func finishDiagnosticFlush(expected: UIBackgroundTaskIdentifier? = nil) {
        if let expected, expected != diagnosticBackgroundTask { return }
        guard diagnosticBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(diagnosticBackgroundTask)
        diagnosticBackgroundTask = .invalid
    }

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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        KSOptions.logger = PlayerDiagnosticLog()
        KSOptions.logLevel = .info
        Log.info("App", "Session started")
        IPTVRemoteImagePipeline.installAsShared()
        _ = AppDatabase.shared
        MockFixture.seedIfNeeded()
        UserDefaults.standard.register(defaults: [
            "player.pipEnabled": true,
            "player.continuePlayingInBackground": true,
            "player.speedUpOnLongPress": true,
            "player.autoPlayNextEpisode": true
        ])
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { appDelegate.flushDiagnosticsInBackground() }
        }
    }
}

/// Uygulama kökü dil seçimini gözler: değişimde `.id` tüm hiyerarşiyi yeniden kurar,
/// böylece L() ile çözülen her metin anında yeni dile geçer (yalnızca 3-4 view'ın
/// manager'ı gözlemesine güvenmek çoğu ekranı eski dilde bırakıyordu). `.locale` ve
/// `.layoutDirection` da seçime göre ayarlanır — Arapça'da sayı/tarih biçimleri ve
/// RTL yerleşim cihaz diline değil, seçilen dile uyar.
/// The locale is `AppLocale.current`, the same one `L()` and the formatters use: a bare
/// language code would drop the device's region, and numbers SwiftUI formats (interpolated
/// counts) would then disagree in digits and separators with the dates and sizes next to them.
private struct AppRootView: View {
    @ObservedObject private var localization = LocalizationManager.shared

    var body: some View {
        let code = localization.effectiveLanguageCode
        let isRTL = Locale.Language(identifier: code).characterDirection == .rightToLeft
        ContentView()
            .environment(\.appDatabase, .shared)
            .environment(\.locale, AppLocale.current)
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .id(localization.selectedLanguage)
    }
}
