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
            "player.speedUpOnLongPress": true
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, .shared)
        }
    }
}
