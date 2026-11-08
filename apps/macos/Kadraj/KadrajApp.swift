#if DEBUG
import CoreAudio
#endif
import GRDBQuery
import SwiftUI

@main
struct KadrajApp: App {
  @AppStorage("mac.appearance") private var appearance = "system"
  @StateObject private var playback = DesktopPlayback()
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var language = LocalizationManager.shared

  init() {
    #if DEBUG
      if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        // Silence this host at the output boundary. Decoders and volume controls
        // still run normally, including AVPlayer instances created by tests.
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessIsAudible,
          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var audible: UInt32 = 0
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
          0, nil, UInt32(MemoryLayout<UInt32>.size), &audible)
        precondition(status == noErr, "Cannot silence playback test host (\(status))")
      }
    #endif
    IPTVRemoteImagePipeline.installAsShared()
    #if DEBUG
      MockFixture.seedIfNeeded()
    #endif
    TipStore.shared.startObservingTransactions()
  }

  var body: some Scene {
    Window("Another IPTV Player", id: "library") {
      GeometryReader { _ in
        SourceLibrary()
          .modifier(MacPlaybackPresentation(playback: playback))
      }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .modifier(AppUpdateOffer(updateChecker: .shared))
        .onChange(of: playback.expanded, initial: true) { _, expanded in
          AppUpdateChecker.shared.isPlayerInFront = expanded
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
          if phase == .active { AppUpdateChecker.shared.checkIfNeeded() }
        }
        .environmentObject(playback)
        .environment(\.appDatabase, AppDatabase.shared)
        .environment(\.locale, AppLocale.current)
        .environment(
          \.layoutDirection,
          Locale.Language(identifier: language.effectiveLanguageCode).characterDirection
            == .rightToLeft ? .rightToLeft : .leftToRight
        )
        .environmentObject(language)
        .frame(minWidth: 500, minHeight: 340)
    }
    .defaultSize(width: 1140, height: 790)
    .windowResizability(.contentMinSize)
    .commands {
      SidebarCommands()
      WorkspaceCommands()
    }
  }
}


struct MacPlaybackPresentation: ViewModifier {
  @ObservedObject var playback: DesktopPlayback
  @AppStorage(MacAudioOutput.speakerKey) private var useSpeakers = false
  @AppStorage("player.continuePlayingInBackground") private var allowsBackground = true
  @State private var windowAnchor = NSView(frame: .zero)
  @State private var previousToolbarVisibility: Bool?
  @State private var fullScreen = false
  @State private var hidden = false
  @State private var minimized = false

  private func applyVisibility() {
    playback.applyVisibility(hidden: hidden, minimized: minimized, allowsBackground: allowsBackground)
  }

  func body(content: Content) -> some View {
    let playerInFront = playback.expanded && playback.current != nil
    let cinema = fullScreen && playerInFront
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: playerInFront, initial: true) { _, hide in
        guard let toolbar = windowAnchor.window?.toolbar else { return }
        if hide {
          previousToolbarVisibility = toolbar.isVisible
          toolbar.isVisible = false
        } else if let previousToolbarVisibility {
          toolbar.isVisible = previousToolbarVisibility
          self.previousToolbarVisibility = nil
        }
      }
      .accessibilityHidden(playerInFront)
      .background(MacPlayerWindowAnchor(view: windowAnchor).frame(width: 0, height: 0))
      .onAppear {
        fullScreen = windowAnchor.window?.styleMask.contains(.fullScreen) == true
        playback.engine.restorePictureInPictureWindow = { [weak playback, weak windowAnchor] in
          guard let playback, playback.current != nil, let window = windowAnchor?.window else { return false }
          playback.expanded = true
          if window.isMiniaturized { window.deminiaturize(nil) }
          NSApp.activate(ignoringOtherApps: true)
          window.makeKeyAndOrderFront(nil)
          return true
        }
        hidden = NSApp.isHidden
        minimized = windowAnchor.window?.isMiniaturized == true
        applyVisibility()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in
        hidden = true
        applyVisibility()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
        hidden = false
        applyVisibility()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { event in
        guard let window = event.object as? NSWindow, window === windowAnchor.window else { return }
        minimized = true
        applyVisibility()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { event in
        guard let window = event.object as? NSWindow, window === windowAnchor.window else { return }
        minimized = false
        applyVisibility()
      }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { event in
        guard let window = event.object as? NSWindow, window === windowAnchor.window else { return }
        fullScreen = true
      }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { event in
        guard let window = event.object as? NSWindow, window === windowAnchor.window else { return }
        fullScreen = false
      }
      .onChange(of: useSpeakers) { _, _ in playback.engine.updateNativeAudioOutput() }
      .onChange(of: allowsBackground) { _, _ in applyVisibility() }
      .safeAreaInset(edge: .bottom) {
        if let media = playback.current, !playback.expanded {
          MacPlayerBar(session: playback, engine: playback.engine, media: media)
        }
      }
      .overlay {
        if let media = playback.current, playerInFront {
          MacPlayerView(session: playback, engine: playback.engine, media: media)
            .ignoresSafeArea(.container, edges: cinema ? .all : [])
        }
      }
  }
}
