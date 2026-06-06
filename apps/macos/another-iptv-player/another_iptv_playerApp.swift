import AppKit
import Combine
import SwiftUI

/// macOS varyantı: iOS'taki UIApplicationDelegate + orientation lock + arka plan URLSession
/// completion handler gerekmiyor. macOS'ta background download tamamlama doğrudan
/// URLSessionDelegate üzerinden ele alınır; ek bir köprüye gerek yok.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Menü komutlarının (File > New Playlist…) tetiklemesi için global SwiftUI sinyali.
/// ContentView bunu okuyup sheet'i açar.
@MainActor
final class MenuSignal: ObservableObject {
    static let shared = MenuSignal()
    @Published var newPlaylistRequested: Int = 0
    @Published var openPlaylistFileRequested: Int = 0
    @Published var refreshContentRequested: Int = 0
    @Published var closePlaylistRequested: Int = 0
    @Published var openDownloadsRequested: Int = 0
    @Published var navigateBackRequested: Int = 0
    @Published var navigateForwardRequested: Int = 0
    @Published var openSearchRequested: Int = 0
}

@main
struct another_iptv_playerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuSignal = MenuSignal.shared

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
                .environmentObject(menuSignal)
                .frame(minWidth: 1024, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)

        Settings {
            AppSettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Playlist…") {
                    menuSignal.newPlaylistRequested &+= 1
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Open Playlist File…") {
                    menuSignal.openPlaylistFileRequested &+= 1
                }
                .keyboardShortcut("o", modifiers: [.command])

                Divider()

                Button("Close Active Playlist") {
                    menuSignal.closePlaylistRequested &+= 1
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                // Browser/Finder tarzı geri/ileri. Toolbar butonlarının da aynı kısayolu var
                // (ContentView'de tetiklenir); buradaki menü item'ları menubar'da görünürlük için.
                Button("Back") {
                    menuSignal.navigateBackRequested &+= 1
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Forward") {
                    menuSignal.navigateForwardRequested &+= 1
                }
                .keyboardShortcut("]", modifiers: [.command])
                Divider()
            }
            CommandMenu("View") {
                Button("Refresh Content") {
                    menuSignal.refreshContentRequested &+= 1
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Search…") {
                    menuSignal.openSearchRequested &+= 1
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .help) {
                Link("GitHub: another-iptv-player",
                     destination: URL(string: "https://github.com/")!)
            }
        }
    }
}
