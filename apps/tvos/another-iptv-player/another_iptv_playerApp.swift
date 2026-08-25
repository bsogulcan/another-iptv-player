import SwiftUI

@main
struct another_iptv_playerApp: App {
    init() {
        _ = AppDatabase.shared
        Task { @MainActor in
            SyncEngine.shared.bootSync()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, .shared)
        }
    }
}
