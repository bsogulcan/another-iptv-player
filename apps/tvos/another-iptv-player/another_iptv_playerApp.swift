import SwiftUI

@main
struct another_iptv_playerApp: App {
    init() {
        _ = AppDatabase.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appDatabase, .shared)
        }
    }
}
