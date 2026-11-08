import AVKit
import AppKit
import CoreAudio
import GRDB
import KSPlayer
import MediaPlayer
import Nuke
import ScreenCaptureKit
import SwiftUI
import XCTest

@testable import another_iptv_player

@MainActor
final class MacInteractionTests: XCTestCase {
  /// Optional provider acceptance run. The regular suite uses local media.
  func testConfiguredProviderPlayback() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let host = env["IPTV_ACCEPTANCE_HOST"], let user = env["IPTV_ACCEPTANCE_USER"],
          let password = env["IPTV_ACCEPTANCE_PASSWORD"], let kind = env["IPTV_ACCEPTANCE_KIND"],
          let id = env["IPTV_ACCEPTANCE_ID"], let number = Int(id) else {
      throw XCTSkip("Requires an explicitly configured provider and media ID.")
    }
    let database = AppDatabase.shared
    var source = Playlist(name: "Provider", serverURL: host, username: user, password: password)
    if kind == "live" {
      var draft = SourceDraft(kind: .xtream)
      draft.name = source.name
      draft.address = host
      draft.username = user
      draft.password = password
      source = try await draft.save(in: database, status: { _ in }, committing: {})
      let playlistID = source.id
      let counts = try await database.read { db in
        try ["liveStream", "vodStream", "series"].map { table in
          try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM " + table + " WHERE playlistId = ?",
                           arguments: [playlistID]) ?? 0
        }
      }
      XCTAssertTrue(counts.allSatisfy { $0 > 0 })
      print("Imported live, film and series counts", counts)
    }
    let client = XtreamAPIClient(playlist: source)
    _ = try await client.verify()
    let links = PlaybackURLBuilder(playlist: source)
    let ext = env["IPTV_ACCEPTANCE_EXTENSION"]
    let url: URL?
    switch kind {
    case "live":
      let groups = try await client.getLiveCategories()
      XCTAssertFalse(groups.isEmpty)
      _ = try await client.getShortEPG(streamId: number)
      url = links.liveURL(streamId: number)
    case "vod":
      _ = try await client.getVODInfo(vodId: number)
      url = links.movieURL(streamId: number, containerExtension: ext)
    case "series":
      let seriesID = try XCTUnwrap(env["IPTV_ACCEPTANCE_SERIES"].flatMap(Int.init))
      _ = try await client.getSeriesInfo(seriesId: seriesID)
      url = links.seriesURL(streamId: id, containerExtension: ext)
    default:
      throw TestFailure("Unknown media type")
    }
    let session = DesktopPlayback(database: database)
    let media = MediaSelection(url: try XCTUnwrap(url), playlistId: source.id, streamId: id,
                               type: kind, title: "Acceptance playback")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let window = window(for: SourceLibrary().modifier(MacPlaybackPresentation(playback: session))
      .environment(\.appDatabase, database).environmentObject(session)
      .environmentObject(LocalizationManager.shared).defaultAppStorage(defaults))
    defer {
      session.close()
      window.close()
      EPGStore.shared.setActivePlaylist(nil)
      _ = try? database.writeSync { try source.delete($0) }
    }
    if kind == "live" {
      try await waitFor("Guide is available") { self.named(L("epg.guide.title"), window) != nil }
      try selectSidebarRow(L("epg.guide.title"), in: window)
      func guideTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.numberOfRows > 100 { return table }
        return view.subviews.lazy.compactMap { guideTable(in: $0) }.first
      }
      try await waitFor("Provider guide rows", timeout: 90) {
        window.contentView.flatMap(guideTable) != nil
      }
      let table = try XCTUnwrap(window.contentView.flatMap(guideTable))
      let target = table.numberOfRows / 2
      table.scrollRowToVisible(target)
      try await waitFor("Provider guide scrolls to its middle") {
        NSLocationInRange(target, table.rows(in: table.visibleRect))
      }
    }
    session.start(media)
    try await waitFor("Real stream plays", timeout: 45) {
      session.engine.isPlaybackEstablished && session.position > 5
    }
    if kind != "live" {
      session.toggle()
      try await waitFor("Pause") { session.isPaused }
      session.seek(to: 20)
      session.toggle()
      try await waitFor("Resume after seek", timeout: 25) { !session.isPaused && session.position > 22 }
    }
    if kind == "series" {
      try await waitFor("Provider episode offers PiP") { session.engine.isPictureInPicturePossible }
      session.engine.startPictureInPicture()
      try await waitFor("Provider episode enters PiP") { session.engine.isPiPActive }
      let output = try XCTUnwrap((session.engine.layer?.player as? KSMEPlayer)?.videoOutput)
      for _ in 0..<8 {
        let frame = try XCTUnwrap(output.pixelBuffer)
        let position = session.position
        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(output.pixelBuffer !== frame)
        XCTAssertGreaterThan(session.position, position + 1)
      }
      session.engine.stopPictureInPicture()
      try await waitFor("Episode returns to inline playback") { !session.engine.isPiPActive }
    }
    XCTAssertNil(session.engine.playbackFailureMessage)
    if let toolbar = window.toolbar {
      XCTAssertFalse(toolbar.isVisible)
      session.expanded = false
      try await waitFor("Catalogue toolbar returns") { toolbar.isVisible }
    }
  }

  private final class FullScreenTestWindow: NSWindow {
    private(set) var fullScreenRequests = 0
    override func toggleFullScreen(_ sender: Any?) { fullScreenRequests += 1 }
  }

  private func window<V: View>(for view: V, in existing: NSWindow? = nil,
                               minimumSize: NSSize = NSSize(width: 800, height: 560)) -> NSWindow {
    let window = existing ?? NSWindow(
      contentRect: CGRect(x: 40, y: 80, width: 1140, height: 790),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingController(rootView: view.frame(minWidth: minimumSize.width, minHeight: minimumSize.height))
    host.sizingOptions = []
    host.view.frame = window.contentLayoutRect
    window.contentViewController = host
    window.setContentSize(NSSize(width: 1140, height: 738))
    window.center()
    window.makeKeyAndOrderFront(nil)
    return window
  }

  private func waitFor(_ description: String, timeout: TimeInterval = 8, _ ready: () -> Bool)
    async throws
  {
    let deadline = Date().addingTimeInterval(timeout)
    while !ready() {
      if Date() >= deadline { throw TestFailure(description) }
      try await Task.sleep(for: .milliseconds(60))
    }
  }

  private func attribute(_ element: NSObject, _ key: String) -> Any? {
    guard element.responds(to: NSSelectorFromString(key)) else { return nil }
    return element.value(forKey: key)
  }
  private func accessible(_ window: NSWindow) -> [NSObject] {
    window.contentView?.layoutSubtreeIfNeeded()
    var seen = Set<ObjectIdentifier>()
    func walk(_ element: NSObject) -> [NSObject] {
      guard seen.insert(ObjectIdentifier(element)).inserted else { return [] }
      return [element]
        + (attribute(element, "accessibilityChildren") as? [NSObject] ?? []).flatMap(walk)
    }
    func nativeChildren(_ view: NSView) -> [NSObject] {
      walk(view) + view.subviews.flatMap(nativeChildren)
    }
    let root = window.contentView?.superview ?? window.contentView
    return walk(window) + (root.map(nativeChildren) ?? [])
  }
  private func named(_ label: String, _ window: NSWindow) -> NSObject? {
    accessible(window).first { element in
      ["accessibilityLabel", "accessibilityTitle", "accessibilityValue", "accessibilityHelp"]
        .contains {
          attribute(element, $0) as? String == label
        }
    }
  }
  private func press(_ label: String, in window: NSWindow) async throws {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    let button = accessible(window).first { el in
      attribute(el, "accessibilityLabel") as? String == label && el.responds(to: selector)
    }
    guard let button else { throw TestFailure("Cannot press \(label)") }
    button.perform(selector)
    try await Task.sleep(for: .milliseconds(250))
  }
  private func capture(_ window: NSWindow, name: String) async throws {
    guard #available(macOS 14.4, *) else { return }
    window.displayIfNeeded()
    CATransaction.flush()
    // Allow WindowServer to composite the submitted frame before capturing it.
    try await Task.sleep(for: .milliseconds(100))
    let content = try await SCShareableContent.currentProcess
    guard let own = content.windows.first(where: { $0.windowID == UInt32(window.windowNumber) })
    else { throw TestFailure("Missing own test window") }
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width) * 2
    config.height = Int(window.frame.height) * 2
    config.ignoreShadowsSingleWindow = true
    config.showsCursor = false
    // ScreenCaptureKit can reject a capture immediately after an AVPlayer releases
    // its surface. Retry that transient capture failure, retaining real screenshots.
    for attempt in 0..<3 {
      do {
        let cg = try await SCScreenshotManager.captureImage(
          contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: config)
        let attachment = XCTAttachment(image: NSImage(cgImage: cg, size: window.frame.size))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return
      } catch {
        let failure = error as NSError
        guard failure.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
          failure.code == -3811 else { throw error }
        if attempt == 2 {
          // Some WindowServer configurations refuse streams for popovers.
          // Render the contents of that same native auxiliary window directly.
          guard window.parent != nil, let view = window.contentView,
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw error }
          view.cacheDisplay(in: view.bounds, to: bitmap)
          let image = NSImage(size: view.bounds.size)
          image.addRepresentation(bitmap)
          let attachment = XCTAttachment(image: image)
          attachment.name = name
          attachment.lifetime = .keepAlways
          add(attachment)
          return
        }
        try await Task.sleep(for: .milliseconds(300))
      }
    }
  }

  func testStoreUpdateWaitsForPlayerAndSnoozesOfferedVersion() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let server = LocalHTTPServer(directory: dir)
    try server.start()
    defer { server.stop() }
    let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/lookup"))
    let suite = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    func publish(version: String, minimum: String) throws {
      let record = [
        "version": version, "minimumOsVersion": minimum,
        "trackViewUrl": "https://apps.apple.com/app/id123",
      ]
      try JSONSerialization.data(withJSONObject: ["results": [record]]).write(
        to: dir.appendingPathComponent("lookup"), options: .atomic)
    }
    try publish(version: "99.1", minimum: "999.0")
    let unsupported = AppUpdateChecker(defaults: defaults, lookupURL: endpoint)
    await unsupported.checkIfNeeded()?.value
    XCTAssertNil(unsupported.availableUpdate)
    try publish(version: "99.1", minimum: "14.0")
    let checker = AppUpdateChecker(defaults: defaults, lookupURL: endpoint)
    checker.isPlayerInFront = true
    var openedURL: URL?
    let window = window(
      for: Text("Library").modifier(AppUpdateOffer(updateChecker: checker))
        .environment(
          \.openURL,
          OpenURLAction { url in
            openedURL = url
            return .handled
          }))
    defer { window.close() }
    await checker.checkIfNeeded()?.value
    XCTAssertEqual(checker.availableUpdate?.version, "99.1")
    XCTAssertNil(window.attachedSheet)
    checker.isPlayerInFront = false
    try await waitFor("Store update offered after player closes") { window.attachedSheet != nil }
    let sheet = try XCTUnwrap(window.attachedSheet)
    try await capture(sheet, name: "Store update")
    try await press(L("update.later"), in: sheet)
    XCTAssertEqual(defaults.string(forKey: "update.dismissedVersion"), "99.1")
    let snoozed = AppUpdateChecker(defaults: defaults, lookupURL: endpoint)
    await snoozed.checkIfNeeded()?.value
    XCTAssertNil(snoozed.availableUpdate)
    try publish(version: "99.2", minimum: "14.0")
    let newer = AppUpdateChecker(defaults: defaults, lookupURL: endpoint)
    await newer.checkIfNeeded()?.value
    XCTAssertEqual(newer.availableUpdate?.version, "99.2")
    try await waitFor("Snoozed offer closes") { window.attachedSheet == nil }
    checker.availableUpdate = newer.availableUpdate
    try await waitFor("New version can be opened") { window.attachedSheet != nil }
    try await press(L("update.action"), in: XCTUnwrap(window.attachedSheet))
    XCTAssertEqual(openedURL, newer.availableUpdate?.storeURL)
  }

  func testReviewRequiresFourLaunchesAndAnAvailableWindow() throws {
    let suite = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var attempts = 0
    for _ in 1...3 {
      let manager = RatingManager(defaults: defaults)
      manager.registerSuccessfulSession()
      manager.registerSuccessfulSession()
      manager.requestReviewIfAppropriate {
        attempts += 1
        return true
      }
    }
    XCTAssertEqual(attempts, 0)
    let manager = RatingManager(defaults: defaults)
    manager.registerSuccessfulSession()
    manager.requestReviewIfAppropriate(in: nil) { XCTFail("A review needs an active window") }
    XCTAssertNil(defaults.object(forKey: "rating.lastPromptVersion"))
    manager.requestReviewIfAppropriate {
      attempts += 1
      return true
    }
    manager.requestReviewIfAppropriate {
      attempts += 1
      return true
    }
    XCTAssertEqual(attempts, 1)
    defaults.set("older", forKey: "rating.lastPromptVersion")
    manager.requestReviewIfAppropriate {
      attempts += 1
      return true
    }
    XCTAssertEqual(attempts, 1)
    defaults.set(
      Calendar.current.date(byAdding: .day, value: -91, to: .now), forKey: "rating.lastPromptDate")
    manager.requestReviewIfAppropriate {
      attempts += 1
      return true
    }
    XCTAssertEqual(attempts, 2)

  }

  func testCancelSourceRefreshWhileProviderIsSilent() async throws {
    let panel = MockPanelServer(stream: .init(transportStream: Data()), script: .silent)
    try panel.start()
    defer { panel.stop() }
    let source = Playlist(name: "Local panel", serverURL: panel.streamURL.absoluteString,
                          type: .m3u, epgEnabled: false)
    let db = AppDatabase.empty()
    let channels = try await M3UParser.parseAsync(
      "#EXTM3U\n#EXTINF:-1,Existing news\nhttps://media.invalid/news.ts").channels
    try await M3UImporter.replace(playlist: source, channels: channels, epgURL: nil, in: db)
    let window = window(for: MacPreferences(source: source, edit: { _ in })
      .environment(\.appDatabase, db).environmentObject(LocalizationManager.shared))
    defer { window.close() }
    try await press(L("settings.m3u.source"), in: window)
    try await press(L("settings.m3u.refresh_url"), in: window)
    try await waitFor("Request in flight") { panel.stats.open == 1 }
    try await press(L("common.cancel"), in: window)
    try await waitFor("Cancellation restores idle controls") {
      self.named(L("common.cancel"), window) == nil && panel.stats.open == 0
    }
    XCTAssertNil(self.named(L("common.try_again"), window))
    try await press(L("settings.m3u.refresh_url"), in: window)
    try await waitFor("Second request in flight") { panel.stats.admitted == 2 && panel.stats.open == 1 }
    try await press(ML("general"), in: window)
    try await waitFor("Leaving settings cancels the pending request") { panel.stats.open == 0 }
    let saved = try await db.read {
      try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch($0).map(\.title)
    }
    XCTAssertEqual(saved, ["Existing news"])
  }

  func testSourceRefreshRetriesTheCatalogueWithoutReplacingItOnFailure() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let server = LocalHTTPServer(directory: dir)
    try server.start()
    defer { server.stop() }
    let source = Playlist(name: "Live channels", serverURL: "http://127.0.0.1:\(server.port)/guide.m3u",
                          type: .m3u, epgEnabled: false)
    let db = AppDatabase.empty()
    let old = "#EXTM3U\n#EXTINF:-1,Original channel\nhttps://media.invalid/old.ts"
    let channels = try await M3UParser.parseAsync(old).channels
    try await M3UImporter.replace(playlist: source, channels: channels, epgURL: nil, in: db)
    let window = window(for: MacPreferences(source: source, edit: { _ in })
      .environment(\.appDatabase, db).environmentObject(LocalizationManager.shared))
    defer { window.close() }
    try await press(L("settings.m3u.source"), in: window)
    try await press(L("settings.m3u.refresh_url"), in: window)
    try await waitFor("Failed sync has an inline retry") {
      self.named(L("common.try_again"), window) != nil
    }
    XCTAssertNil(window.attachedSheet)
    func titles() async throws -> [String] {
      try await db.read { try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch($0).map(\.title) }
    }
    let before = try await titles()
    XCTAssertEqual(before, ["Original channel"])
    try await capture(window, name: "Catalogue refresh failure")
    try old.replacingOccurrences(of: "Original channel", with: "Updated channel")
      .write(to: dir.appendingPathComponent("guide.m3u"), atomically: true, encoding: .utf8)
    try await press(L("common.try_again"), in: window)
    try await waitFor("Refresh completion shown") {
      self.named(L("epg.last_updated"), window) != nil && self.named(L("common.try_again"), window) == nil
    }
    let after = try await titles()
    XCTAssertEqual(after, ["Updated channel"])
  }

  func testDelayedM3URefreshCannotReplaceEditedSourceInSettings() async throws {
    let provider = MockPanelServer(stream: .init(transportStream: Data()), script: .silent)
    try provider.start()
    defer { provider.stop() }
    let source = Playlist(name: "Original news", serverURL: provider.streamURL.absoluteString,
                          type: .m3u, epgEnabled: false)
    let db = AppDatabase.empty()
    let original = "#EXTM3U\n#EXTINF:-1,Local news\nhttps://media.invalid/news.ts"
    let channels = try await M3UParser.parseAsync(original).channels
    try await M3UImporter.replace(playlist: source, channels: channels, epgURL: nil, in: db)
    let window = window(for: MacPreferences(source: source, edit: { _ in })
      .environment(\.appDatabase, db).environmentObject(LocalizationManager.shared))
    defer { window.close() }
    try await press(L("settings.m3u.source"), in: window)
    try await press(L("settings.m3u.refresh_url"), in: window)
    try await waitFor("Old provider request has reached server") { provider.stats.open == 1 }
    _ = try await db.updatePlaylist(id: source.id) {
      $0.serverURL = "https://new.invalid/news.m3u"
      $0.name = "Replacement"
    }
    provider.sendPendingPlaylist(original.replacingOccurrences(of: "Local news", with: "Stale news"))
    let message = L("misc.refresh_error", L("playlist.import.changed"))
    try await waitFor("Late provider response reports inline conflict") { self.named(message, window) != nil }
    XCTAssertNil(named(L("common.try_again"), window))
    XCTAssertNil(window.attachedSheet)
    let result = try await db.read { db in
      (try Playlist.fetchOne(db, key: source.id)?.name,
       try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch(db).map(\.title))
    }
    XCTAssertEqual(result.0, "Replacement")
    XCTAssertEqual(result.1, ["Local news"])
    try await capture(window, name: "Late provider response in source settings")
    try await press(ML("reload_source"), in: window)
    try await waitFor("Reload reflects latest name and removes conflict") {
      self.named("Replacement", window) != nil && self.named(message, window) == nil
    }
  }

  func testPastingXtreamAccountIntoNativeServerField() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let panel = root.appendingPathComponent("panel")
    try FileManager.default.createDirectory(at: panel, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(#"{"user_info":{"auth":0}}"#.utf8).write(to: panel.appendingPathComponent("player_api.php"))
    let server = LocalHTTPServer(directory: root)
    try server.start()
    defer { server.stop() }
    let base = "http://127.0.0.1:\(server.port)/panel"
    var closed = false
    let window = window(for: SourceEditor(kind: .xtream, saved: { _ in }, cancel: { closed = true }))
    defer { window.close() }
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let formFields = fields(try XCTUnwrap(window.contentView))
    let nameField = try XCTUnwrap(formFields.first { $0.placeholderString == L("add_playlist.name_placeholder") })
    try await waitFor("New source opens ready to type its name") { nameField.currentEditor() != nil }
    let address = try XCTUnwrap(formFields.first { $0.placeholderString == "https://" })
    nameField.currentEditor()?.insertNewline(nil)
    try await waitFor("Return moves from name to address") { address.currentEditor() != nil }
    let editor = try XCTUnwrap(address.currentEditor() as? NSTextView)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString(base + "/get.php?username=demo&password=a%2Bb", forType: .string)
    XCTAssertTrue(editor.readSelection(from: pasteboard))
    try await waitFor("Pasted account fills native login fields") {
      address.stringValue == base &&
        formFields.contains { $0.stringValue == "127.0.0.1" } &&
        formFields.contains { $0.stringValue == "demo" } &&
        formFields.contains { $0 is NSSecureTextField && $0.stringValue == "a+b" }
    }
    address.currentEditor()?.insertNewline(nil)
    let username = try XCTUnwrap(formFields.first { $0.stringValue == "demo" })
    try await waitFor("Return moves from address to username") { username.currentEditor() != nil }
    username.currentEditor()?.insertNewline(nil)
    let password = try XCTUnwrap(formFields.first { $0 is NSSecureTextField })
    try await waitFor("Return moves to the secure password field") { password.currentEditor() != nil }
    password.currentEditor()?.insertNewline(nil)
    try await waitFor("Rejected sign-in focuses the username and keeps the entered credentials") {
      self.named(L("misc.xtream.auth_error"), window) != nil &&
        formFields.contains { $0.stringValue == "demo" && $0.currentEditor() != nil } &&
        formFields.contains { $0 is NSSecureTextField && $0.stringValue == "a+b" } &&
        address.stringValue == base
    }
    func discardPrompt() -> NSWindow? {
      ([window] + (window.childWindows ?? []) + [window.attachedSheet].compactMap { $0 })
        .first { self.named(L("onboarding.form.discard"), $0) != nil }
    }
    try await press(L("common.cancel"), in: window)
    try await waitFor("Edited source offers discard") { discardPrompt() != nil }
    try await press(L("onboarding.form.keep_editing"), in: XCTUnwrap(discardPrompt()))
    XCTAssertFalse(closed)
    XCTAssertEqual(address.stringValue, base)
    try await press(L("common.cancel"), in: window)
    try await waitFor("Discard available again") { discardPrompt() != nil }
    try await press(L("onboarding.form.discard"), in: XCTUnwrap(discardPrompt()))
    XCTAssertTrue(closed)
  }

  func testSourceEditorRetriesInvalidRemoteListWithoutLosingAddress() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = LocalHTTPServer(directory: root)
    try server.start()
    defer { server.stop() }
    let file = root.appendingPathComponent("channels.m3u")
    try "#EXTM3U\n".write(to: file, atomically: true, encoding: .utf8)
    let db = AppDatabase.empty()
    let original = Playlist(name: "Home", serverURL: "https://previous.invalid/list.m3u", type: .m3u)
    try db.writeSync { try original.insert($0) }
    var saved: Playlist?
    let window = window(for: SourceEditor(kind: .m3u, editing: original, saved: { saved = $0 }, cancel: {})
      .environment(\.appDatabase, db))
    defer { window.close() }
    func addressField(_ view: NSView) -> NSTextField? {
      if let field = view as? NSTextField, field.isEditable, field.stringValue == original.serverURL { return field }
      return view.subviews.lazy.compactMap(addressField).first
    }
    let field = try XCTUnwrap(window.contentView.flatMap(addressField))
    window.makeFirstResponder(field)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    let address = "http://127.0.0.1:\(server.port)/channels.m3u"
    editor.selectAll(nil)
    editor.insertText(address, replacementRange: editor.selectedRange())
    try XCTUnwrap(field.currentEditor()).insertNewline(nil)
    try await waitFor("Parsing failure clears progress and retains address") {
      self.named(L("parser.error.no_channels"), window) != nil &&
        self.named(L("add_m3u.parsing"), window) == nil && field.stringValue == address && field.currentEditor() != nil
    }
    XCTAssertNil(saved)
    try "#EXTM3U\n#EXTINF:-1,Home News\nhttps://fixture.invalid/live.ts".write(to: file, atomically: true, encoding: .utf8)
    try XCTUnwrap(field.currentEditor()).insertNewline(nil)
    try await waitFor("Retry saves corrected list in the same editor") { saved?.serverURL == address }
    XCTAssertEqual(saved?.id, original.id)
  }

  func testSourceEditorReloadsChangedProviderBeforeSave() async throws {
    let db = AppDatabase.empty()
    let original = Playlist(name: "Original provider", serverURL: "", type: .m3u)
    try db.writeSync { try original.insert($0) }
    var saved: Playlist?
    let window = window(for: SourceEditor(kind: .m3u, editing: original, saved: { saved = $0 }, cancel: {})
      .environment(\.appDatabase, db))
    defer { window.close() }
    try await waitFor("Editor identifies the saved local source and offers file replacement") {
      self.named(L("playlists.local_file"), window) != nil &&
        self.named(L("add_m3u.pick_another_file"), window) != nil
    }
    _ = try await db.updatePlaylist(id: original.id) {
      $0.name = "Latest provider"
      $0.serverURL = "https://latest.invalid/list.m3u"
      $0.epgEnabled = false
    }
    try await press(L("common.save"), in: window)
    try await waitFor("Editor exposes reload action") {
      self.named(ML("reload_source"), window) != nil && self.named(L("playlist.import.changed"), window) != nil
    }
    XCTAssertNil(saved)
    try await capture(window, name: "Source editor conflict recovery")
    try await press(ML("reload_source"), in: window)
    try await waitFor("Editor reads latest source values") {
      self.named("Latest provider", window) != nil && self.named(ML("reload_source"), window) == nil &&
        self.named(L("playlists.local_file"), window) == nil && self.named(L("add_m3u.pick_file"), window) != nil &&
        self.named(L("add_m3u.pick_another_file"), window) == nil
    }
    try await press(L("common.save"), in: window)
    try await waitFor("Save returns actual current settings") {
      saved?.name == "Latest provider" && saved?.serverURL == "https://latest.invalid/list.m3u" && saved?.epgEnabled == false
    }
  }

  func testAccountErrorAndRetryInSourceSettings() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let response = dir.appendingPathComponent("player_api.php")
    try Data(#"{"user_info":{"auth":0}}"#.utf8).write(to: response)
    let server = LocalHTTPServer(directory: dir)
    try server.start()
    defer { server.stop() }
    let source = Playlist(name: "Test provider", serverURL: "http://127.0.0.1:\(server.port)",
                          username: "sample", password: "fixture", epgEnabled: false)
    let window = window(for: MacPreferences(source: source, edit: { _ in })
      .environment(\.appDatabase, AppDatabase.empty()).environmentObject(LocalizationManager.shared))
    defer { window.close() }
    try await press(L("settings.m3u.source"), in: window)
    let rejection = NetworkErrorText.describe(XtreamError.unauthenticated)
    try await waitFor("Account rejection visible alongside retry") {
      self.named(rejection, window) != nil && self.named(ML("check_account"), window) != nil
    }
    XCTAssertNil(window.attachedSheet)
    try await capture(window, name: "Source account error")
    let success = #"{"user_info":{"auth":1,"active_cons":2,"max_connections":4,"message":"Account renewed"}}"#
    try Data(success.utf8).write(to: response, options: .atomic)
    try await press(ML("check_account"), in: window)
    try await waitFor("Renewed account replaces rejection") {
      self.named("Account renewed", window) != nil && self.named(rejection, window) == nil
    }
  }

  func testLibraryAndSettingsShareWindow() async throws {
    let database = AppDatabase.empty()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let source = Playlist(name: "Harbor", serverURL: "https://catalog.invalid")
    try database.writeSync { db in
      try source.insert(db)
      try DBLiveStream(streamId: 1, name: "Harbor News", playlistId: source.id).insert(db)
    }
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let session = DesktopPlayback(database: database)
    let window = window(
      for: SourceLibrary().environment(\.appDatabase, database)
        .environmentObject(LocalizationManager.shared).environmentObject(session).defaultAppStorage(
          defaults))
    defer { window.close() }
    try await waitFor("Discover shows the source channel") {
      self.named("Harbor News", window) != nil
    }
    try await capture(window, name: "Discover")
    try await press(ML("see_all"), in: window)
    let before = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.map(\.windowNumber)
      .sorted()
    func tables(_ view: NSView) -> [NSTableView] {
      (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
    }
    try await waitFor("Live table contains the imported channel") {
      window.contentView.map {
        tables($0).contains { $0.numberOfColumns == 3 && $0.numberOfRows == 1 }
      } == true
    }
    try await capture(window, name: "Live catalogue")
    try await press(L("dashboard.settings"), in: window)
    try await waitFor("Language picker") {
      self.named(L("settings.language.title"), window) != nil
        || self.named(L("settings.language.section"), window) != nil
    }
    XCTAssertNil(window.attachedSheet)
    XCTAssertEqual(
      before, NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.map(\.windowNumber).sorted()
    )
    try await capture(window, name: "Inline settings")
  }

  func testFiniteFileListedAsLiveEndsWithoutReopening() async throws {
    let movie = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let session = DesktopPlayback(database: .empty())
    defer { session.close() }
    let channel = MediaSelection(
      url: movie, playlistId: UUID(), streamId: "finite", type: "live", title: "Finite broadcast")
    session.start(channel)
    try await waitFor("Finite broadcast duration available") {
      session.engine.isPlaybackEstablished && session.duration > 1
    }
    let original = try XCTUnwrap(session.engine.layer)
    try await waitFor("Finite broadcast ends", timeout: 15) { session.engine.isCompleted }
    try await Task.sleep(for: .milliseconds(700))
    XCTAssertTrue(session.engine.isCompleted)
    XCTAssertFalse(session.waitingToReconnect)
    XCTAssertTrue(session.engine.layer === original)
  }

  private func retryUsingPictureAccessibility(in window: NSWindow) throws {
    let picture = try XCTUnwrap(named(ML("video_zoom"), window))
    let actions = attribute(picture, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]
    let retry = try XCTUnwrap(actions?.first { $0.name == L("common.try_again") })
    XCTAssertEqual(retry.handler?(), true)
  }

  func testLiveRetryBudgetEndsAndAllowsManualRestart() async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(
      stream: .init(transportStream: try Data(contentsOf: url)), script: .chunkedStream, pace: 2)
    try panel.start()
    defer { panel.stop() }
    let session = DesktopPlayback(database: .empty())
    let channel = MediaSelection(
      url: panel.streamURL, playlistId: UUID(), streamId: "bounded", type: "live", title: "Coast")
    let window = window(
      for: MacPlayerView(session: session, engine: session.engine, media: channel))
    defer {
      session.close()
      window.close()
    }
    session.start(channel)
    for connection in 1...4 {
      try await waitFor("Playback established on attempt \(connection)", timeout: 20) {
        panel.stats.admitted == connection && session.engine.isPlaybackEstablished
          && session.position > 0.2
      }
      panel.finishStream()
    }
    try await waitFor("Bounded retries give way to an ended state", timeout: 20) {
      session.engine.isCompleted && self.named(L("player.ended"), window) != nil
    }
    XCTAssertFalse(session.waitingToReconnect)
    try retryUsingPictureAccessibility(in: window)
    try await waitFor("Explicit restart starts fresh playback", timeout: 20) {
      panel.stats.admitted == 5 && session.engine.isPlaybackEstablished && session.position > 0.2
    }
    panel.finishStream()
    try await waitFor("Restart restores automatic reconnect budget", timeout: 20) {
      session.waitingToReconnect
    }
    session.close()
    try await Task.sleep(for: .seconds(1))
    XCTAssertEqual(panel.stats.admitted, 5)
    XCTAssertNil(session.current)
  }

  func testUnavailableChannelOffersManualRetryAfterAutomaticAttempt() async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: url)), pace: 2)
    try panel.start()
    defer { panel.stop() }
    let occupyingRequest = URLSession.shared.dataTask(with: panel.streamURL)
    occupyingRequest.resume()
    defer { occupyingRequest.cancel() }
    try await waitFor("Provider slot occupied") { panel.stats.open == 1 }
    let session = DesktopPlayback(database: .empty())
    let channel = MediaSelection(
      url: panel.streamURL, playlistId: UUID(), streamId: "manual", type: "live", title: "Coast")
    let window = window(
      for: MacPlayerView(session: session, engine: session.engine, media: channel))
    defer {
      session.close()
      window.close()
    }
    session.start(channel)
    try await waitFor("Manual retry shown after second rejection", timeout: 20) {
      panel.stats.refused >= 2 && !session.waitingToReconnect
        && self.named(L("common.try_again"), window) != nil
    }
    let refused = panel.stats.refused
    try await Task.sleep(for: .seconds(1.2))
    XCTAssertEqual(panel.stats.refused, refused)
    try await capture(window, name: "Channel unavailable")
    occupyingRequest.cancel()
    try await waitFor("Account slot released") { panel.stats.open == 0 }
    try retryUsingPictureAccessibility(in: window)
    try await waitFor("Manual retry plays the channel", timeout: 20) {
      session.engine.isPlaybackEstablished && session.position > 0.2
    }
  }

  func testTransientPanelRejectionRetriesAfterSlotIsFreed() async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: url)), pace: 2)
    try panel.start()
    defer { panel.stop() }
    let occupyingRequest = URLSession.shared.dataTask(with: panel.streamURL)
    occupyingRequest.resume()
    defer { occupyingRequest.cancel() }
    try await waitFor("Provider's single account slot occupied") { panel.stats.open == 1 }
    let session = DesktopPlayback(database: .empty())
    defer { session.close() }
    let channel = MediaSelection(
      url: panel.streamURL, playlistId: UUID(), streamId: "slot", type: "live", title: "Coast")
    let window = window(
      for: MacPlayerView(session: session, engine: session.engine, media: channel))
    defer { window.close() }
    session.start(channel)
    try await waitFor("Temporary 403 schedules retry", timeout: 20) {
      panel.stats.refused > 0 && session.waitingToReconnect
    }
    occupyingRequest.cancel()
    try await capture(window, name: "Reconnecting live channel")
    try await waitFor("Playback recovers when provider releases its slot", timeout: 20) {
      panel.stats.admitted >= 2 && session.engine.isPlaybackEstablished && session.position > 0.2
    }
    XCTAssertNil(session.engine.playbackFailureMessage)
  }

  func testAbruptLiveConnectionResetResumesNewData() async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: url)), pace: 1)
    try panel.start()
    defer { panel.stop() }
    let session = DesktopPlayback(database: .empty())
    defer { session.close() }
    session.start(
      MediaSelection(
        url: panel.streamURL, playlistId: UUID(), streamId: "reset", type: "live", title: "Coast"))
    try await waitFor("Live channel established", timeout: 20) {
      session.engine.isPlaybackEstablished && session.position > 0.3
    }
    let stats = panel.stats
    panel.reset()
    do {
      try await waitFor("Fresh connection after TCP reset", timeout: 40) {
        panel.stats.admitted > stats.admitted && panel.stats.bytesSent > stats.bytesSent + 4000
          && !session.engine.isBuffering && session.engine.isPlaybackEstablished
          && session.position > 0.2
      }
    } catch {
      print(
        "TCP_RESET", panel.stats, session.position, session.duration, session.engine.isCompleted,
        session.engine.isPaused, session.engine.isBuffering,
        session.engine.playbackFailureMessage as Any)
      throw error
    }
    let position = session.position
    try await waitFor("Video advances after TCP reconnection") { session.position > position + 0.2 }
  }

  func testInterruptedLiveChannelReconnects() async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(
      stream: .init(transportStream: try Data(contentsOf: url)), script: .chunkedStream, pace: 2)
    try panel.start()
    defer { panel.stop() }
    let session = DesktopPlayback(database: .empty())
    defer { session.close() }
    let channel = MediaSelection(
      url: panel.streamURL, playlistId: UUID(), streamId: "coast", type: "live", title: "Coast")
    session.start(channel)
    try await waitFor("Live HTTP stream starts", timeout: 20) {
      session.engine.isPlaybackEstablished && session.position > 0.2
    }
    let original = try XCTUnwrap(session.engine.layer)
    let connections = panel.stats.admitted
    panel.finishStream()
    try await waitFor("Media decoder reopens disconnected live channel", timeout: 35) {
      panel.stats.admitted > connections && session.engine.layer !== original
        && session.engine.isPlaybackEstablished && session.position > 0.2
    }
    XCTAssertEqual(session.current, channel)
  }

  func testChangingChannelCancelsPendingReconnect() async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(
      stream: .init(transportStream: try Data(contentsOf: url)), script: .chunkedStream, pace: 2)
    try panel.start()
    defer { panel.stop() }
    let session = DesktopPlayback(database: .empty())
    defer { session.close() }
    let sourceID = UUID()
    let channel = MediaSelection(
      url: panel.streamURL, playlistId: sourceID, streamId: "live", type: "live",
      title: "Old channel")
    session.start(channel)
    try await waitFor("Live HTTP stream opens", timeout: 20) {
      session.engine.isPlaybackEstablished && session.position > 0.2
    }
    panel.finishStream()
    try await waitFor("Owner waits before reconnecting", timeout: 30) { session.waitingToReconnect }
    let connections = panel.stats.admitted
    let local = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let next = MediaSelection(
      url: local, playlistId: sourceID, streamId: "next", type: "vod", title: "Next film")
    session.start(next)
    try await waitFor("New content plays past the previous retry deadline") {
      session.current == next && session.engine.isPlaybackEstablished && session.position > 1.0
    }
    XCTAssertEqual(panel.stats.admitted, connections)
  }

  func testOpeningChannelLogoYieldsToFirstLivePicture() async throws {
    let stream = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: stream)), pace: 2)
    panel.stall()
    try panel.start()
    defer { panel.stop() }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let logo = NSImage(size: NSSize(width: 120, height: 60), flipped: false) { rect in
      NSColor.systemGreen.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
      let title = NSAttributedString(string: "COAST", attributes: [
        .font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.black])
      title.draw(at: NSPoint(x: 19, y: 17))
      return true
    }
    try XCTUnwrap(logo.tiffRepresentation).write(to: folder.appendingPathComponent("coast.tiff"))
    let server = LocalHTTPServer(directory: folder)
    try server.start()
    defer { server.stop() }

    let session = DesktopPlayback(database: .empty())
    let media = MediaSelection(url: panel.streamURL, playlistId: UUID(), streamId: "coast",
      type: "live", title: "Coast", artwork: "http://127.0.0.1:\(server.port)/coast.tiff")
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer { session.close(); window.close() }
    session.start(media)
    try await waitFor("Opening live connection waits for first stream data") { panel.stats.open == 1 }
    XCTAssertFalse(session.engine.isPlaybackEstablished)
    try await capture(window, name: "Opening channel logo")
    panel.stall(atStreamSeconds: 120)
    try await waitFor("Live picture arrives on the same stream", timeout: 20) {
      session.engine.isPlaybackEstablished && session.engine.videoDisplayWidth > 0 && session.position > 0.25
    }
    try await capture(window, name: "Live channel after logo")
    XCTAssertEqual(panel.stats.admitted, 1)
  }

  func testSystemPlaybackMetadataAndMediaCommands() async throws {
    let movie = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let poster = NSImage(size: NSSize(width: 24, height: 36), flipped: false) { rect in
      NSColor.systemBlue.setFill()
      NSBezierPath(rect: rect).fill()
      return true
    }
    try XCTUnwrap(poster.tiffRepresentation).write(to: folder.appendingPathComponent("poster.tiff"))
    let server = LocalHTTPServer(directory: folder)
    try server.start()
    defer { server.stop() }
    let media = MediaSelection(
      url: movie, playlistId: UUID(), streamId: "system", type: "vod",
      title: "Night Crossing", secondaryTitle: "Harbor",
      artwork: "http://127.0.0.1:\(server.port)/poster.tiff")
    let session = DesktopPlayback(database: .empty())
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer { session.close(); window.close() }
    try await capture(window, name: "Opening movie poster")
    session.start(media)
    let center = MPNowPlayingInfoCenter.default()
    try await waitFor("System Now Playing title, poster and duration", timeout: 15) {
      let info = center.nowPlayingInfo
      return info?[MPMediaItemPropertyTitle] as? String == media.title
        && info?[MPMediaItemPropertyArtist] as? String == media.secondaryTitle
        && info?[MPMediaItemPropertyArtwork] is MPMediaItemArtwork
        && (info?[MPMediaItemPropertyPlaybackDuration] as? Double ?? 0) > 7
        && center.playbackState == .playing
    }
    try await capture(window, name: "Movie picture replaces opening poster")
    XCTAssertEqual(session.systemPlayback.perform(.pause), .success)
    try await waitFor("System pause stops playback and published rate") {
      session.isPaused && center.playbackState == .paused
        && center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0
    }
    XCTAssertEqual(session.systemPlayback.perform(.pause), .success)
    XCTAssertTrue(session.isPaused)
    XCTAssertEqual(session.systemPlayback.perform(.seek(3.2)), .success)
    try await waitFor("Remote seek reaches the video") { abs(session.position - 3.2) < 0.45 }
    XCTAssertEqual(session.systemPlayback.perform(.seek(3.65)), .success)
    try await waitFor("Short paused seek updates system clock") {
      let elapsed =
        center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0
      return abs(elapsed - 3.65) < 0.2
    }
    XCTAssertEqual(session.systemPlayback.perform(.speed(1.5)), .success)
    XCTAssertEqual(session.systemPlayback.perform(.play), .success)
    try await waitFor("Remote speed reflected by Now Playing") {
      center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5
    }
    XCTAssertEqual(session.systemPlayback.perform(.stop), .success)
    XCTAssertNil(center.nowPlayingInfo)
    XCTAssertNil(session.current)
  }

  func testPlaybackDiagnosticsAppearOnlyWhenEnabledAndFollowRealSeek() async throws {
    let database = AppDatabase.empty()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(false, forKey: "player.debugOverlayEnabled")
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let media = MediaSelection(url: url, playlistId: UUID(), streamId: "local", type: "vod", title: "Movie")
    let session = DesktopPlayback(database: database)
    let window = window(for: Color.clear.modifier(MacPlaybackPresentation(playback: session))
      .defaultAppStorage(defaults).environment(\.appDatabase, database))
    defer { session.close(); window.close() }
    session.start(media)
    try await waitFor("Video decoder has frame size") {
      session.engine.isPlaybackEstablished && session.engine.videoDisplayWidth > 0
    }
    session.toggle()
    let resolution = "RES  \(session.engine.videoDisplayWidth) × \(session.engine.videoDisplayHeight)"
    XCTAssertNil(named(resolution, window))
    try await press(L("player.dev_section"), in: window)
    let panel = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await capture(panel, name: "Player diagnostics controls")
    try await press(L("player.show_debug_overlay"), in: panel)
    panel.performClose(nil)
    try await waitFor("Native diagnostic overlay shows real decoded dimensions") {
      self.named(resolution, window) != nil && defaults.bool(forKey: "player.debugOverlayEnabled")
    }
    session.seek(to: 3)
    try await waitFor("Diagnostic overlay reports completed seek") {
      guard let latency = session.engine.lastSeekMilliseconds else { return false }
      return self.named("SEEK \(latency) ms", window) != nil
    }
    let codec = [session.engine.hwdecCurrent, session.engine.videoCodecName, session.engine.audioCodecName]
      .filter { !$0.isEmpty }.joined(separator: " / ")
    XCTAssertFalse(codec.isEmpty)
    XCTAssertNotNil(named("DEC  " + codec, window))
    try await capture(window, name: "Playing movie diagnostics")
    try await press(ML("minimize"), in: window)
    try await waitFor("Mini player dismisses diagnostic overlay") { self.named(resolution, window) == nil }
    try await press("Movie", in: window)
    try await waitFor("Expanded player restores preference") { self.named(resolution, window) != nil }
    try await press(L("player.dev_section"), in: window)
    let settings = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await press(L("player.show_debug_overlay"), in: settings)
    try await waitFor("Diagnostic overlay is disabled") {
      self.named(resolution, window) == nil && !defaults.bool(forKey: "player.debugOverlayEnabled")
    }
  }

  func testDiagnosticCopyActionsUseStreamURLAndAirPlayLog() async throws {
    let url = try XCTUnwrap(URL(string: "https://media.invalid/movie/fixture"))
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let window = window(for: MacDiagnosticControls(showOverlay: .constant(false), url: url, pasteboard: board))
    defer { window.close() }
    try await press(L("player.stream_url.copy"), in: window)
    XCTAssertEqual(board.string(forType: .string), url.absoluteString)
    try await press(L("player.debug.copy_airplay_log"), in: window)
    XCTAssertEqual(board.string(forType: .string), AirPlayLogExport.text())
  }

  func testBackgroundPreferenceControlsOwningWindowAndHiddenAppPlayback() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(false, forKey: "player.continuePlayingInBackground")
    let session = DesktopPlayback(database: .empty())
    let mediaURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let media = MediaSelection(url: mediaURL, playlistId: UUID(), streamId: "native", type: "vod", title: "Window movie")
    let native = NSWindow(contentRect: NSRect(x: 40, y: 80, width: 1140, height: 738),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    let window = window(for: MacPreferences(source: nil, edit: { _ in })
      .modifier(MacPlaybackPresentation(playback: session))
      .environmentObject(LocalizationManager.shared).defaultAppStorage(defaults), in: native)
    defer { session.close(); window.close() }
    session.start(media)
    try await waitFor("Movie starts before minimizing") { session.engine.isPlaybackEstablished && session.position > 0.1 }
    let other = NSWindow()
    other.isReleasedWhenClosed = false
    defer { other.close() }
    NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: other)
    XCTAssertFalse(session.isPaused)
    window.miniaturize(nil)
    try await waitFor("Minimizing the owning window pauses the decoder") { window.isMiniaturized && session.isPaused }
    window.deminiaturize(nil)
    try await waitFor("Window is restored without starting paused playback") { !window.isMiniaturized && session.isPaused }
    try await press(ML("minimize"), in: window)
    try await press(L("settings.player.title"), in: window)
    try await waitFor("Playback preference is visible") { self.named(L("settings.player.background.title"), window) != nil }
    try await capture(window, name: "Background playback setting")
    try await press(L("settings.player.background.title"), in: window)
    XCTAssertTrue(defaults.bool(forKey: "player.continuePlayingInBackground"))
    session.toggle()
    try await waitFor("Local playback resumes") { !session.isPaused && session.engine.isPlaybackEstablished }
    let before = session.position
    window.miniaturize(nil)
    try await waitFor("Enabled background playback advances while minimized") {
      window.isMiniaturized && !session.isPaused && session.position > before + 0.4
    }
    window.deminiaturize(nil)
    try await waitFor("Restored window still playing") { !window.isMiniaturized && !session.isPaused }
    try await press(L("settings.player.background.title"), in: window)
    XCTAssertFalse(defaults.bool(forKey: "player.continuePlayingInBackground"))
    NotificationCenter.default.post(name: NSApplication.didHideNotification, object: NSApp)
    try await waitFor("App hide notification pauses the decoder") { session.isPaused }
    let replacement = MediaSelection(url: mediaURL, playlistId: media.playlistId, streamId: "replacement",
                                     type: "vod", title: "Second movie")
    session.start(replacement)
    try await waitFor("An item loaded in the hidden app honors paused intent") {
      session.current?.streamId == "replacement" && session.engine.layer != nil && session.isPaused
    }
    NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: NSApp)
    XCTAssertTrue(session.isPaused)
    session.toggle()
    try await waitFor("An explicit play resumes the new movie") { session.engine.isPlaybackEstablished && session.position > 0.1 }
  }

  func testPictureInPicturePlaysAndReturnsToTheSameMovie() async throws {
    try await verifyPictureInPicture(resource: "selected-tracks", fileExtension: "mkv")
  }

  func testNativeMP4PictureInPicturePlaysAndReturnsToTheSameMovie() async throws {
    try await verifyPictureInPicture(resource: "pip-movie", fileExtension: "mp4")
  }

  func testLiveTransportStreamPlaysInSystemPictureInPicture() async throws {
    let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pip-channel", withExtension: "ts"))
    let server = LocalHTTPServer(directory: fixture.deletingLastPathComponent())
    try server.start()
    defer { server.stop() }
    let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/pip-channel.ts"))
    let media = MediaSelection(url: url, playlistId: UUID(), streamId: "pip-live", type: "live", title: "PiP channel")
    try await verifyPictureInPicture(media: media)
  }

  private func verifyPictureInPicture(resource: String, fileExtension: String) async throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: resource, withExtension: fileExtension))
    let media = MediaSelection(url: url, playlistId: UUID(), streamId: "pip", type: "vod", title: "PiP")
    try await verifyPictureInPicture(media: media)
  }

  private func verifyPictureInPicture(media: MediaSelection) async throws {
    let session = DesktopPlayback(database: .empty())
    let window = window(for: Color.clear.modifier(MacPlaybackPresentation(playback: session)),
      minimumSize: NSSize(width: 500, height: 340))
    if media.isLive { window.setContentSize(NSSize(width: 520, height: 350)) }
    defer { session.engine.stopPictureInPicture(); session.close(); window.close() }
    session.start(media)
    try await waitFor("Local movie offers system PiP") { session.engine.isPictureInPicturePossible }
    session.engine.togglePictureInPicture()
    try await waitFor("System PiP opens") { session.engine.isPiPActive }
    if let decoder = session.engine.layer?.player as? KSMEPlayer {
      let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? NSPanel }.first { $0.isVisible })
      func fitsPanel() -> Bool {
        guard let surface = decoder.videoOutput, let size = panel.contentView?.bounds.size else { return false }
        return abs(surface.bounds.width - size.width) <= 1 && abs(surface.bounds.height - size.height) <= 1
      }
      try await waitFor("Decoded picture fits the floating panel") {
        abs(panel.frame.width - window.frame.width) > 10 && fitsPanel()
      }
      if media.isLive {
        let original = panel.frame
        let ratio = original.height / original.width
        panel.setFrame(NSRect(x: 120, y: 120, width: 320, height: 320 * ratio), display: true)
        try await waitFor("Small PiP fits before enlargement") {
          panel.frame.width < window.frame.width && fitsPanel()
        }
        let width = max(original.width, window.frame.width + 20)
        let larger = NSRect(origin: NSPoint(x: 80, y: 120),
                            size: NSSize(width: width, height: width * original.height / original.width))
        panel.setFrame(larger, display: true)
        try await waitFor("Resizing PiP refits the complete video") {
          panel.frame.width > window.frame.width && fitsPanel()
        }
      }
    }
    let position = session.position
    try await waitFor("Picture in picture advances") { session.position > position + 1.6 }
    let controller = try XCTUnwrap(session.engine.pipController)
    if let controls = controller.contentSource?.sampleBufferPlaybackDelegate {
      controls.pictureInPictureController(controller, setPlaying: false)
      try await waitFor("PiP pause reaches the app") { session.engine.isPaused }
      controls.pictureInPictureController(controller, setPlaying: true)
      try await waitFor("PiP resume reaches the app") { !session.engine.isPaused }
    }
    window.miniaturize(nil)
    let restored = await withCheckedContinuation { continuation in
      session.engine.pictureInPictureController(controller, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: {
        continuation.resume(returning: $0)
      })
    }
    XCTAssertTrue(restored)
    XCTAssertFalse(window.isMiniaturized)
    let beforeReturn = session.position
    session.engine.togglePictureInPicture()
    try await waitFor("System PiP closes") { !session.engine.isPiPActive }
    XCTAssertEqual(session.current?.historyID, media.historyID)
    try await waitFor("Inline playback advances after PiP") { session.position > beforeReturn + 0.3 }
    session.engine.togglePictureInPicture()
    try await waitFor("PiP reopens on the same source") { session.engine.isPiPActive }
    session.engine.stopPictureInPicture()
    try await waitFor("Reopened PiP closes cleanly") { !session.engine.isPiPActive }
  }

  func testAspectSettingsStayOpenDuringPlayback() async throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let session = DesktopPlayback(database: .empty(), preferences: defaults)
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let media = MediaSelection(url: url, playlistId: UUID(), streamId: "settings", type: "vod", title: "Settings test")
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer { session.close(); window.close() }
    session.start(media)
    try await waitFor("Playing video") { session.engine.isPlaybackEstablished }
    try await press(L("settings.player.title"), in: window)
    let popover = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    let before = session.position
    try await Task.sleep(for: .seconds(3.4))
    XCTAssertGreaterThan(session.position, before)
    XCTAssertTrue(popover.isVisible)
    let fill = try XCTUnwrap(named(VideoAspectMode.fill.title, popover))
    fill.perform(NSSelectorFromString("accessibilityPerformPress"))
    try await waitFor("Aspect selection applied while playing") { session.aspect == .fill }
  }

  func testFullScreenPlayerHidesIdleControlsAndKeepsPausedControlsVisible() async throws {
    let session = DesktopPlayback(database: .empty())
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let media = MediaSelection(url: url, playlistId: UUID(), streamId: "fullscreen", type: "vod", title: "Fullscreen movie")
    let window = window(for: NavigationStack {
      Text("Library").navigationTitle("Library").toolbar { Button("Library action") {} }
    }.modifier(MacPlaybackPresentation(playback: session)), minimumSize: NSSize(width: 500, height: 340))
    defer { session.close(); window.close() }
    session.start(media)
    try await waitFor("Video and window controls ready") {
      session.engine.isPlaybackEstablished && self.named(ML("minimize"), window) != nil
    }
    XCTAssertEqual(window.aspectRatio, .zero)
    window.setContentSize(NSSize(width: 520, height: 370))
    try await waitFor("Compact window keeps its chosen dimensions during playback") {
      window.contentView?.bounds.size == NSSize(width: 520, height: 370)
        && self.named(ML("minimize"), window) != nil
    }
    try await capture(window, name: "Compact windowed player")
    NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
    try await waitFor("Playing fullscreen hides controls after inactivity", timeout: 6) {
      self.named(ML("minimize"), window) == nil && session.position > 2
    }
    XCTAssertNotEqual(window.toolbar?.isVisible, true)
    try await capture(window, name: "Fullscreen picture with idle controls hidden")
    let picture = try XCTUnwrap(named(ML("video_zoom"), window))
    let actions = attribute(picture, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]
    let reveal = try XCTUnwrap(actions?.first { $0.name == L("player.a11y.show_controls") })
    XCTAssertEqual(reveal.handler?(), true)
    try await waitFor("Accessible action reveals controls while video keeps playing") {
      !session.isPaused && self.named(ML("minimize"), window) != nil
    }
    let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
      characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
    window.sendEvent(event)
    try await waitFor("Space reveals controls and pauses fullscreen movie") {
      session.isPaused && self.named(ML("minimize"), window) != nil
    }
    try await Task.sleep(for: .seconds(3.3))
    XCTAssertNotNil(named(L("player.a11y.play"), window))
    try await capture(window, name: "Paused fullscreen controls")
    NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
    try await press(L("player.a11y.play"), in: window)
    try await Task.sleep(for: .seconds(3.3))
    XCTAssertNil(named(ML("minimize"), window))
  }

  func testDoubleClickEntersAndLeavesNativeFullscreenWithoutSeeking() async throws {
    let session = DesktopPlayback(database: .empty())
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek", withExtension: "mp4",
      subdirectory: "fixtures/playback"))
    let media = MediaSelection(url: url, playlistId: UUID(), streamId: "click", type: "vod", title: "Double click")
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    window.collectionBehavior.insert(.fullScreenPrimary)
    defer { session.close(); window.close() }
    session.start(media)
    try await waitFor("Movie advances before checking double click") { session.position > 0.2 }
    session.toggle()
    try await waitFor("Movie pauses") { session.isPaused }
    let before = session.position
    func doubleClick(fraction: CGFloat) throws {
      let picture = try XCTUnwrap(named(ML("video_zoom"), window))
      let rect = try XCTUnwrap((attribute(picture, "accessibilityFrame") as? NSValue)?.rectValue)
      let point = window.convertPoint(fromScreen: NSPoint(x: rect.minX + rect.width * fraction, y: rect.midY))
      for count in 1...2 {
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
          let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: count, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0))
          NSApp.sendEvent(event)
        }
      }
    }
    let entered = expectation(forNotification: NSWindow.didEnterFullScreenNotification, object: window)
    try doubleClick(fraction: 0.75)
    await fulfillment(of: [entered], timeout: 5)
    let exited = expectation(forNotification: NSWindow.didExitFullScreenNotification, object: window)
    try doubleClick(fraction: 0.25)
    await fulfillment(of: [exited], timeout: 5)
    XCTAssertEqual(session.position, before, accuracy: 0.35)
  }

  func testHardwareKeysControlOnlyTheExpandedMacPlayer() async throws {
    let db = AppDatabase.empty()
    let session = DesktopPlayback(database: db)
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let media = MediaSelection(url: url, playlistId: UUID(), streamId: "keys", type: "vod", title: "Keyboard movie")
    let native = FullScreenTestWindow(contentRect: NSRect(x: 40, y: 80, width: 1140, height: 738),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let window = window(for: Color.clear.modifier(MacPlaybackPresentation(playback: session))
      .environment(\.appDatabase, db), in: native)
    defer { session.close(); window.close() }
    session.start(media)
    try await waitFor("Keyboard movie is playing") { session.engine.isPlaybackEstablished && session.position > 0.1 }
    func send(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws {
      for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
          characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
        window.sendEvent(event)
      }
    }
    try send(" ", code: 49)
    try await waitFor("Space pauses decoder") { session.engine.isPaused }
    session.volume = 0.5
    try send("m", code: 46)
    try await waitFor("M mutes both session and decoder") {
      session.volume == 0 && session.engine.layer?.player.playbackVolume == 0
    }
    try send("m", code: 46)
    try await waitFor("M restores previous volume") { session.volume == 0.5 }
    try send("\u{F700}", code: 126)
    try await waitFor("Up arrow increases volume") { session.volume == 0.5625 }
    try send("\u{F701}", code: 125)
    try await waitFor("Down arrow decreases volume") { session.volume == 0.5 }
    session.seek(to: 3)
    try await waitFor("Paused seek lands") { abs(session.position - 3) < 1 && !session.engine.isSeekInFlight }
    try send("\u{F702}", code: 123)
    try await waitFor("Left arrow seeks to start") { session.position < 1 && !session.engine.isSeekInFlight }
    try send("\u{F703}", code: 124)
    try await waitFor("Right arrow seeks toward the end") { session.position > session.duration - 1 }
    try send("f", code: 3)
    try await waitFor("F requests full screen on the player window") { native.fullScreenRequests == 1 }
    try send("\u{1b}", code: 53)
    try await waitFor("Escape minimizes while keeping paused movie") { !session.expanded && session.current == media }
    try send("m", code: 46)
    XCTAssertEqual(session.volume, 0.5)
  }

  func testAppSpeakerSettingStartsTheBuiltInDeviceOnTheAudioQueue() async throws {
    let device = try XCTUnwrap(MacAudioOutput.builtInOutput())
    XCTAssertNotNil(MacAudioOutput.builtInOutputUID())
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(true, forKey: MacAudioOutput.speakerKey)
    let ready = expectation(description: "Audio graph started on selected device")
    let output = MacAudioOutput(defaults: defaults, startAudio: { graph in
      XCTAssertEqual(graph.engine.outputNode.auAudioUnit.deviceID, device)
      graph.play()
      XCTAssertTrue(graph.engine.isRunning)
      ready.fulfill()
    })
    output.prepare(audioFormat: try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)))
    output.play()
    await fulfillment(of: [ready], timeout: 5)
    output.pause()
  }

  func testPlaybackTestHostIsInaudible() {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessIsAudible,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var audible: UInt32 = 1, size = UInt32(MemoryLayout<UInt32>.size)
    XCTAssertEqual(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
      0, nil, &size, &audible), noErr)
    XCTAssertEqual(audible, 0)
  }

  func testSlowMacAudioDeviceDoesNotBlockPauseVolumeOrWindowEvents() async throws {
    let entered = expectation(description: "Audio device started on worker")
    let release = DispatchSemaphore(value: 0)
    let output = MacAudioOutput(startAudio: { _ in
      XCTAssertFalse(Thread.isMainThread)
      entered.fulfill()
      _ = release.wait(timeout: .now() + 4)
    })
    defer { release.signal() }
    output.prepare(audioFormat: try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)))
    output.play()
    await fulfillment(of: [entered], timeout: 3)
    let start = ContinuousClock.now
    output.volume = 0.35
    output.pause()
    output.flush()
    XCTAssertEqual(output.volume, 0.35)
    XCTAssertLessThan(start.duration(to: .now), .milliseconds(300))
  }

  func testPinchingFilledPictureCanRevealTheEntireFittedFrame() {
    let viewport = CGSize(width: 800, height: 600)
    let fitted = CGSize(width: 800, height: 450)
    let cover = PlayerPinchAspectSnapPolicy.coverScale(fitted: fitted, container: viewport)
    let minimum = PlayerPinchAspectSnapPolicy.minimumZoom(mode: .fill, committedZoom: 1, coverScale: cover)
    let filled = CGSize(width: fitted.width * cover, height: fitted.height * cover)
    let zoom = MacPictureTransform().adjusted(factor: 0.5, picture: filled, viewport: viewport, floor: minimum)
    XCTAssertEqual(filled.width * zoom.scale, fitted.width, accuracy: 0.01)
    XCTAssertEqual(filled.height * zoom.scale, fitted.height, accuracy: 0.01)
    XCTAssertEqual(PlayerPinchAspectSnapPolicy.outcome(mode: .fill, committedZoom: 1, endZoom: zoom.scale,
      coverScale: cover, cancelled: false), .snapToFit)
    XCTAssertEqual(PlayerPinchAspectSnapPolicy.outcome(mode: .fit, committedZoom: 1, endZoom: cover,
      coverScale: cover, cancelled: false), .snapToFill)
  }

  func testPictureZoomKeepsPinchAnchorAndClampsPanToVideoEdges() {
    let window = CGSize(width: 800, height: 600), picture = CGSize(width: 800, height: 450)
    let zoom = MacPictureTransform().adjusted(factor: 2, anchor: UnitPoint(x: 0.75, y: 0.5),
                                              picture: picture, viewport: window)
    XCTAssertEqual(zoom.scale, 2)
    XCTAssertEqual(zoom.offset.width, -200)
    let dragged = zoom.adjusted(drag: CGSize(width: 3000, height: -2000), picture: picture, viewport: window)
    XCTAssertEqual(dragged.offset, CGSize(width: 400, height: -150))
    XCTAssertEqual(dragged.adjusted(factor: 0.1, picture: picture, viewport: window), MacPictureTransform())
    XCTAssertEqual(zoom.adjusted(factor: 10, picture: picture, viewport: window).scale, 4)
  }

  func testPictureDoubleClickTogglesFullscreenWithoutSeekingAndHoldChangesSpeed() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Seek fixture", serverURL: "", type: .m3u)
    try database.writeSync { db in try source.insert(db) }
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "seek", withExtension: "mp4", subdirectory: "fixtures/playback"))
    let selection = MediaSelection(url: url, playlistId: source.id, streamId: "seek",
      type: "vod", title: "Seek fixture", ext: "mp4")
    let session = DesktopPlayback(database: database,
      preferences: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)))
    let native = FullScreenTestWindow(contentRect: NSRect(x: 40, y: 80, width: 1140, height: 738),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: selection), in: native)
    defer { session.close(); window.close() }
    session.start(selection)
    try await waitFor("Silent fixture plays") { session.engine.position > 0.2 && session.canSeek }
    let surface = try XCTUnwrap(named(ML("video_zoom"), window))
    let frame = try XCTUnwrap((attribute(surface, "accessibilityFrame") as? NSValue)?.rectValue)
    let center = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY))
    func pressPicture(_ type: NSEvent.EventType) throws {
      let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: center, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
      NSApp.sendEvent(event)
    }
    window.makeKeyAndOrderFront(nil)
    session.setSpeed(1.25)
    func performPictureAction(_ key: String) throws {
      let element = try XCTUnwrap(named(ML("video_zoom"), window))
      let actions = attribute(element, "accessibilityCustomActions") as? [NSAccessibilityCustomAction]
      let action = try XCTUnwrap(actions?.first { $0.name == L(key) })
      XCTAssertEqual(action.handler?(), true)
    }
    try performPictureAction("player.a11y.toggle_2x")
    try await waitFor("Accessible action starts fast playback") { session.engine.playbackRate == 2 }
    try performPictureAction("player.a11y.toggle_2x")
    try await waitFor("Accessible action restores selected speed") { session.engine.playbackRate == 1.25 }
    try performPictureAction("player.a11y.toggle_2x")
    try await waitFor("Temporary speed before pausing") { session.engine.playbackRate == 2 }
    try performPictureAction("player.a11y.pause")
    try await waitFor("Accessible pause ends temporary speed") {
      session.isPaused && session.engine.playbackRate == 1.25 && self.named("2×", window) == nil
    }
    try performPictureAction("player.a11y.play")
    try await waitFor("Accessible play resumes at chosen speed") {
      !session.isPaused && session.engine.playbackRate == 1.25
    }
    try pressPicture(.leftMouseDown)
    try await waitFor("Hold accelerates playing video") { session.engine.playbackRate == 2 }
    try await waitFor("Hold indicator appears") { self.named("2×", window) != nil }
    try await capture(window, name: "Temporary playback speed")
    try pressPicture(.leftMouseUp)
    try await waitFor("Release restores selected speed") {
      session.engine.playbackRate == 1.25 && self.named("2×", window) == nil
    }
    session.toggle()
    try await waitFor("Paused") { session.engine.isPaused }
    let origin = session.position
    let picture = try XCTUnwrap(named(ML("video_zoom"), window))
    let rect = try XCTUnwrap((attribute(picture, "accessibilityFrame") as? NSValue)?.rectValue)
    let point = window.convertPoint(fromScreen: CGPoint(x: rect.maxX - 24, y: rect.midY))
    for count in 1...3 {
      for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, eventNumber: count, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0))
        NSApp.sendEvent(event)
      }
    }
    XCTAssertEqual(native.fullScreenRequests, 1)
    XCTAssertEqual(session.position, origin, accuracy: 0.3)
    session.toggle()
    try await waitFor("Playing before minimizing") { !session.isPaused }
    try performPictureAction("player.a11y.toggle_2x")
    try await waitFor("Temporary speed applied") { session.engine.playbackRate == 2 }
    let beforeMinimize = session.position
    try performPictureAction("player.a11y.minimize")
    try await waitFor("Minimizing restores chosen speed and playback continues") {
      !session.expanded && session.engine.playbackRate == 1.25 && session.position > beforeMinimize
    }
  }

  func testMKVPlaybackPauseSeekAndStoredHistory() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Movie fixture", serverURL: "", type: .m3u)
    try database.writeSync { db in try source.insert(db) }
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let selection = MediaSelection(
      url: url, playlistId: source.id, streamId: "local-1", type: "vod", title: "Local movie",
      ext: "mkv")
    let preferences = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let session = DesktopPlayback(database: database, preferences: preferences)
    let window = window(
      for: MacPlayerView(session: session, engine: session.engine, media: selection))
    defer {
      session.close()
      window.close()
    }
    session.start(selection)
    try await waitFor("Decoded MKV picture", timeout: 18) {
      session.engine.isPlaybackEstablished && session.engine.position > 0.2
        && session.engine.videoDisplayWidth > 0
    }
    let zoom = try XCTUnwrap(named(ML("video_zoom"), window))
    let increment = NSSelectorFromString("accessibilityPerformIncrement")
    XCTAssertTrue(zoom.responds(to: increment))
    zoom.perform(increment)
    try await waitFor("Decoded picture zooms to 200 percent") {
      guard let control = self.named(ML("video_zoom"), window) else { return false }
      return self.attribute(control, "accessibilityValueDescription") as? String == Double(2).formatted(.percent)
    }
    let position = session.engine.position
    try await waitFor("Zoomed picture keeps playing") { session.engine.position > position + 0.15 }
    try await capture(window, name: "Zoomed local movie")
    let decoder = try XCTUnwrap(session.engine.layer?.player)
    session.aspect = .fill
    try await waitFor("Changing aspect resets zoom without replacing the playing decoder") {
      guard let control = self.named(ML("video_zoom"), window) else { return false }
      return self.attribute(control, "accessibilityValueDescription") as? String == Double(1).formatted(.percent)
        && session.engine.layer?.player === decoder && !session.engine.isPaused
    }
    try await waitFor("Fill notice appears on picture") { self.named(VideoAspectMode.fill.title, window) != nil }
    try await capture(window, name: "Movie after changing aspect")
    try await waitFor("Aspect notice clears") { self.named(VideoAspectMode.fill.title, window) == nil }
    let reopened = DesktopPlayback(database: database, preferences: preferences)
    XCTAssertEqual(reopened.aspect, .fill)

    XCTAssertTrue(session.engine.isFFmpegBackendActive)
    session.volume = 0.45
    XCTAssertEqual(session.engine.layer?.player.playbackVolume ?? -1, 0.45, accuracy: 0.015)
    session.setSpeed(1.5)
    XCTAssertEqual(session.engine.layer?.player.playbackRate ?? 0, 1.5, accuracy: 0.01)
    session.aspect = .fill
    try await capture(window, name: "MKV playback")
    session.setSleepTimer(seconds: 900, presetMinutes: 15)
    XCTAssertEqual(session.sleepPresetMinutes, 15)
    session.setSleepTimer(seconds: nil)
    XCTAssertEqual(session.sleepPresetMinutes, 0)
    XCTAssertNil(session.sleepDeadline)
    session.setSleepTimer(seconds: 0.12, presetMinutes: 5)
    try await waitFor("Sleep timer pauses transport") {
      session.engine.isPaused && session.sleepDeadline == nil
    }
    XCTAssertEqual(session.sleepPresetMinutes, 0)
    session.toggle()
    try await waitFor("Resumed after timer") { !session.engine.isPaused }
    session.toggle()
    try await waitFor("Paused") { session.engine.isPaused }
    session.engine.seek(to: 3.5)
    try await waitFor("Seek landed") { abs(session.engine.position - 3.5) < 0.9 }
    session.close()
    let deadline = Date().addingTimeInterval(3)
    var row: DBWatchHistory?
    repeat {
      row = try await database.read { try DBWatchHistory.fetchOne($0, key: selection.historyID) }
      if (row?.lastTimeMs ?? 0) > 2500 { break }
      try await Task.sleep(for: .milliseconds(60))
    } while Date() < deadline
    XCTAssertGreaterThan(row?.lastTimeMs ?? 0, 2500)
  }

  func testFileImportCancellationRecognizesOnlyCancellationErrors() {
    XCTAssertTrue(isFileImportCancellation(CocoaError(.userCancelled)))
    XCTAssertTrue(isFileImportCancellation(CancellationError()))
    XCTAssertFalse(isFileImportCancellation(CocoaError(.fileReadNoPermission)))
    XCTAssertFalse(isFileImportCancellation(NSError(domain: "Importer", code: NSUserCancelledError)))
  }

  func testTrackPickerAndExternalSubtitleRestore() async throws {
    let db = AppDatabase.empty()
    let pid = UUID()
    let movie = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let media = MediaSelection(
      url: movie, playlistId: pid, streamId: "tracks", type: "vod", title: "Tracks")
    let key = ImportedSubtitleStore.contentKey(playlistId: pid, type: "vod", streamId: "tracks")
    let preferenceKey = "playback.trackPreferences.v1"
    let prefs = UserDefaults.standard.object(forKey: preferenceKey)
    let subtitle = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".srt")
    try "1\n00:00:00,000 --> 00:00:07,000\nHarbor subtitle\n".write(
      to: subtitle, atomically: true, encoding: .utf8)
    let session = DesktopPlayback(database: db)
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer {
      session.close()
      window.close()
      ImportedSubtitleStore.removeAll(playlistId: pid)
      SubtitleDelayStore.removeAll(playlistId: pid)
      try? FileManager.default.removeItem(at: subtitle)
      if let prefs {
        UserDefaults.standard.set(prefs, forKey: preferenceKey)
      } else {
        UserDefaults.standard.removeObject(forKey: preferenceKey)
      }
    }
    session.start(media)
    try await waitFor("Audio and embedded subtitle tracks", timeout: 15) {
      session.tracks.audio.count >= 2 && session.tracks.subtitles.count >= 3
    }
    let other = try XCTUnwrap(session.tracks.audio.first { $0.id != session.tracks.audioID })
    session.tracks.select(.audio, id: other.id)
    session.tracks.refresh()
    XCTAssertEqual(session.tracks.audioID, other.id)
    let alternate = subtitle.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".srt")
    try "1\n00:00:00,000 --> 00:00:07,000\nAlternate subtitle\n".write(to: alternate, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: alternate) }
    try session.tracks.add(alternate)
    try await waitFor("First external file renders before importing a second file") {
      session.engine.subtitleText?.string.contains("Alternate subtitle") == true
    }
    try session.tracks.add(subtitle)
    try await waitFor("External subtitles render") {
      session.engine.subtitleText?.string.contains("Harbor subtitle") == true
    }
    try "1\n00:00:00,000 --> 00:00:07,000\nRevised harbor subtitle\n".write(
      to: subtitle, atomically: true, encoding: .utf8)
    try session.tracks.add(subtitle)
    try await waitFor("Reimported file renders the corrected subtitle") {
      session.engine.subtitleText?.string.contains("Revised harbor subtitle") == true
    }
    XCTAssertEqual(session.tracks.files.filter { $0.lastPathComponent == subtitle.lastPathComponent }.count, 1)
    XCTAssertEqual(session.tracks.subtitles.filter { $0.isExternal && $0.title == subtitle.lastPathComponent }.count, 1)
    let alternateTrack = try XCTUnwrap(session.tracks.subtitles.first { $0.title == alternate.lastPathComponent })
    let revisedTrack = try XCTUnwrap(session.tracks.subtitles.first { $0.title == subtitle.lastPathComponent })
    session.tracks.select(.subtitles, id: alternateTrack.id)
    try await waitFor("Switching files displays the alternate cue") {
      session.engine.subtitleText?.string.contains("Alternate subtitle") == true
    }
    session.tracks.select(.subtitles, id: revisedTrack.id)
    try await waitFor("Reselecting the revised file displays its new text") {
      session.engine.subtitleText?.string.contains("Revised harbor subtitle") == true
    }
    let workingFile = try XCTUnwrap(session.tracks.files.first { $0.lastPathComponent == subtitle.lastPathComponent })
    let workingData = try Data(contentsOf: workingFile)
    try "Not a subtitle file".write(to: subtitle, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try session.tracks.add(subtitle))
    XCTAssertEqual(try Data(contentsOf: workingFile), workingData)
    XCTAssertEqual(session.tracks.subtitleID, revisedTrack.id)
    XCTAssertEqual(ImportedSubtitleStore.selectedFileName(for: key), workingFile.lastPathComponent)
    session.tracks.setSubtitleDelay(0.4)
    session.start(media)
    try await waitFor("Selected subtitle restored after reopening", timeout: 15) {
      session.tracks.subtitles.contains { $0.isExternal && $0.id == session.tracks.subtitleID }
    }
    XCTAssertEqual(session.tracks.audioID, other.id)
    XCTAssertEqual(session.tracks.subtitleDelay, 0.4)
    XCTAssertEqual(ImportedSubtitleStore.selectedFileName(for: key), subtitle.lastPathComponent)
    try await press(L("player.tracks.title"), in: window)
    try await capture(window, name: "Playback tracks")
    let popover = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    let alternateDelete = try XCTUnwrap(accessible(popover).first {
      attribute($0, "accessibilityLabel") as? String == L("common.delete") &&
        attribute($0, "accessibilityValue") as? String == alternate.lastPathComponent
    })
    alternateDelete.perform(NSSelectorFromString("accessibilityPerformPress"))
    try await waitFor("Deleting an unselected subtitle keeps the active external track") {
      session.tracks.files.map(\.lastPathComponent) == [subtitle.lastPathComponent] &&
        session.tracks.subtitles.contains { $0.title == subtitle.lastPathComponent && $0.id == session.tracks.subtitleID }
    }
    XCTAssertEqual(ImportedSubtitleStore.selectedFileName(for: key), subtitle.lastPathComponent)
    let saved = try XCTUnwrap(session.tracks.files.first)
    func selectedFileDeleteButton() -> NSObject? {
      accessible(popover).first {
        attribute($0, "accessibilityLabel") as? String == L("common.delete") &&
          attribute($0, "accessibilityValue") as? String == saved.lastPathComponent
      }
    }
    try await waitFor("Selected subtitle delete button is available") { selectedFileDeleteButton() != nil }
    try XCTUnwrap(selectedFileDeleteButton()).perform(NSSelectorFromString("accessibilityPerformPress"))
    try await waitFor("Deleted subtitle leaves the current track list") {
      session.tracks.files.isEmpty && !session.tracks.subtitles.contains { $0.title == saved.lastPathComponent }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: subtitle.path))
    XCTAssertNil(ImportedSubtitleStore.selectedFileName(for: key))
    session.start(media)
    try await waitFor("Reopened movie loads embedded subtitles without the removed file") {
      session.engine.isPlaybackEstablished && session.tracks.subtitles.count >= 3 &&
        !session.tracks.subtitles.contains { $0.isExternal && $0.title == saved.lastPathComponent }
    }
    XCTAssertEqual(session.tracks.subtitleDelay, 0.4)
  }

  func testSubtitleAppearancePreviewsAndCancels() async throws {
    let database = AppDatabase.empty()
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let media = MediaSelection(
      url: url, playlistId: UUID(), streamId: "style", type: "vod", title: "Subtitle style")
    let saved = SubtitleAppearancePersistence.load()
    let session = DesktopPlayback(database: database)
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer {
      session.close()
      window.close()
      SubtitleAppearancePersistence.save(saved)
      SubtitleDelayStore.removeAll(playlistId: media.playlistId)
    }
    var initial = saved
    initial.fontSize = 30
    session.tracks.applySubtitleAppearanceSettings(initial)
    session.start(media)
    try await waitFor("Decoded subtitle fixture") { session.engine.isPlaybackEstablished }
    session.engine.pause()
    try await press(L("player.tracks.title"), in: window)
    let popover = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await press(L("subtitle.settings_title"), in: popover)
    try await waitFor("Subtitle appearance editor opens") { self.named(L("common.done"), window) != nil }
    XCTAssertNil(window.attachedSheet)
    let sheet = window
    try await waitFor("Font size slider") { self.named(L("subtitle.font_size"), sheet) != nil }
    let slider = try XCTUnwrap(
      accessible(sheet).first {
        attribute($0, "accessibilityRole") as? String == "AXSlider" && attribute($0, "accessibilityLabel") as? String == L("subtitle.font_size")
      })
    let increment = NSSelectorFromString("accessibilityPerformIncrement")
    XCTAssertTrue(slider.responds(to: increment))
    let initialDelay = session.tracks.subtitleDelaySeconds
    let timing = try XCTUnwrap(accessible(window).first {
      attribute($0, "accessibilityRole") as? String == "AXSlider" &&
        attribute($0, "accessibilityLabel") as? String == L("subtitle.time_offset")
    })
    timing.perform(increment)
    try await waitFor("Subtitle offset adjustment reaches the player") {
      session.tracks.subtitleDelaySeconds > initialDelay
    }
    slider.perform(increment)
    try await Task.sleep(for: .milliseconds(250))
    try await waitFor("Live font size preview") { session.engine.subtitleAppearance.fontSize > 30 }
    XCTAssertEqual(session.engine.subtitleAppearance, SubtitleAppearancePersistence.load())
    try await capture(window, name: "Player with subtitle appearance editor")
    try await press(L("common.cancel"), in: sheet)
    try await waitFor("Cancel restores font size") {
      self.named(L("common.done"), window) == nil && session.engine.subtitleAppearance == initial
    }
    XCTAssertEqual(session.tracks.subtitleDelaySeconds, initialDelay, accuracy: 0.001)
    XCTAssertEqual(SubtitleAppearancePersistence.load(), initial)
    try await press(L("player.tracks.title"), in: window)
    let reopenedPopover = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await press(L("subtitle.settings_title"), in: reopenedPopover)
    try await waitFor("Appearance editor reopens") { self.named(L("common.done"), window) != nil }
    XCTAssertNil(window.attachedSheet)
    let reopened = window
    let fontControl = try XCTUnwrap(accessible(reopened).first {
      attribute($0, "accessibilityRole") as? String == "AXSlider" && attribute($0, "accessibilityLabel") as? String == L("subtitle.font_size")
    })
    fontControl.perform(increment)
    try await waitFor("Preview reflects new size") { session.engine.subtitleAppearance.fontSize > initial.fontSize }
    let reopenedTiming = try XCTUnwrap(accessible(reopened).first {
      attribute($0, "accessibilityRole") as? String == "AXSlider" &&
        attribute($0, "accessibilityLabel") as? String == L("subtitle.time_offset")
    })
    reopenedTiming.perform(increment)
    try await waitFor("New subtitle delay is applied") { session.tracks.subtitleDelaySeconds > initialDelay }
    let acceptedDelay = session.tracks.subtitleDelaySeconds
    let other = MediaSelection(url: url, playlistId: media.playlistId, streamId: "other",
                               type: "vod", title: "Another film")
    let accepted = session.engine.subtitleAppearance
    try await press(L("common.done"), in: reopened)
    try await waitFor("Done dismisses the editor") { self.named(L("common.done"), window) == nil }
    XCTAssertEqual(session.engine.subtitleAppearance, accepted)
    XCTAssertEqual(SubtitleAppearancePersistence.load(), accepted)
    session.start(other)
    try await waitFor("Other film uses its own timing") {
      session.engine.isPlaybackEstablished && session.tracks.subtitleDelaySeconds == 0
    }
    session.start(media)
    try await waitFor("Returning to the film restores its saved subtitle timing") {
      session.engine.isPlaybackEstablished && session.tracks.subtitleDelaySeconds == acceptedDelay
    }
    session.start(other)
    try await waitFor("Other film is ready for editing") { session.engine.isPlaybackEstablished && session.tracks.subtitleDelaySeconds == 0 }
    try await press(L("player.tracks.title"), in: window)
    let tracksMenu = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await press(L("subtitle.settings_title"), in: tracksMenu)
    try await waitFor("Inline editor is open") { self.named(L("common.cancel"), window) != nil }
    let otherTiming = try XCTUnwrap(accessible(window).first {
      attribute($0, "accessibilityRole") as? String == "AXSlider" &&
        attribute($0, "accessibilityLabel") as? String == L("subtitle.time_offset")
    })
    otherTiming.perform(increment)
    try await waitFor("Other film preview now equals the first film delay") {
      session.tracks.subtitleDelaySeconds == acceptedDelay
    }
    session.start(media)
    try await waitFor("Film with equal delay opens while editor stays visible") {
      session.engine.isPlaybackEstablished && session.tracks.subtitleDelaySeconds == acceptedDelay &&
        self.named(L("common.cancel"), window) != nil
    }
    try await press(L("subtitle.reset_to_default"), in: window)
    try await waitFor("Reset previews default appearance and zero delay") {
      session.engine.subtitleAppearance == .default && session.tracks.subtitleDelaySeconds == 0
    }
    try await press(L("common.cancel"), in: window)
    XCTAssertEqual(session.tracks.subtitleDelaySeconds, acceptedDelay, accuracy: 0.001)
    XCTAssertEqual(session.engine.subtitleAppearance, accepted)
    XCTAssertEqual(SubtitleAppearancePersistence.load(), accepted)


  }

  func testProviderAirPlayPlaysTheLiveHLSAndRestoresOriginalStream() async throws {
    try await exerciseProviderAirPlay(validHLS: true)
  }

  func testFailedProviderAirPlayAutomaticallyRemuxesAndRemembersTheHost() async throws {
    try await exerciseProviderAirPlay(validHLS: false)
  }

  private func exerciseProviderAirPlay(validHLS: Bool) async throws {
    let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let segments = LocalHTTPServer(directory: folder, advertisedAddress: { "127.0.0.1" })
    try segments.start()
    defer { segments.stop() }
    if validHLS { try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent("segment.ts")) }
    let manifest = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-TARGETDURATION:8
      #EXT-X-MEDIA-SEQUENCE:0
      #EXTINF:8.0,
      http://127.0.0.1:\(segments.port)/segment.ts
      #EXT-X-ENDLIST

      """
    let provider = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: file)),
                                  pace: 1, providerHLS: manifest)
    try provider.start()
    defer { provider.stop() }
    let suite = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let session = DesktopPlayback(database: .empty()) {
      CastController(routeIsActive: { false }, server: segments, nativeCastDefaults: defaults)
    }
    defer { session.close() }
    CastNativeURL.rememberFailure(for: provider.streamURL, defaults: defaults)
    let window = window(for: MacDiagnosticControls(showOverlay: .constant(false), url: provider.streamURL,
                                                   castDefaults: defaults).defaultAppStorage(defaults))
    defer { window.close() }
    XCTAssertFalse(defaults.bool(forKey: CastNativeURL.enabledDefaultsKey))
    try await press(L("player.airplay.native_live_cast"), in: window)
    XCTAssertTrue(defaults.bool(forKey: CastNativeURL.enabledDefaultsKey))
    XCTAssertFalse(CastNativeURL.hasRememberedFailure(for: provider.streamURL, defaults: defaults))
    if validHLS { try await capture(window, name: "Provider AirPlay preference") }
    let media = MediaSelection(url: provider.streamURL, playlistId: UUID(), streamId: "1",
                               type: "live", title: "Live TV")
    session.start(media)
    try await waitFor("Local H.264/AAC live playback", timeout: 15) {
      session.engine.isPlaybackEstablished && session.engine.position > 0.1 &&
        session.engine.videoCodecName == "h264" && session.engine.audioCodecName == "aac"
    }
    session.prepareAirPlay()
    try await waitFor("Provider receives HLS request", timeout: 12) { provider.stats.providerHLSRequests > 0 }
    if validHLS {
      try await waitFor("Native HLS frames advance on the route player", timeout: 15) {
        session.cast?.isRemuxing == false && session.cast?.isPlaybackEstablished == true &&
          (session.cast?.position ?? 0) > 0.2
      }
      XCTAssertFalse(CastNativeURL.hasRememberedFailure(for: provider.streamURL, defaults: defaults))
    } else {
      try await waitFor("Unplayable HLS falls back to a playing remux", timeout: 30) {
        session.cast?.isRemuxing == true && session.cast?.isPlaybackEstablished == true &&
          (session.cast?.position ?? 0) > 0.2
      }
      XCTAssertTrue(CastNativeURL.hasRememberedFailure(for: provider.streamURL, defaults: defaults))
    }
    session.cast?.stopCasting()
    try await waitFor("Stop restores the original live decoder", timeout: 18) {
      session.engine.isPlaybackEstablished && session.current?.url == provider.streamURL
    }
    if !validHLS {
      let before = provider.stats.providerHLSRequests
      session.prepareAirPlay()
      try await waitFor("Remembered provider goes directly to a playing remux", timeout: 30) {
        session.cast?.isRemuxing == true && session.cast?.isPlaybackEstablished == true
      }
      XCTAssertEqual(provider.stats.providerHLSRequests, before)
    }
  }

  func testAirPlayWithoutNetworkKeepsPlayingMKV() async throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let server = LocalHTTPServer(
      directory: FileManager.default.temporaryDirectory, advertisedAddress: { nil })
    let session = DesktopPlayback(database: .empty()) { CastController(server: server) }
    let media = MediaSelection(
      url: url, playlistId: UUID(), streamId: "offline-airplay", type: "vod", title: "Harbor")
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer {
      session.close()
      window.close()
    }
    session.start(media)
    try await waitFor("AirPlay action available on MKV") {
      session.engine.isPlaybackEstablished && self.named("AirPlay", window) != nil
    }
    let layer = try XCTUnwrap(session.engine.layer)
    try await press("AirPlay", in: window)
    try await waitFor("AirPlay network message") {
      self.named(ML("airplay_network"), window) != nil
    }
    XCTAssertTrue(session.engine.layer === layer)
    XCTAssertFalse(session.cast?.isPresenting ?? true)
    try await capture(window, name: "AirPlay network unavailable")
  }

  func testDesktopAirPlayPreparesMKVAndResumesLocalPlayback() async throws {
    let source = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let server = LocalHTTPServer(directory: folder, advertisedAddress: { "127.0.0.1" })
    let session = DesktopPlayback(database: .empty()) {
      CastController(routeIsActive: { false }, server: server)
    }
    defer {
      session.close()
      server.stop()
      try? FileManager.default.removeItem(at: folder)
    }
    let media = MediaSelection(
      url: source, playlistId: UUID(), streamId: "airplay", type: "vod", title: "Harbor")
    session.start(media)
    try await waitFor("Direct MKV decoder ready") {
      session.engine.isPlaybackEstablished && session.engine.position > 0.2
    }
    session.setSpeed(1.25)
    session.prepareAirPlay()
    try await waitFor("MKV handoff completes", timeout: 30) {
      (session.cast?.routePlayer?.currentTime().seconds ?? 0) > 0.2 && session.pickerRequest != nil
    }
    let cast = try XCTUnwrap(session.cast)
    XCTAssertNil(session.engine.layer)
    XCTAssertTrue(cast.isPresenting)
    XCTAssertTrue(cast.isRemuxing)
    XCTAssertFalse(session.canChangeSpeed)
    XCTAssertEqual(session.systemPlayback.perform(.speed(1.5)), .commandFailed)
    let previousSpeed = session.speed
    session.setSpeed(1.5)
    XCTAssertEqual(session.speed, previousSpeed)
    try await waitFor("Cast source clock advances", timeout: 8) { session.position > 1 }
    session.toggle()
    try await waitFor("Remote transport pauses") { session.isPaused }
    try await waitFor("System metadata survives the engine to cast handoff") {
      let center = MPNowPlayingInfoCenter.default()
      return center.playbackState == .paused
        && center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == media.title
    }
    let prefsKey = "playback.trackPreferences.v1"
    let saved = UserDefaults.standard.object(forKey: prefsKey)
    defer {
      if let saved {
        UserDefaults.standard.set(saved, forKey: prefsKey)
      } else {
        UserDefaults.standard.removeObject(forKey: prefsKey)
      }
    }
    let other = try XCTUnwrap(session.tracks.audio.first { $0.id != session.tracks.audioID })
    let player = try XCTUnwrap(cast.routePlayer)
    XCTAssertEqual(player.defaultRate, 1)
    try await waitFor("Remux ready to return to Mac") { cast.continuePlaybackLocally() }
    try await waitFor("Returning to Mac restores chosen speed on the same paused player") {
      session.canChangeSpeed && player.defaultRate == 1.25 && player.rate == 0 && cast.routePlayer === player
    }
    session.tracks.select(.audio, id: other.id)
    try await waitFor("Cast playlist rebuilt with selected second audio track", timeout: 20) {
      cast.sourceTracks?.selectedAudioID == other.id && !cast.isBuffering && cast.isPaused
    }
    XCTAssertTrue(cast.routePlayer === player)
    let subtitle = folder.appendingPathComponent("harbor.srt")
    try "1\n00:00:00,000 --> 00:00:07,000\nHarbor crossing\n".write(
      to: subtitle, atomically: true, encoding: .utf8)
    defer { ImportedSubtitleStore.removeAll(playlistId: media.playlistId) }
    try session.tracks.add(subtitle)
    try await waitFor("External subtitle rendition loaded on same cast player", timeout: 20) {
      (player.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent == "master.m3u8"
        && !cast.isBuffering && cast.isPaused
    }
    let master = try XCTUnwrap((player.currentItem?.asset as? AVURLAsset)?.url)
    let (data, _) = try await URLSession.shared.data(from: master)
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("TYPE=SUBTITLES"))
    let stoppedAt = session.position
    cast.stopCasting()
    try await waitFor("Direct engine resumes paused", timeout: 15) {
      !cast.isPresenting && session.engine.layer != nil && session.engine.isReady
        && session.engine.isPaused
    }
    XCTAssertTrue(session.canChangeSpeed)
    session.setSpeed(1.5)
    XCTAssertEqual(session.speed, 1.5)
    session.toggle()
    try await waitFor("Local playback advances after cast", timeout: 12) {
      session.engine.position > stoppedAt
    }
  }

  func testRemuxedMKVPlaysThroughMacCastSurface() async throws {
    let source = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let server = LocalHTTPServer(directory: folder)
    try server.start()
    defer { server.stop() }
    let writer = RemuxHLSWriter(
      sourceURL: source, outputDirectory: folder, startSeconds: 0,
      isLive: false, userAgent: nil, audioStreamIndex: 1)
    var failure: Error?
    writer.onError = { failure = $0 }
    writer.start()
    defer { writer.cancel() }
    let playlist = folder.appendingPathComponent("stream.m3u8")
    try await waitFor("MKV remux produces a complete HLS playlist", timeout: 15) {
      failure != nil
        || (try? String(contentsOf: playlist, encoding: .utf8).contains("#EXT-X-ENDLIST")) == true
    }
    if let failure { throw failure }
    let host = AirPlayCastPlayer()
    defer { host.dispose() }
    let surface = NSWindow(
      contentRect: NSRect(x: 30, y: 60, width: 600, height: 360),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    surface.isReleasedWhenClosed = false
    surface.contentView = host.view
    surface.makeKeyAndOrderFront(nil)
    defer { surface.close() }
    let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/stream.m3u8"))
    host.load(url: url, startAt: nil, autoPlay: true)
    try await waitFor("Cast player decodes remuxed MKV", timeout: 12) {
      host.currentTime > 0.2 && host.isLocalVideoReadyForDisplay
    }
    host.pause()
    XCTAssertTrue(host.isPaused)
    let original = host.player.currentItem
    let oldSurface = host.view
    XCTAssertTrue(host.restoreLocalVideoSurface())
    XCTAssertFalse(host.view === oldSurface)
    surface.contentView = host.view
    XCTAssertTrue(host.player.currentItem === original)
    host.play()
    try await waitFor("Video resumes on the restored local layer") {
      host.isLocalVideoReadyForDisplay && host.currentTime > 0.4
    }
    try await capture(surface, name: "Remux MKV playback")
    host.prepareForExternalPlayback()
    XCTAssertTrue(host.player.allowsExternalPlayback)
  }

  func testNativeAirPlayPickerRoutesPlayingAVPlayer() async throws {
    let db = AppDatabase.empty()
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "route-video", withExtension: "mp4"))
    let media = MediaSelection(
      url: url, playlistId: UUID(), streamId: "airplay", type: "vod", title: "AirPlay fixture")
    let session = DesktopPlayback(database: db)
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer {
      session.close()
      window.close()
    }
    session.start(media)
    func findPicker(_ view: NSView) -> AVRoutePickerView? {
      if let picker = view as? AVRoutePickerView { return picker }
      return view.subviews.lazy.compactMap(findPicker).first
    }
    try await waitFor("Native H.264 playback has an attached route picker", timeout: 15) {
      guard let view = window.contentView,
        let player = (session.engine.layer?.player as? KSAVPlayer)?.player
      else { return false }
      return session.engine.isPlaybackEstablished && findPicker(view)?.player === player
    }
    XCTAssertFalse(session.engine.isFFmpegBackendActive)
  }

  func testM3UMovieFromDiscoverDownloadsAndPlaysOffline() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    try FileManager.default.copyItem(
      at: fixture, to: directory.appendingPathComponent("feature.mkv"))
    try FileManager.default.copyItem(
      at: fixture, to: directory.appendingPathComponent("broadcast.ts"))
    let http = LocalHTTPServer(directory: directory)
    try http.start()
    defer { http.stop() }
    let base = "http://127.0.0.1:\(http.port)"
    let database = AppDatabase.shared
    let source = Playlist(name: "Harbor library", serverURL: base + "/playlist.m3u", type: .m3u)
    try await M3UImporter.replace(
      playlist: source,
      channels: [
        ParsedM3UChannel(name: "Harbor feature", url: base + "/feature.mkv", groupTitle: "Films"),
        ParsedM3UChannel(name: "Harbor live", url: base + "/broadcast.ts", groupTitle: "News"),
      ], epgURL: nil, in: database)
    defer {
      _ = try? database.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    let catalog = try await database.read {
      try MacCatalogQuery(playlistID: source.id, kinds: [.m3u]).fetch($0)
    }
    let film = try XCTUnwrap(catalog.first { $0.title == "Harbor feature" })
    let live = try XCTUnwrap(catalog.first { $0.title == "Harbor live" })
    let stale = CatalogItem(
      playlistId: source.id, kind: film.kind, streamKey: film.streamKey, title: "Previous title",
      category: "Previous group", artwork: base + "/previous-logo.png", rating: film.rating,
      favorite: film.favorite, sortIndex: film.sortIndex, m3uURL: film.m3uURL)
    let refreshed = try await MediaSelection.resolve(stale, in: source, database: database)
    XCTAssertEqual(refreshed.title, "Harbor feature")
    XCTAssertEqual(refreshed.secondaryTitle, "Films")
    XCTAssertNil(refreshed.artwork)
    XCTAssertTrue(film.isM3UMovie)
    XCTAssertFalse(live.isM3UMovie)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let session = DesktopPlayback(database: database)
    let window = window(
      for: SourceLibrary().modifier(MacPlaybackPresentation(playback: session)).environment(\.appDatabase, database)
        .environmentObject(LocalizationManager.shared).environmentObject(session).defaultAppStorage(
          defaults))
    defer {
      session.close()
      window.close()
    }
    try await waitFor("Discover shows imported movie") { self.named(film.title, window) != nil }
    try await press(live.title, in: window)
    try await waitFor("M3U live channel plays directly") {
      session.current?.streamId == live.streamKey && session.engine.isPlaybackEstablished
    }
    XCTAssertNil(session.current?.downloadID)
    session.close()
    try await press(film.title, in: window)
    try await waitFor("M3U movie offers download") {
      self.named(L("download.action"), window) != nil
    }
    try database.writeSync { db in
      try db.execute(sql: "UPDATE m3uChannel SET name = ?, tvgLogo = ?, groupTitle = ? WHERE playlistId = ? AND id = ?",
        arguments: ["Renamed feature", base + "/poster.jpg", "Cinema", source.id, film.streamKey])
    }
    try await waitFor("Open M3U detail reflects the new title, poster and group") {
      self.named("Renamed feature", window) != nil && self.named(ML("enlarge_artwork"), window) != nil &&
        self.named("Cinema", window) != nil
    }
    try database.writeSync { db in
      try db.execute(sql: "UPDATE m3uChannel SET name = ?, tvgLogo = NULL, groupTitle = ? WHERE playlistId = ? AND id = ?",
        arguments: [film.title, film.category, source.id, film.streamKey])
    }
    try await waitFor("Removed M3U artwork clears the detail action") {
      self.named(film.title, window) != nil && self.named(ML("enlarge_artwork"), window) == nil
    }
    let filmHistory = DBWatchHistory(id: "\(source.id)_vod_\(film.streamKey)", playlistId: source.id,
      streamId: film.streamKey, type: "vod", lastTimeMs: 6000, durationMs: 60000,
      lastWatchedAt: Date(), title: film.title)
    try database.writeSync { try filmHistory.insert($0) }
    try await waitFor("Saved film position offers resume") { self.named(L("detail.resume"), window) != nil }
    try database.writeSync { db in
      try db.execute(sql: "UPDATE m3uChannel SET url = ? WHERE playlistId = ? AND id = ?",
        arguments: [base + "/broadcast.ts", source.id, film.streamKey])
    }
    try await waitFor("Reclassified live entry offers playback without film download") {
      self.named(L("movie.play"), window) != nil && self.named(L("download.action"), window) == nil
    }
    XCTAssertNil(named(L("detail.resume"), window))
    try await press(L("movie.play"), in: window)
    try await waitFor("Reclassified entry decodes the new live URL") {
      session.current?.isLive == true && session.current?.url.path == "/broadcast.ts" &&
        session.engine.isPlaybackEstablished
    }
    XCTAssertNil(session.current?.downloadID)
    session.close()
    let retained = try await database.read { try DBWatchHistory.fetchOne($0, key: filmHistory.id) }
    XCTAssertEqual(retained?.lastTimeMs, 6000)
    _ = try database.writeSync { try filmHistory.delete($0) }
    try database.writeSync { db in
      try db.execute(sql: "UPDATE m3uChannel SET url = ? WHERE playlistId = ? AND id = ?",
        arguments: [base + "/feature.mkv", source.id, film.streamKey])
    }
    try await waitFor("Film download action returns") { self.named(L("download.action"), window) != nil }
    try await press(ML("favorite"), in: window)
    try await waitFor("Favorite saved") { self.named(ML("unfavorite"), window) != nil }
    try await film.setFavorite(false, in: database)
    try await waitFor("Detail observes favorites changed elsewhere") {
      self.named(ML("favorite"), window) != nil
    }
    try await press(L("download.action"), in: window)
    try await waitFor("Imported film downloaded", timeout: 25) {
      self.named(L("download.completed"), window) != nil
    }
    let id = DownloadManager.idFor(m3uChannel: source.id, channelId: film.streamKey)
    let local = await DownloadManager.shared.localURL(forId: id)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(local)), try Data(contentsOf: fixture))
    try await capture(window, name: "Downloaded M3U movie")
    http.stop()
    let absent = try database.writeSync { db in
      try db.execute(sql: "UPDATE downloadedItem SET title = ?, secondaryTitle = ?, imageURL = ? WHERE id = ?",
        arguments: ["Downloaded feature", "Offline cinema", base + "/downloaded-cover.jpg", id])
      let row = try DBM3UChannel.filter(Column("playlistId") == source.id && Column("id") == film.streamKey).fetchOne(db)
      if let row { _ = try row.delete(db) }
      return row
    }
    try await press(L("movie.play"), in: window)
    try await waitFor("Offline movie decodes from detail") {
      session.current?.downloadID == id && session.engine.isPlaybackEstablished
        && session.position > 0.1
    }
    XCTAssertTrue(session.current?.url.isFileURL == true)
    XCTAssertEqual(session.current?.title, "Downloaded feature")
    XCTAssertEqual(session.current?.secondaryTitle, "Offline cinema")
    XCTAssertEqual(session.current?.artwork, base + "/downloaded-cover.jpg")
    let reimported = try XCTUnwrap(absent)
    try database.writeSync { try reimported.insert($0) }
    func playerTitleButton() -> NSObject? {
      self.accessible(window).first { element in
        self.attribute(element, "accessibilityLabel") as? String == "Downloaded feature" &&
          self.attribute(element, "accessibilityRole") as? String == "AXButton"
      }
    }
    try await waitFor("M3U film title is an accessible detail button") { playerTitleButton() != nil }
    let removed = try database.writeSync { db in
      let row = try DBM3UChannel.filter(Column("playlistId") == source.id && Column("id") == film.streamKey).fetchOne(db)
      if let row { _ = try row.delete(db) }
      return row
    }
    try await waitFor("Removed movie loses its detail button without interrupting playback") {
      playerTitleButton() == nil && session.engine.isPlaybackEstablished
    }
    let restored = try XCTUnwrap(removed)
    try database.writeSync { try restored.insert($0) }
    try await waitFor("Reimported movie restores its detail button") { playerTitleButton() != nil }
    try database.writeSync { db in
      var channel = restored
      channel.url = base + "/broadcast.ts"
      channel.groupTitle = "News"
      try channel.update(db)
    }
    try await waitFor("A reclassified live channel has no movie detail") {
      playerTitleButton() == nil && session.engine.isPlaybackEstablished
    }
    let watchedFilm = DBWatchHistory(id: "offline-history", playlistId: source.id, streamId: film.streamKey,
      type: "vod", lastTimeMs: 1000, durationMs: 8000, lastWatchedAt: Date(), title: film.title)
    let replay = try await MediaSelection.history(watchedFilm, source: source, database: database)
    XCTAssertEqual(replay.url, local)
    XCTAssertEqual(replay.type, "vod")
    XCTAssertEqual(replay.downloadID, id)
    XCTAssertEqual(replay.title, "Downloaded feature")
    XCTAssertEqual(replay.secondaryTitle, "Offline cinema")
    XCTAssertEqual(replay.artwork, base + "/downloaded-cover.jpg")
    try database.writeSync { try restored.update($0) }
    try await waitFor("Changing the entry back to a film restores navigation") { playerTitleButton() != nil }
    try XCTUnwrap(playerTitleButton()).perform(NSSelectorFromString("accessibilityPerformPress"))
    try await waitFor("Offline M3U film returns to its detail") {
      !session.expanded && session.engine.isPlaybackEstablished &&
        self.named(L("download.completed"), window) != nil
    }
    session.close()
    func saveHistory(at milliseconds: Int) throws {
      try database.writeSync { db in
        try DBWatchHistory(id: "\(source.id)_vod_\(film.streamKey)", playlistId: source.id,
                           streamId: film.streamKey, type: "vod", lastTimeMs: milliseconds,
                           durationMs: 8000, lastWatchedAt: Date(), title: film.title).save(db)
      }
    }
    try saveHistory(at: 6000)
    try await waitFor("Movie detail observes the saved position and offers both actions") {
      self.named(L("detail.resume"), window) != nil && self.named(L("detail.restart"), window) != nil
        && self.named(DetailFormatting.formatMs(6000), window) != nil
    }
    window.setContentSize(NSSize(width: 800, height: 560))
    try await waitFor("Compact detail keeps all four actions inside the window") {
      [L("detail.resume"), L("detail.restart"), ML("favorite"), L("download.completed")].allSatisfy { label in
        guard let action = self.named(label, window),
              let bounds = (self.attribute(action, "accessibilityFrame") as? NSValue)?.rectValue else { return false }
        return bounds.width > 0 && bounds.height > 0 && window.frame.contains(bounds)
      }
    }
    try await capture(window, name: "Compact movie detail actions")
    try await press(L("detail.resume"), in: window)
    try await waitFor("Offline film resumes near six seconds") {
      session.engine.isPlaybackEstablished && session.position >= 5.5
    }
    session.close()
    try await waitFor("Restart remains available") { self.named(L("detail.restart"), window) != nil }
    try await press(L("detail.restart"), in: window)
    try await waitFor("Explicit restart decodes from the beginning") {
      session.engine.isPlaybackEstablished && session.position > 0.05 && session.position < 2
    }
    session.close()
    window.setContentSize(NSSize(width: 1140, height: 738))
    try saveHistory(at: 7900)
    try await waitFor("Finished film offers play from beginning") {
      self.named(L("movie.play"), window) != nil && self.named(L("detail.restart"), window) == nil
    }
    try saveHistory(at: 6000)
    _ = try await database.write { db in
      try DBM3UChannel.filter(Column("playlistId") == source.id && Column("id") == film.streamKey).deleteAll(db)
    }
    try selectSidebarRow(L("history.title"), in: window)
    try await waitFor("History retains the removed provider film") { self.named(film.title, window) != nil }
    try await press(film.title, in: window)
    try await waitFor("History resumes the offline file after provider removal") {
      session.current?.url.isFileURL == true && session.current?.downloadID == id &&
        session.engine.isPlaybackEstablished && session.position >= 5.5
    }
    session.close()
    await DownloadManager.shared.delete(id: id)
  }

  private func selectSidebarRow(_ title: String, in window: NSWindow) throws {
    let elements = accessible(window)
    let sidebar = try XCTUnwrap(elements.compactMap { $0 as? NSTableView }.first)
    for label in elements where ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].contains(where: {
      attribute(label, $0) as? String == title
    }) {
      guard let frame = (attribute(label, "accessibilityFrame") as? NSValue)?.rectValue else { continue }
      let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
      let local = sidebar.convert(point, from: nil)
      let row = sidebar.row(at: local)
      if local.x >= sidebar.bounds.minX, local.x <= sidebar.bounds.maxX, row >= 0 {
        sidebar.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return
      }
    }
    throw TestFailure("Sidebar row not visible: \(title)")
  }

  func testDiscoverKeepsResumableMovieAndRecentlyWatchedChannelsInSeparateShelves() async throws {
    let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: fixture)), pace: 2)
    try panel.start()
    defer { panel.stop() }
    let source = Playlist(name: "Discovery library", serverURL: "http://127.0.0.1:\(panel.port)",
                          username: "user", password: "pass", epgEnabled: false)
    let db = AppDatabase.empty()
    try db.writeSync { db in
      try source.insert(db)
      for n in 1...46 {
        try DBWatchHistory(id: "live-\(n)", playlistId: source.id, streamId: "\(n)", type: "live",
          lastTimeMs: 0, durationMs: 0, lastWatchedAt: Date(timeIntervalSince1970: Double(200-n)),
          title: "Watched channel \(n)").insert(db)
      }
      try DBLiveStream(streamId: 1, name: "Catalogue channel", playlistId: source.id).insert(db)
      try DBVODStream(streamId: 1, name: "Harbor Lights", playlistId: source.id).insert(db)
      for (id, type, time, watched, title) in [
        ("1", "vod", 50, 45000, "Film to resume"),
        ("2", "series", 60, 100000, "Finished latest episode"),
        ("3", "series", 40, 20000, "Old unfinished episode")] {
        try DBWatchHistory(id: "saved-\(id)", playlistId: source.id, streamId: id, type: type,
          lastTimeMs: watched, durationMs: 100000, lastWatchedAt: Date(timeIntervalSince1970: Double(time)),
          seriesId: type == "series" ? "10" : nil, title: title).insert(db)
      }
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let player = DesktopPlayback(database: db)
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(player).defaultAppStorage(defaults))
    defer { player.close(); window.close() }
    try await waitFor("Older movie and recent channels both available") {
      self.named("Film to resume", window) != nil && self.named(ML("recent_live_channels"), window) != nil
    }
    XCTAssertNil(named("Old unfinished episode", window))
    try await capture(window, name: "Continue watching and recent channels")
    try await press(ML("see_all") + " · " + ML("recent_live_channels"), in: window)
    try await waitFor("All recent channels opens live history only") {
      self.named("Watched channel 1", window) != nil && self.named("Film to resume", window) == nil &&
        self.named(L("history.clear.title"), window) != nil
    }
    try selectSidebarRow(ML("discover"), in: window)
    try await waitFor("Recently watched channels are ready to play") { self.named(ML("recent_live_channels"), window) != nil }
    try await press("Watched channel 1", in: window)
    try await waitFor("Recently watched channel decodes") {
      player.current?.type == "live" && player.current?.streamId == "1" && player.engine.isPlaybackEstablished
    }
  }

  func testOpeningAnotherWindowRestoresLastContentSectionAfterSettings() async throws {
    let db = AppDatabase.empty()
    let source = Playlist(name: "Series library", serverURL: "https://fixture.invalid", epgEnabled: false)
    try db.writeSync {
      try source.insert($0)
      try DBSeries(seriesId: 1, name: "Restored series", playlistId: source.id).insert($0)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    func library() -> NSWindow {
      window(for: SourceLibrary().environment(\.appDatabase, db)
        .environmentObject(LocalizationManager.shared).environmentObject(DesktopPlayback(database: db))
        .defaultAppStorage(defaults))
    }
    let first = library()
    try await waitFor("Library loaded") { self.named(L("dashboard.series"), first) != nil }
    try selectSidebarRow(L("dashboard.series"), in: first)
    try await waitFor("Series selected and remembered") { defaults.string(forKey: "mac.lastXtreamSection") == "series" }
    try await press(L("dashboard.settings"), in: first)
    first.close()
    let reopened = library()
    defer { reopened.close() }
    try await waitFor("New window restores the series catalogue after closing in settings") {
      self.named("Restored series", reopened) != nil && self.named(L("favorites.title"), reopened) != nil &&
        self.accessible(reopened).contains { self.attribute($0, "accessibilityIdentifier") as? String == "catalog-favorites" }
    }
  }

  func testSearchGroupsRankedResultsAndFavoritesPlayOnlyMatchingChannels() async throws {
    let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let panel = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: clip)), pace: 2)
    try panel.start()
    defer { panel.stop() }
    let db = AppDatabase.empty()
    let source = Playlist(name: "Local search", serverURL: "http://127.0.0.1:\(panel.port)",
                          username: "user", password: "pass", epgEnabled: false)
    try db.writeSync { db in
      try source.insert(db)
      for n in 1...8 {
        try DBLiveStream(streamId: n, name: n == 1 ? "Harbor" : n == 8 ? "Mountain" : "Harbor \(n)",
          categoryId: n == 7 ? "blocked" : nil, sortIndex: n, playlistId: source.id).insert(db)
      }
      try DBVODStream(streamId: 1, name: "Harbor movie", playlistId: source.id).insert(db)
      try DBSeries(seriesId: 1, name: "Harbor series", playlistId: source.id).insert(db)
      for n in [1, 2, 7, 8] { try DBFavorite(streamId: n, playlistId: source.id, type: "live").insert(db) }
      try DBFavorite(streamId: 1, playlistId: source.id, type: "vod").insert(db)
      try DBWatchHistory(id: "favorite-film", playlistId: source.id, streamId: "1", type: "vod",
        lastTimeMs: 4000, durationMs: 10000, lastWatchedAt: .now, title: "Harbor movie").insert(db)
    }
    let hidden = HiddenCategoryStore.shared
    hidden.setHidden(true, playlistId: source.id, type: "live", categoryId: "blocked")
    defer { hidden.setHidden(false, playlistId: source.id, type: "live", categoryId: "blocked") }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let session = DesktopPlayback(database: db)
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(session).defaultAppStorage(defaults))
    defer { session.close(); window.close() }
    func editSearch(_ value: String) async throws {
      func field(_ view: NSView) -> NSSearchField? {
        if let search = view as? NSSearchField { return search }
        return view.subviews.lazy.compactMap { field($0) }.first
      }
      try await waitFor("Native search field attached to the window toolbar") { window.contentView?.superview.flatMap(field) != nil }
      let search = try XCTUnwrap(window.contentView?.superview.flatMap(field))
      window.makeFirstResponder(search)
      let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
      editor.selectAll(nil)
      editor.insertText(value, replacementRange: editor.selectedRange())
    }
    try await waitFor("Search available in sidebar") { self.named(L("search.title"), window) != nil }
    try selectSidebarRow(L("search.title"), in: window)
    try await waitFor("Idle search explains the minimum") { self.named(L("search.min_chars"), window) != nil }
    try await capture(window, name: "Empty catalogue search")
    try await editSearch("H")
    try await Task.sleep(for: .milliseconds(320))
    XCTAssertNotNil(named(L("search.min_chars"), window))
    XCTAssertNil(named("Harbor", window))
    try await editSearch("Harbor")
    try await waitFor("Each kind gets its own preview") {
      self.named("Harbor", window) != nil && self.named("Harbor movie", window) != nil &&
        self.named("Harbor series", window) != nil && self.named(L("search.more_results_format", 2), window) != nil
    }
    XCTAssertNil(named("Harbor 5", window))
    try await capture(window, name: "Grouped catalogue search")
    try await press(L("search.more_results_format", 2), in: window)
    try await waitFor("More results opens just matching channels") {
      self.named("Harbor 6", window) != nil && self.named("Harbor movie", window) == nil
    }
    XCTAssertNil(named("Harbor 7", window))
    try selectSidebarRow(L("favorites.title"), in: window)
    try await waitFor("Favorites opens on saved movies") {
      self.named("Harbor movie", window) != nil && self.named("Mountain", window) == nil
    }
    try await waitFor("Favorite movie exposes its viewing progress") {
      self.named(BrowseAccessibility.progressValue(0.4), window) != nil
    }
    try await db.write { try $0.execute(sql: "UPDATE watchHistory SET lastTimeMs = 7000 WHERE id = 'favorite-film'") }
    try await waitFor("Progress on the favorite updates while the screen is open") {
      self.named(BrowseAccessibility.progressValue(0.7), window) != nil
    }
    try await capture(window, name: "Watched favorite movie")
    try selectSidebarRow(L("dashboard.series"), in: window)
    try await waitFor("Series catalogue and category picker open") {
      self.named("Harbor series", window) != nil && self.named(L("category_picker.title"), window) != nil
    }
    try await press(L("category_picker.title"), in: window)
    let picker = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await press(L("content.uncategorized"), in: picker)
    try await waitFor("Series without a provider category remains selectable") {
      self.named("Harbor series", window) != nil && self.named(L("content.uncategorized"), window) != nil
    }
    try await capture(window, name: "Uncategorized series")
    try await press(L("favorites.title"), in: window)
    try await waitFor("Series catalogue shortcut opens the matching empty favorites tab") {
      self.named(L("favorites.empty.series"), window) != nil
    }
    try await press(L("dashboard.live"), in: window)
    try await waitFor("Live favorites lists saved channels") { self.named("Mountain", window) != nil }
    try await editSearch("Harbor")
    try await waitFor("Searched favorites exclude other channels") {
      self.named("Harbor", window) != nil && self.named("Mountain", window) == nil
    }
    try await capture(window, name: "Filtered live favorites")
    try await press("Harbor", in: window)
    try await waitFor("Real decoder starts with just the two matching favorite channels") {
      session.engine.isPlaybackEstablished && session.queue?.items.map(\.id) == ["1", "2"]
    }
  }

  func testUnavailableM3UHistoryOffersRemoval() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Library", serverURL: "https://fixture.invalid/list.m3u", type: .m3u)
    let row = DBWatchHistory(id: UUID().uuidString, playlistId: source.id, streamId: "removed",
      type: "vod", lastTimeMs: 60000, durationMs: 180000, lastWatchedAt: Date(), title: "Lost film")
    try database.writeSync { db in
      try source.insert(db)
      try row.insert(db)
    }
    let session = DesktopPlayback(database: database)
    let discover = window(for: MacDiscoverView(source: source, open: { _ in }, browse: { _ in }, history: { _ in })
      .environment(\.appDatabase, database).environmentObject(session))
    defer { discover.close() }
    func alertWindow(for window: NSWindow) -> NSWindow? {
      ([window] + (window.childWindows ?? []) + [window.attachedSheet].compactMap { $0 })
        .first { self.named(L("m3u.history.unavailable.message"), $0) != nil }
    }
    try await waitFor("Missing film appears in Continue Watching") { self.named(row.title, discover) != nil }
    try await press(row.title, in: discover)
    try await waitFor("Discover explains unavailable film") { alertWindow(for: discover) != nil }
    try await press(L("common.cancel"), in: XCTUnwrap(alertWindow(for: discover)))
    try await waitFor("Cancellation keeps the film on Discover") {
      alertWindow(for: discover) == nil && self.named(row.title, discover) != nil
    }
    let saved = try await database.read { try DBWatchHistory.fetchOne($0, key: row.id) }
    XCTAssertEqual(saved?.lastTimeMs, row.lastTimeMs)
    XCTAssertNil(session.current)
    let window = window(for: MacHistory(source: source, query: "").environment(\.appDatabase, database)
      .environmentObject(session))
    defer { window.close() }
    try await waitFor("Missing movie in history") { self.named(row.title, window) != nil }
    try await press(row.title, in: window)
    try await waitFor("Unavailable history prompt") { alertWindow(for: window) != nil }
    XCTAssertNil(session.current)
    try await press(L("history.item.remove"), in: XCTUnwrap(alertWindow(for: window)))
    try await waitFor("Removed unavailable entry") { self.named(L("history.empty.title"), window) != nil }
  }

  func testHistoryScopeSearchAndConfirmedClearKeepOtherTypesAndSources() async throws {
    let db = AppDatabase.empty()
    let source = Playlist(name: "History library", serverURL: "https://fixture.invalid", epgEnabled: false)
    let other = Playlist(name: "Other source", serverURL: "https://other.invalid", epgEnabled: false)
    try db.writeSync { db in
      try source.insert(db)
      try other.insert(db)
      for n in 0..<130 {
        try DBWatchHistory(id: "movie-\(n)", playlistId: source.id, streamId: "\(n)", type: "vod",
          lastTimeMs: 65000, durationMs: 180000, lastWatchedAt: Date(timeIntervalSince1970: Double(n)),
          title: n == 0 ? "Oldest film" : "Movie \(n)").insert(db)
      }
      for (playlist, type, title) in [(source, "live", "Today's channel"), (source, "series", "Harbor pilot"),
                                      (other, "vod", "Other source film")] {
        try DBWatchHistory(id: title, playlistId: playlist.id, streamId: "1", type: type,
          lastTimeMs: 0, durationMs: 0, lastWatchedAt: Date(), title: title).insert(db)
      }
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(DesktopPlayback(database: db))
      .defaultAppStorage(defaults))
    defer { window.close() }
    try await waitFor("History available in sidebar") { self.named(L("history.title"), window) != nil }
    try selectSidebarRow(L("history.title"), in: window)
    try await waitFor("All types shown initially") { self.named("Today's channel", window) != nil }
    try await press(L("dashboard.movies"), in: window)
    try await waitFor("Movie scope excludes channels and series") {
      self.named(L("history.title.vod"), window) != nil &&
        self.named("Movie 129", window) != nil && self.named("Today's channel", window) == nil
    }
    func field(_ view: NSView) -> NSSearchField? {
      if let field = view as? NSSearchField { return field }
      return view.subviews.lazy.compactMap { field($0) }.first
    }
    let search = try XCTUnwrap(window.contentView?.superview.flatMap(field))
    window.makeFirstResponder(search)
    let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
    editor.insertText("Oldest", replacementRange: editor.selectedRange())
    try await waitFor("Search finds a movie beyond the initial page") { self.named("Oldest film", window) != nil }
    try await capture(window, name: "Scoped movie history search")
    try await press(L("history.clear.title"), in: window)
    func confirmation() -> NSWindow? {
      ([window.attachedSheet].compactMap { $0 } + (window.childWindows ?? []) + [window])
        .first { self.named(L("history.clear.message.vod"), $0) != nil }
    }
    try await waitFor("History confirmation names selected scope") { confirmation() != nil }
    try await press(L("history.clear.label"), in: XCTUnwrap(confirmation()))
    try await waitFor("Scoped history empty") { self.named(L("history.empty.title"), window) != nil }
    let retained = try await db.read { try DBWatchHistory.fetchAll($0).map(\.title).sorted() }
    XCTAssertEqual(retained, ["Harbor pilot", "Other source film", "Today's channel"])
  }

  func testDownloadLibraryGroupsEpisodesAndSearchesBySeriesTitle() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Download library", serverURL: "https://fixture.invalid", epgEnabled: false)
    try database.writeSync { db in
      try source.insert(db)
      for (id, kind, title, series, season, episode, status) in [
        ("1", "vod", "An independent film", "Cinema", 0, 0, "completed"),
        ("2", "episode", "Harbor pilot", "Harbor", 1, 1, "completed"),
        ("3", "episode", "Winter ferry", "Harbor", 2, 1, "completed"),
        ("4", "vod", "Earlier request", "", 0, 0, "queued"),
        ("5", "vod", "Later request", "", 0, 0, "queued"),
        ("6", "episode", "Survey in progress", "Coast", 1, 1, "downloading"),
        ("7", "vod", "Unavailable film", "", 0, 0, "failed")
      ] {
        try DBDownloadedItem(id: id, playlistId: source.id, streamId: id, type: kind, title: title,
          secondaryTitle: series.isEmpty ? nil : series, remoteURL: "https://fixture.invalid/movie.mkv",
          localPath: id + ".mkv", totalBytes: 10000, downloadedBytes: status == "downloading" ? 4300 : 10000,
          status: status, createdAt: Date(timeIntervalSince1970: Double(id)!),
          seasonNumber: season, episodeNumber: episode).insert(db)
      }
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let window = window(for: SourceLibrary().environment(\.appDatabase, database)
      .environmentObject(LocalizationManager.shared).environmentObject(DesktopPlayback(database: database))
      .defaultAppStorage(defaults))
    defer { window.close() }
    try await waitFor("Downloads in sidebar") { self.named(L("download.title"), window) != nil }
    try selectSidebarRow(L("download.title"), in: window)
    try await waitFor("Download status sections and completed films") {
      self.named("An independent film", window) != nil && self.named("Survey in progress", window) != nil
    }
    try await capture(window, name: "Native downloads library")
    func field(_ view: NSView) -> NSSearchField? {
      if let field = view as? NSSearchField { return field }
      return view.subviews.lazy.compactMap { field($0) }.first
    }
    let search = try XCTUnwrap(window.contentView?.superview.flatMap(field))
    window.makeFirstResponder(search)
    let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
    editor.insertText("Harbor", replacementRange: editor.selectedRange())
    try await waitFor("Series search includes both seasons and excludes other movies") {
      self.named("Harbor pilot", window) != nil && self.named("Winter ferry", window) != nil &&
        self.named("An independent film", window) == nil
    }
    XCTAssertNotNil(named(L("series.season_format", 2) + " · " + L("series.episode_format", 1), window))
    try await capture(window, name: "Downloaded episodes by series")
    editor.selectAll(nil)
    editor.insertText("Cinema", replacementRange: editor.selectedRange())
    try await waitFor("Category search finds the movie") {
      self.named("An independent film", window) != nil && self.named("Winter ferry", window) == nil
    }
    editor.selectAll(nil)
    editor.insertText("no-such-title", replacementRange: editor.selectedRange())
    try await waitFor("Empty search result") { self.named(L("favorites.empty.no_result.title"), window) != nil }
    try database.writeSync { db in
      _ = try DBDownloadedItem.filter(Column("playlistId") == source.id).deleteAll(db)
    }
    try await waitFor("An empty library shows the downloads explanation even with a query") {
      self.named(L("download.empty.title"), window) != nil
    }
  }

  func testActiveDownloadCanBeKeptThenCancelledFromLibrary() async throws {
    let panel = MockPanelServer(stream: .init(transportStream: Data()), script: .headersOnly)
    try panel.start()
    defer { panel.stop() }
    let database = AppDatabase.shared
    let source = Playlist(name: "Local", serverURL: panel.streamURL.absoluteString, epgEnabled: false)
    try database.writeSync { try source.insert($0) }
    let id = DownloadManager.idFor(vod: source.id, streamId: 17)
    defer {
      _ = try? database.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    await DownloadManager.shared.enqueue(id: id, playlistId: source.id, streamId: "17", type: "vod",
      title: "In flight", secondaryTitle: nil, imageURL: nil, remoteURL: panel.streamURL, containerExtension: "ts")
    let window = window(for: MacDownloads(source: source, query: "").environment(\.appDatabase, database)
      .environmentObject(DesktopPlayback(database: database)))
    defer { window.close() }
    try await waitFor("Actual background download holds provider connection", timeout: 20) {
      panel.stats.open == 1 && self.named(L("download.cancel"), window) != nil
    }
    func confirmation() -> NSWindow? {
      ([window] + (window.childWindows ?? []) + [window.attachedSheet].compactMap { $0 })
        .first { self.named(ML("keep_transfer"), $0) != nil }
    }
    try await press(L("download.cancel"), in: window)
    try await waitFor("Confirm which download should stop") { confirmation() != nil }
    try await press(ML("keep_transfer"), in: XCTUnwrap(confirmation()))
    XCTAssertEqual(panel.stats.open, 1)
    try await press(L("download.cancel"), in: window)
    try await waitFor("Cancel choice available") { confirmation() != nil }
    try await press(ML("cancel_transfer"), in: XCTUnwrap(confirmation()))
    try await waitFor("Confirmed stop removes row and releases slot", timeout: 12) {
      panel.stats.open == 0 && self.named(L("download.empty.title"), window) != nil
    }
    let removed = try await database.read { try DBDownloadedItem.fetchOne($0, key: id) }
    XCTAssertNil(removed)
  }

  func testEpisodeDownloadUsesUpdatedSeriesMetadata() async throws {
    let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    let server = MockPanelServer(stream: .init(transportStream: try Data(contentsOf: fixture)), script: .download)
    try server.start()
    defer { server.stop() }
    let source = Playlist(name: "Cinema", serverURL: "http://127.0.0.1:\(server.port)",
      username: "viewer", password: "local", epgEnabled: false)
    let db = AppDatabase.shared
    defer {
      _ = try? db.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    let season = DBSeason.scopedId(playlistId: source.id, seriesId: 7, seasonNumber: 2)
    try db.writeSync { db in
      try source.insert(db)
      try DBSeries(seriesId: 7, name: "Harbor", seasonsLoaded: true, playlistId: source.id).insert(db)
      try DBSeason(id: DBSeason.scopedId(playlistId: source.id, seriesId: 7, seasonNumber: 1),
        seasonNumber: 1, seriesId: 7, playlistId: source.id).insert(db)
      try DBSeason(id: season, seasonNumber: 2, seriesId: 7, playlistId: source.id).insert(db)
      try DBEpisode(id: "3", episodeId: nil,
        episodeNum: 3, title: "Crossing", containerExtension: "ts", seasonId: season).insert(db)
    }
    let otherSource = Playlist(name: "Other cinema", serverURL: source.serverURL, epgEnabled: false)
    defer { _ = try? db.writeSync { try otherSource.delete($0) } }
    try db.writeSync { db in
      try otherSource.insert(db)
      try DBSeries(seriesId: 7, name: "Other series", playlistId: otherSource.id).insert(db)
      let otherSeason = DBSeason.scopedId(playlistId: otherSource.id, seriesId: 7, seasonNumber: 1)
      try DBSeason(id: otherSeason, seasonNumber: 1, seriesId: 7, playlistId: otherSource.id).insert(db)
      XCTAssertNil(try SeriesDetailData.episode(streamId: "3", playlistId: otherSource.id, db: db))
      try DBEpisode(id: DBEpisode.scopedId(playlistId: otherSource.id, panelEpisodeId: "3"), episodeId: "3",
        episodeNum: 1, title: "Other crossing", seasonId: otherSeason).insert(db)
      try DBEpisode(id: DBEpisode.scopedId(playlistId: otherSource.id, panelEpisodeId: "4"), episodeId: "4",
        episodeNum: 2, title: "Other sequel", seasonId: otherSeason).insert(db)
      let otherNavigation = try SeriesPlaybackOrdering.navigationContext(playlistId: otherSource.id,
        playbackStreamId: "3", seriesIdHint: nil, db: db)
      XCTAssertEqual(otherNavigation.next?.title, "Other sequel")
      let navigation = try SeriesPlaybackOrdering.navigationContext(playlistId: source.id,
        playbackStreamId: "3", seriesIdHint: nil, db: db)
      XCTAssertNil(navigation.next)
      XCTAssertEqual(try SeriesDetailData.episode(streamId: "3", playlistId: otherSource.id, db: db)?.title, "Other crossing")
      XCTAssertEqual(try SeriesDetailData.episode(streamId: "3", playlistId: source.id, db: db)?.title, "Crossing")
    }
    let item = CatalogItem(playlistId: source.id, kind: "series", streamKey: "7", title: "Harbor",
      category: "", artwork: nil, rating: nil, favorite: false, sortIndex: 0)
    let session = DesktopPlayback(database: db)
    let window = window(for: MacMediaDetail(item: item, source: source).environment(\.appDatabase, db)
      .environmentObject(session))
    defer { session.close(); window.close() }
    try await waitFor("Episode download control appears") { self.named(L("download.action"), window) != nil }
    let cover = "http://127.0.0.1:1/harbor.jpg"
    try db.writeSync { db in
      try db.execute(sql: "UPDATE series SET name = ?, cover = ? WHERE playlistId = ? AND seriesId = 7",
        arguments: ["Harbor restored", cover, source.id])
    }
    try await waitFor("Updated series available before download") { self.named("Harbor restored", window) != nil }
    try await press(L("download.action"), in: window)
    try await waitFor("Episode downloads", timeout: 25) { self.named(L("download.completed"), window) != nil }
    let id = DownloadManager.idFor(episode: source.id, episodeId: "3")
    let stored = try await db.read { try DBDownloadedItem.fetchOne($0, key: id) }
    let row = try XCTUnwrap(stored)
    XCTAssertEqual(row.secondaryTitle, "Harbor restored")
    XCTAssertEqual(row.imageURL, cover)
    XCTAssertEqual(row.seasonNumber, 2)
    XCTAssertEqual(row.episodeNumber, 3)
    let file = await DownloadManager.shared.localURL(forId: id)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(file)), try Data(contentsOf: fixture))
    server.stop()
    try await press(L("movie.play"), in: window)
    try await waitFor("Series play skips empty first season and decodes downloaded episode") {
      session.current?.streamId == "3" && session.current?.seriesId == "7"
        && session.engine.isPlaybackEstablished && session.position > 0.1
    }
  }

  func testMissingDownloadedEpisodeRetriesAndResumesOfflineFromLibrary() async throws {
    try await checkMissingDownload(isEpisode: true)
  }

  func testMissingDownloadedMovieRetriesAndResumesOfflineFromLibrary() async throws {
    try await checkMissingDownload(isEpisode: false)
  }

  private func checkMissingDownload(isEpisode: Bool) async throws {
    let type = isEpisode ? "episode" : "vod"
    let historyType = isEpisode ? "series" : "vod"
    let title = isEpisode ? "Missing episode" : "Missing movie"
    let seriesID: String? = isEpisode ? "4" : nil
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("feature.mkv"))
    let server = LocalHTTPServer(directory: root)
    try server.start()
    defer { server.stop() }
    let source = Playlist(name: "Downloads", serverURL: "http://127.0.0.1:\(server.port)", epgEnabled: false)
    let database = AppDatabase.shared
    let id = isEpisode ? DownloadManager.idFor(episode: source.id, episodeId: "3")
      : DownloadManager.idFor(vod: source.id, streamId: 3)
    let path = DownloadStorage.relativePath(playlistId: source.id, type: type, streamId: "3", ext: "mkv")
    defer {
      _ = try? database.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    try database.writeSync { db in
      try source.insert(db)
      if isEpisode {
        try DBSeries(seriesId: 4, name: "Harbor series", seasonsLoaded: true, playlistId: source.id).insert(db)
      }
      try DBDownloadedItem(id: id, playlistId: source.id, streamId: "3", type: type, title: title,
        secondaryTitle: "Harbor", remoteURL: source.serverURL + "/feature.mkv", localPath: path,
        containerExtension: "mkv", status: "completed", seriesId: seriesID, seasonNumber: isEpisode ? 2 : nil, episodeNumber: isEpisode ? 3 : nil).insert(db)
      try DBWatchHistory(id: "\(source.id)_\(historyType)_3", playlistId: source.id, streamId: "3", type: historyType,
        lastTimeMs: 6000, durationMs: 60000, lastWatchedAt: Date(), seriesId: seriesID, title: title).insert(db)
    }
    let session = DesktopPlayback(database: database)
    let window = window(for: MacDownloads(source: source, query: "").environment(\.appDatabase, database)
      .environmentObject(session))
    defer { session.close(); window.close() }
    try await waitFor("Missing file row is present") { self.named(title, window) != nil }
    try await press(L("movie.play"), in: window)
    func prompt() -> NSWindow? {
      ([window] + (window.childWindows ?? []) + [window.attachedSheet].compactMap { $0 })
        .first { self.named(L("download.retry"), $0) != nil }
    }
    try await waitFor("Missing file has retry action") { prompt() != nil }
    try await press(L("download.retry"), in: XCTUnwrap(prompt()))
    let deadline = Date().addingTimeInterval(25)
    var file: URL?
    while file == nil, Date() < deadline {
      file = await DownloadManager.shared.localURL(forId: id)
      if file == nil { try await Task.sleep(for: .milliseconds(100)) }
    }
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(file)), try Data(contentsOf: fixture))
    server.stop()
    try await waitFor("Retried download becomes playable") { self.named(L("movie.play"), window) != nil }
    try await press(L("movie.play"), in: window)
    try await waitFor("Offline download decodes at saved playhead") {
      session.engine.isPlaybackEstablished && session.current?.type == historyType && session.current?.seriesId == seriesID && session.position >= 5.5
    }
    if isEpisode {
      let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
      defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
      let workspace = self.window(for: SourceLibrary().modifier(MacPlaybackPresentation(playback: session))
        .environment(\.appDatabase, database).environmentObject(LocalizationManager.shared)
        .environmentObject(session).defaultAppStorage(defaults))
      defer { workspace.close() }
      try await waitFor("Episode title is an accessible detail button") {
        self.accessible(workspace).contains { element in
          self.attribute(element, "accessibilityLabel") as? String == title &&
            self.attribute(element, "accessibilityRole") as? String == "AXButton"
        }
      }
      try await press(title, in: workspace)
      try await waitFor("Episode title opens its series while the downloaded episode keeps playing") {
        !session.expanded && session.engine.isPlaybackEstablished && session.current?.streamId == "3" &&
          self.named("Harbor series", workspace) != nil && self.named(ML("favorite"), workspace) != nil
      }
      try await capture(workspace, name: "Series detail from downloaded episode")
    }
  }

  func testBackgroundDownloadOfflinePlayAndDeletion() async throws {
    let fixture = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("91.mkv")
    try FileManager.default.copyItem(at: fixture, to: file)
    let http = LocalHTTPServer(directory: directory)
    try http.start()
    defer { http.stop() }
    let source = Playlist(name: "Offline fixture", serverURL: "http://127.0.0.1:\(http.port)", username: "user", password: "pass")
    try await AppDatabase.shared.write { db in
      try source.insert(db)
      try DBVODStream(streamId: 91, name: "Offline fixture", categoryId: "group",
        containerExtension: "mkv", playlistId: source.id).insert(db)
      try DBCategory(id: "group", name: "Previous", type: "vod", playlistId: source.id).insert(db)
      try DBCategory(id: "group", name: "News", type: "live", playlistId: source.id).insert(db)
    }
    defer { _ = try? AppDatabase.shared.writeSync { try source.delete($0) } }
    let manager = DownloadManager.shared
    let id = DownloadManager.idFor(vod: source.id, streamId: 91)
    let films = try await AppDatabase.shared.read {
      try MacCatalogQuery(playlistID: source.id, kinds: [.vod]).fetch($0)
    }
    let film = try XCTUnwrap(films.first)
    XCTAssertEqual(film.category, "Previous")
    try await AppDatabase.shared.write { db in
      try db.execute(sql: "UPDATE category SET name = 'Cinema' WHERE playlistId = ? AND type = 'vod'",
                     arguments: [source.id])
    }
    var selection = try await MediaSelection.resolve(film, in: source, database: .shared)
    let history = DBWatchHistory(id: "saved-film", playlistId: source.id, streamId: "91", type: "vod",
      lastTimeMs: 1000, durationMs: 8000, lastWatchedAt: Date(), title: "Previous film", containerExtension: "mp4")
    let refreshed = try await MediaSelection.history(history, source: source, database: .shared)
    XCTAssertEqual(refreshed.url, selection.url)
    XCTAssertEqual(refreshed.title, film.title)
    XCTAssertEqual(selection.url.path, "/movie/user/pass/91.mkv")
    // The local fixture server serves files directly under its root.
    selection.url = try XCTUnwrap(URL(string: source.serverURL + "/91.mkv"))
    let button = MacDownloadAction(id: id, play: {}) {
      Task { await selection.enqueueDownload() }
    }
    let downloadWindow = window(for: button.environment(\.appDatabase, AppDatabase.shared))
    defer { downloadWindow.close() }
    try await press(L("download.action"), in: downloadWindow)
    let deadline = Date().addingTimeInterval(25)
    var local: URL?
    repeat {
      local = await manager.localURL(forId: id)
      if local != nil { break }
      let row = try await AppDatabase.shared.read { try DBDownloadedItem.fetchOne($0, key: id) }
      if row?.downloadStatus == .failed {
        throw TestFailure("Transfer failed: " + (row?.errorMessage ?? ""))
      }
      try await Task.sleep(for: .milliseconds(120))
    } while Date() < deadline
    let result = try XCTUnwrap(local)
    XCTAssertEqual(try Data(contentsOf: result), try Data(contentsOf: fixture))
    try await Task.sleep(for: .milliseconds(500))
    try await capture(downloadWindow, name: "Download diagnostic")
    try await waitFor("Download action updates after transfer") {
      self.named(L("download.completed"), downloadWindow) != nil
    }
    try await capture(downloadWindow, name: "Completed download action")
    http.stop()
    let session = DesktopPlayback()
    let downloaded = try await AppDatabase.shared.read { try DBDownloadedItem.fetchOne($0, key: id) }
    XCTAssertEqual(downloaded?.secondaryTitle, "Cinema")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let workspace = window(for: SourceLibrary().modifier(MacPlaybackPresentation(playback: session))
      .environment(\.appDatabase, AppDatabase.shared).environmentObject(LocalizationManager.shared)
      .environmentObject(session).defaultAppStorage(defaults))
    defer { workspace.close() }
    try await waitFor("Workspace ready") { self.named(L("download.title"), workspace) != nil }
    try selectSidebarRow(L("download.title"), in: workspace)
    session.start(selection)
    try await waitFor("Decoded downloaded media after server shutdown", timeout: 12) {
      session.engine.isPlaybackEstablished && session.engine.position > 0.1
    }
    try await press(selection.title, in: workspace)
    try await waitFor("Player title opens downloaded film detail while playback continues") {
      !session.expanded && session.engine.isPlaybackEstablished &&
        self.named(ML("favorite"), workspace) != nil
    }
    session.close()
    await manager.delete(id: id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: result.path))
    let removed = try await AppDatabase.shared.read { try DBDownloadedItem.fetchOne($0, key: id) }
    XCTAssertNil(removed)
    try await waitFor("Download action resets after deletion") {
      self.named(L("download.action"), downloadWindow) != nil
    }
  }

  private final class GuideUpdateProbe: ObservableObject {
    @Published var positionRequest = UUID()
    @Published var version = 0
    @Published var day = Date(timeIntervalSince1970: 0)
    var draws = 0
  }

  private struct ChangingGuide: View {
    @ObservedObject var probe: GuideUpdateProbe
    let row = EPGGuideItem.channel(EPGGuideRow(id: "1", channelKey: "1", displayName: "One",
      iconURL: nil, liveStream: nil, categoryId: "news", categoryTitle: "News"))
    var body: some View {
      MacGuideTable(layoutVersion: probe.version, headerHours: [probe.day], items: [row], channelWidth: 180, timelineWidth: 4800,
        horizontalPosition: probe.version == 0 ? 0 : 800, positionRequest: probe.positionRequest,
        header: AnyView(Text(verbatim: "Hours \(Int(probe.day.timeIntervalSince1970))")), channel: { _ in AnyView(Text("One")) }, timeline: { _ in
          probe.draws += 1
          return AnyView(Text(verbatim: "Revision \(probe.version)"))
        })
    }
  }

  func testGuidePositionRequestPreservesRowsAndGuideRefreshUpdatesThem() async throws {
    let probe = GuideUpdateProbe()
    let window = window(for: ChangingGuide(probe: probe))
    defer { window.close() }
    try await waitFor("Programme layout ready") { self.named("Revision 0", window) != nil }
    let draws = probe.draws
    probe.positionRequest = UUID()
    try await Task.sleep(for: .milliseconds(250))
    XCTAssertEqual(probe.draws, draws, "Jump to now should not rebuild programme views")
    probe.version = 1
    try await waitFor("Refresh updates a visible channel without changing row IDs") {
      self.named("Revision 1", window) != nil && probe.draws > draws
    }
    probe.day = Date(timeIntervalSince1970: 86400)
    try await waitFor("Changing day updates the native hour header") { self.named("Hours 86400", window) != nil }
  }

  func testOverlappingProgrammesCoverEndOfHalfHourTransitionDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Lord_Howe"))
    for (month, date, hours) in [(4, 5, 24.5), (10, 4, 23.5)] {
      let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: date, hour: 12)))
      let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: noon))
      let feature = EPGProgramme(channelKey: "news", title: "Live coverage",
        start: day.end.addingTimeInterval(-3600), stop: day.end.addingTimeInterval(600))
      let bulletin = EPGProgramme(channelKey: "news", title: "Bulletin",
        start: day.end.addingTimeInterval(-2400), stop: day.end.addingTimeInterval(-1200))
      let cells = EPGGuideViewModel.cells(for: [feature, bulletin], dayStart: day.start, dayEnd: day.end, hourWidth: 100)
      let lastHour = try XCTUnwrap(cells.first { $0.programme?.id == feature.id })
      XCTAssertEqual(lastHour.x + lastHour.width, hours * 100, accuracy: 0.001)
      XCTAssertEqual(cells.compactMap(\.programme).count, 2)
      XCTAssertFalse(cells.contains { $0.id == "gap-tail" })
    }
  }

  func testGuideClockStopsAtLocalMidnightAcrossDaylightSavingChange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    for (month, date, hours) in [(3, 8, 23), (11, 1, 25)] {
      let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: date, hour: 12)))
      let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: noon))
      let timeline = GuideDayTimeline(day: day)
      let before = day.start.addingTimeInterval(-300)
      let entries = Array(timeline.entries(from: before, mode: .normal))
      XCTAssertEqual(entries.first, before)
      XCTAssertEqual(entries[1], day.start)
      XCTAssertEqual(entries.last, day.end)
      XCTAssertEqual(entries.count, hours * 60 + 2)
      let late = day.end.addingTimeInterval(-3)
      XCTAssertEqual(Array(timeline.entries(from: late, mode: .normal)), [late, day.end])
    }
  }

  func testLargeGuideReusesRowsAndSynchronizesScrolling() async throws {
    try await checkLargeGuide(direction: .leftToRight)
  }

  func testArabicGuideMirrorsHoursAndKeepsChannelPinnedWhileScrolling() async throws {
    try await checkLargeGuide(direction: .rightToLeft)
  }

  private func checkLargeGuide(direction: LayoutDirection) async throws {
    let rtl = direction == .rightToLeft
    let channelName = rtl ? "القناة" : "Channel"
    let hourName = rtl ? "الساعة" : "Hour"
    let rows = (0..<10000).map { number in
      EPGGuideItem.channel(
        EPGGuideRow(
          id: String(number), channelKey: String(number),
          displayName: "Channel \(number)", iconURL: nil, liveStream: nil, categoryId: "news",
          categoryTitle: "News"))
    }
    var rendered = Set<String>()
    let guide = MacGuideTable(
      items: rows, channelWidth: 180, timelineWidth: 4800,
      horizontalPosition: 800, positionRequest: UUID(), header: AnyView(
        HStack(spacing: 0) {
          ForEach(0..<48) { hour in Text(verbatim: "\(hourName) \(hour)").frame(width: 100) }
        }),
      channel: { item in AnyView(Text(verbatim: "\(channelName) " + item.id)) },
      timeline: { item in
        rendered.insert(item.id)
        return AnyView(
          ZStack(alignment: .leading) {
            ForEach(0..<48) { hour in
              Text(verbatim: "\(item.id) · \(hour)").frame(width: 100, height: 48).offset(x: CGFloat(hour) * 100)
            }
          }.frame(width: 4800, alignment: .leading))
      })
    let window = window(for: guide.environment(\.layoutDirection, direction)
      .environment(\.locale, Locale(identifier: rtl ? "ar" : "en")))
    defer { window.close() }
    func tables(_ view: NSView) -> [NSTableView] {
      (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
    }
    try await waitFor("Guide tables ready") {
      window.contentView.map { tables($0).count == 2 } == true && !rendered.isEmpty
    }
    XCTAssertLessThan(rendered.count, 100, "Offscreen channels must not create programme views")
    let all = tables(try XCTUnwrap(window.contentView))
    let timeline = try XCTUnwrap(all.first { $0.tableColumns[0].width > 1000 })
    let labels = try XCTUnwrap(all.first { $0 !== timeline })
    let timelineScroll = try XCTUnwrap(timeline.enclosingScrollView)
    let labelScroll = try XCTUnwrap(labels.enclosingScrollView)
    let labelsFrame = labelScroll.convert(labelScroll.bounds, to: nil)
    let timelineFrame = timelineScroll.convert(timelineScroll.bounds, to: nil)
    XCTAssertTrue(rtl ? labelsFrame.minX >= timelineFrame.maxX : labelsFrame.maxX <= timelineFrame.minX)
    let target = rtl ? 4800 - timelineScroll.contentView.bounds.width - 800 : 800
    XCTAssertEqual(timelineScroll.contentView.bounds.minX, target, accuracy: 1)
    func center(_ name: String) throws -> CGFloat {
      let element = try XCTUnwrap(named(name, window), name)
      return try XCTUnwrap((attribute(element, "accessibilityFrame") as? NSValue)?.rectValue).midX
    }
    if rtl { XCTAssertNotNil(named("القنوات", window)) }
    let eighthHour = try center("\(hourName) 8")
    XCTAssertEqual(eighthHour, try center("0 · 8"), accuracy: 1)
    XCTAssertEqual(try center("\(hourName) 9") - eighthHour, rtl ? -100 : 100, accuracy: 1)
    if rtl { try await capture(window, name: "Arabic programme guide") }
    timeline.scrollRowToVisible(9999)
    try await waitFor("Last channel renders without materializing the whole guide") {
      rendered.contains("9999")
    }
    XCTAssertLessThan(rendered.count, 150)
    timelineScroll.scrollerStyle = .legacy
    timelineScroll.autohidesScrollers = false
    window.contentView?.layoutSubtreeIfNeeded()
    timeline.scrollRowToVisible(9999)
    XCTAssertEqual(
      timelineScroll.contentView.bounds.minY, labelScroll.contentView.bounds.minY, accuracy: 1)
    let y = timelineScroll.contentView.bounds.minY
    timelineScroll.contentView.scroll(to: NSPoint(x: 1900, y: y))
    timelineScroll.reflectScrolledClipView(timelineScroll.contentView)
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(labelScroll.contentView.bounds.minX, 0)
    XCTAssertEqual(
      timelineScroll.contentView.bounds.minY, labelScroll.contentView.bounds.minY, accuracy: 1)
    try await capture(window, name: rtl ? "Scrolled Arabic guide" : "Large native guide")
    labels.scrollRowToVisible(0)
    try await waitFor("Channel and programme scrolling return together") {
      timelineScroll.contentView.bounds.minY == labelScroll.contentView.bounds.minY
        && timelineScroll.contentView.bounds.minY < 100
    }
  }

  func testLeavingProgrammeCancelsPendingArchiveProbe() async throws {
    let panel = MockPanelServer(stream: .init(transportStream: Data()), script: .silent)
    try panel.start()
    defer { panel.stop() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let logo = NSImage(size: NSSize(width: 60, height: 36), flipped: false) { rect in
      NSColor.systemTeal.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
      NSAttributedString(string: "TV", attributes: [.font: NSFont.boldSystemFont(ofSize: 20),
        .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 16, y: 5))
      return true
    }
    try XCTUnwrap(logo.tiffRepresentation).write(to: directory.appendingPathComponent("evening.tiff"))
    let artworkServer = LocalHTTPServer(directory: directory)
    try artworkServer.start()
    defer { artworkServer.stop() }
    let source = Playlist(name: "Evening TV", serverURL: "http://127.0.0.1:\(panel.port)",
      username: "viewer", password: "local", serverTimezone: "UTC")
    let db = AppDatabase.shared
    let now = Date()
    let start = Int64(now.timeIntervalSince1970) + 4
    let stop = start + 4
    try db.writeSync { db in
      try source.insert(db)
      try DBLiveStream(streamId: 9, name: "Evening TV", streamIcon: "http://127.0.0.1:\(artworkServer.port)/evening.tiff",
                       epgChannelId: "evening", playlistId: source.id, tvArchive: 1, tvArchiveDuration: 0).insert(db)
      try DBEPGProgramme(playlistId: source.id, channelKey: "evening", startTs: start, stopTs: stop,
                         title: "Evening highlights").insert(db)
      try DBEPGSource(playlistId: source.id, sourceType: EPGSourceType.xtreamXMLTV.rawValue,
                      lastSuccessAt: now, programmeCount: 1, channelCount: 1).insert(db)
    }
    defer {
      EPGStore.shared.setActivePlaylist(nil)
      PlaylistContentStore.shared.unload()
      _ = try? db.writeSync { try source.delete($0) }
    }
    let player = DesktopPlayback(database: db)
    let window = window(for: NavigationStack { MacGuide(source: source, settings: {}) }
      .modifier(MacPlaybackPresentation(playback: player)).environment(\.appDatabase, db)
      .environmentObject(player))
    defer { player.close(); window.close() }
    try await waitFor("Archived programme on local guide") { self.named("Evening highlights", window) != nil }
    try await press("Evening highlights", in: window)
    XCTAssertNil(named(L("epg.detail.watch_from_start"), window))
    try await waitFor("Open detail offers start-over when programme begins") {
      self.named(L("epg.detail.watch_from_start"), window) != nil
    }
    XCTAssertNotNil(named(L("epg.detail.live_badge"), window))
    let begins = Date(timeIntervalSince1970: Double(start))
    let ends = Date(timeIntervalSince1970: Double(stop))
    let timing = EPGTimeFormat.day(begins, wide: false) + " · " + EPGTimeFormat.range(begins, ends)
      + " · " + EPGTimeFormat.duration(ends.timeIntervalSince(begins))
    XCTAssertNotNil(named(timing, window))
    try await capture(window, name: "Current programme progress")
    try await press(L("epg.detail.watch_from_start"), in: window)
    try await waitFor("Provider has a pending archive connection") { panel.stats.open == 1 }
    try await waitFor("Start-over disappears when the zero-retention programme ends") {
      self.named(L("epg.detail.watch_from_start"), window) == nil
        && self.named(L("epg.detail.play_catchup"), window) == nil
    }
    try await press(L("epg.guide.title"), in: window)
    try await waitFor("Returning to guide closes archive connection") { panel.stats.open == 0 }
    XCTAssertEqual(panel.stats.admitted, 1)
    XCTAssertNil(player.current)
    XCTAssertNil(window.attachedSheet)
  }

  func testEarlyArchiveHLSDecoderFailureChangesNextProbeOrder() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let server = LocalHTTPServer(directory: dir)
    try server.start()
    defer { server.stop() }
    let manifest = """
      #EXTM3U
      #EXT-X-VERSION:3
      #EXT-X-TARGETDURATION:5
      #EXTINF:5,
      unavailable.ts
      #EXT-X-ENDLIST
      """
    try manifest.write(to: dir.appendingPathComponent("archive.m3u8"), atomically: true, encoding: .utf8)
    let base = "http://127.0.0.1:\(server.port)"
    let source = Playlist(name: "Archive", serverURL: base, timeshiftStyle: "m3u8")
    let database = AppDatabase.empty()
    try database.writeSync { try source.insert($0) }
    let session = DesktopPlayback(database: database)
    defer { session.close() }
    let url = try XCTUnwrap(URL(string: base + "/archive.m3u8"))
    session.start(MediaSelection(url: url, playlistId: source.id, streamId: "5", type: "catchup",
                                 title: "Recap", storesHistory: false))
    try await waitFor("Failed catch-up decoder demotes HLS for next archive", timeout: 18) {
      (try? database.reader.read { try Playlist.fetchOne($0, key: source.id)?.timeshiftStyle }) == "path-no-m3u8"
    }
    let stored = await CatchupURLResolver.storedStyle(for: source, in: database)
    let order = TimeshiftStyleCache.probeOrder(for: TimeshiftStyleCache(storedValue: stored))
    XCTAssertEqual(order.first, .path)
    XCTAssertEqual(order.last, .hls)
  }

  func testArchiveProviderFailureRetriesFromProgrammeDetailAndDecodesPHPStream() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let streaming = root.appendingPathComponent("streaming")
    try FileManager.default.createDirectory(at: streaming, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let http = LocalHTTPServer(directory: root)
    try http.start()
    defer { http.stop() }
    let base = "http://127.0.0.1:\(http.port)"
    let source = Playlist(name: "Coastal TV", serverURL: base, username: "viewer", password: "local",
                          serverTimezone: "UTC")
    let start = Date().addingTimeInterval(-1200)
    let stop = start.addingTimeInterval(3600)
    let date = DateFormatter()
    date.locale = Locale(identifier: "en_US_POSIX")
    date.timeZone = TimeZone(secondsFromGMT: 0)
    date.dateFormat = "yyyyMMddHHmmss Z"
    let xml = """
      <tv><channel id="coast"><display-name>Coast One</display-name></channel>
      <programme start="\(date.string(from: start))" stop="\(date.string(from: stop))" channel="coast">
      <title>Coastal report</title><desc>Morning edition</desc></programme></tv>
      """
    try xml.write(to: root.appendingPathComponent("xmltv.php"), atomically: true, encoding: .utf8)
    let db = AppDatabase.shared
    try db.writeSync { db in
      try source.insert(db)
      try DBLiveStream(streamId: 17, name: "Coast One", epgChannelId: "coast",
                       playlistId: source.id, tvArchive: 1, tvArchiveDuration: 1).insert(db)
    }
    let store = EPGStore.shared
    defer {
      store.setActivePlaylist(nil)
      PlaylistContentStore.shared.unload()
      _ = try? db.writeSync { try source.delete($0) }
    }
    store.setActivePlaylist(source)
    await store.forceRefresh(playlist: source)
    let programmes = try await store.programmes(playlistId: source.id, channelKey: "coast", from: start, to: stop)
    XCTAssertEqual(programmes.map(\.title), ["Coastal report"])
    let olderProgramme = Date().addingTimeInterval(-47 * 3600)
    try db.writeSync { db in
      for (title, starts) in [("Archived bulletin", start.addingTimeInterval(-7200)), ("Expired bulletin", olderProgramme)] {
        try DBEPGProgramme(playlistId: source.id, channelKey: "coast", startTs: Int64(starts.timeIntervalSince1970),
          stopTs: Int64(starts.timeIntervalSince1970) + 600, title: title).insert(db)
      }
    }
    let player = DesktopPlayback(database: db)
    let window = window(for: NavigationStack { MacGuide(source: source, settings: {}) }
      .modifier(MacPlaybackPresentation(playback: player)).environment(\.appDatabase, db)
      .environmentObject(player))
    defer { player.close(); window.close() }
    try await waitFor("Archive programme appears in guide") { self.named("Coastal report", window) != nil }
    try await press("Coast One", in: window)
    try await waitFor("Archived and expired programmes are distinguished in the schedule") {
      guard let archived = self.named("Archived bulletin", window), let expired = self.named("Expired bulletin", window),
        let available = self.attribute(archived, "accessibilityValue") as? String,
        let unavailable = self.attribute(expired, "accessibilityValue") as? String else { return false }
      return available.contains(L("epg.catchup.available")) && !unavailable.contains(L("epg.catchup.available"))
    }
    try await capture(window, name: "Archive availability in channel schedule")
    try await press("Coastal report", in: window)
    try await press(L("epg.detail.watch_from_start"), in: window)
    try await waitFor("Missing archive offers an inline retry") {
      self.named(L("common.try_again"), window) != nil &&
        self.named(NetworkErrorText.describe(CatchupURLError.notAvailable), window) != nil
    }
    XCTAssertNil(window.attachedSheet)
    XCTAssertNil(player.current)
    try await capture(window, name: "Programme archive unavailable")
    let transport = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    try FileManager.default.copyItem(at: transport, to: streaming.appendingPathComponent("timeshift.php"))
    try await press(L("common.try_again"), in: window)
    try await waitFor("Recovered PHP archive plays as seekable programme", timeout: 14) {
      player.current?.type == "catchup" && player.engine.isPlaybackEstablished && player.canSeek
    }
    let media = try XCTUnwrap(player.current)
    XCTAssertEqual(media.url.path, "/streaming/timeshift.php")
    let query = try XCTUnwrap(URLComponents(url: media.url, resolvingAgainstBaseURL: false)?.queryItems)
    XCTAssertEqual(query.first(where: { $0.name == "stream" })?.value, "17")
    XCTAssertEqual(media.title, "Coastal report")
    XCTAssertFalse(media.storesHistory)
    let style = await CatchupURLResolver.storedStyle(for: source, in: db)
    XCTAssertEqual(style, "php-no-m3u8")
    player.checkpoint()
    let records = try await db.read { try DBWatchHistory.filter(Column("playlistId") == source.id).fetchCount($0) }
    XCTAssertEqual(records, 0)
    try await capture(window, name: "Programme archive playback")
  }

  func testXMLTVGuideToProgrammeAndLivePlayback() async throws {
    try await checkXMLTVGuide(direction: .leftToRight)
  }

  func testArabicXMLTVJumpToNowAndOpenProgramme() async throws {
    try await checkXMLTVGuide(direction: .rightToLeft)
  }

  private func checkXMLTVGuide(direction: LayoutDirection) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let movie = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    try FileManager.default.copyItem(at: movie, to: directory.appendingPathComponent("live.ts"))
    try FileManager.default.copyItem(at: movie, to: directory.appendingPathComponent("second.ts"))
    let http = LocalHTTPServer(directory: directory)
    try http.start()
    defer { http.stop() }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMddHHmmss Z"
    let now = Date()
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
    func programme(_ start: Date, _ title: String) -> String {
      "<programme start=\"" + formatter.string(from: start) + "\" stop=\""
        + formatter.string(from: start.addingTimeInterval(3600)) + "\" channel=\"harbor\"><title>"
        + title + "</title><desc>Harbor dispatches</desc></programme>"
    }
    let xml =
      "<?xml version=\"1.0\"?><tv><channel id=\"harbor\"><display-name>Harbor News</display-name></channel>"
      + programme(now.addingTimeInterval(-600), "Evening bulletin")
      + programme(tomorrow, "Tomorrow bulletin")
      + (1...36).map { programme(tomorrow.addingTimeInterval(Double($0 + 2) * 3600), "Later programme \($0)") }.joined()
      + "</tv>"
    try xml.write(
      to: directory.appendingPathComponent("guide.xml"), atomically: true, encoding: .utf8)
    let url = "http://127.0.0.1:\(http.port)"
    let source = Playlist(
      name: "Guide fixture", serverURL: url + "/channels.m3u", type: .m3u,
      m3uEpgURL: url + "/guide.xml")
    let db = AppDatabase.shared
    try await M3UImporter.replace(
      playlist: source,
      channels: [
        ParsedM3UChannel(
          name: "Harbor News", url: url + "/live.ts", tvgId: "harbor", groupTitle: "News"),
        ParsedM3UChannel(name: "Weather", url: url + "/second.ts", tvgId: "weather", groupTitle: "News")
      ] + (direction == .rightToLeft ? [ParsedM3UChannel(name: "Sports One", url: url + "/sport.ts",
        tvgId: "sports", groupTitle: "Sports")] : []), epgURL: source.m3uEpgURL, in: db)
    let store = EPGStore.shared
    defer {
      store.setActivePlaylist(nil)
      M3UContentStore.shared.unload()
      _ = try? db.writeSync { try source.delete($0) }
    }
    store.setActivePlaylist(source)
    await store.forceRefresh(playlist: source)
    let parsed = try await store.programmes(
      playlistId: source.id, channelKey: "harbor", from: now.addingTimeInterval(-3600),
      to: tomorrow.addingTimeInterval(7200))
    XCTAssertEqual(parsed.map(\.title), ["Evening bulletin", "Tomorrow bulletin"])
    let player = DesktopPlayback(database: db)
    let window = window(
      for: NavigationStack {
        MacGuide(source: source, settings: {}).navigationTitle(L("epg.guide.title"))
      }.modifier(MacPlaybackPresentation(playback: player)).environment(\.appDatabase, db).environmentObject(player)
        .environment(\.layoutDirection, direction)
        .environment(\.locale, direction == .rightToLeft ? Locale(identifier: "ar") : AppLocale.current))
    defer {
      player.close()
      window.close()
    }
    print("GUIDE_CHECK parsed", parsed.map(\.title))
    try await waitFor("Programme in guide grid") { self.named("Evening bulletin", window) != nil }
    if direction == .rightToLeft {
      let timeline = try XCTUnwrap(accessible(window).compactMap { $0 as? NSTableView }.first {
        ($0.tableColumns.first?.width ?? 0) > 1000
      })
      let scroll = try XCTUnwrap(timeline.enclosingScrollView)
      scroll.contentView.scroll(to: .zero)
      scroll.reflectScrolledClipView(scroll.contentView)
      try await press(L("epg.jump_to_now"), in: window)
      let metrics = EPGGuideMetrics.guide(regularWidth: true)
      let elapsed = Date().timeIntervalSince(Calendar.current.startOfDay(for: .now))
      let fromStart = CGFloat(max(0, Int(elapsed / 3600) - 1)) * metrics.hourWidth
      try await waitFor("Jump to now aligns the RTL time axis") {
        let maxX = max(0, timeline.tableColumns[0].width - scroll.contentView.bounds.width)
        return abs(scroll.contentView.bounds.minX - max(0, maxX - fromStart)) < 1
      }
      let news = try XCTUnwrap(named("News", window))
      XCTAssertEqual(attribute(news, "accessibilityValue") as? String, L("epg.categories.expanded_a11y"))
      try await press("News", in: window)
      try await waitFor("Collapsed category exposes its state and removes programmes") {
        self.named(L("epg.categories.collapsed_a11y"), window) != nil && self.named("Evening bulletin", window) == nil
      }
      try await press("News", in: window)
      try await waitFor("Expanded category restores the programme's accessible time and channel") {
        guard let button = self.named("Evening bulletin", window),
              let value = self.attribute(button, "accessibilityValue") as? String else { return false }
        return value.contains("Harbor News") && value.contains(L("epg.now"))
      }
      try await capture(window, name: "Arabic XMLTV jump to now")
    }
    print("GUIDE_CHECK grid")
    try await capture(window, name: "Programme guide")
    try await press("Harbor News", in: window)
    try await waitFor("Channel schedule loads current and next-day programmes") {
      self.named("Evening bulletin", window) != nil && self.named("Tomorrow bulletin", window) != nil
    }
    XCTAssertNotNil(named(L("epg.day.today"), window))
    XCTAssertNotNil(named(L("epg.day.tomorrow"), window))
    let scheduleTable = try XCTUnwrap(accessible(window).compactMap { $0 as? NSTableView }.first)
    let scroll = try XCTUnwrap(scheduleTable.enclosingScrollView)
    scheduleTable.scrollRowToVisible(scheduleTable.numberOfRows - 1)
    try await waitFor("Schedule scrolls away from the current programme") {
      scroll.contentView.bounds.minY > 100
    }
    let beforeJump = scroll.contentView.bounds.minY
    try await press(L("epg.jump_to_now"), in: window)
    try await waitFor("Jump returns to the current programme") {
      scroll.contentView.bounds.minY < beforeJump - 100 && self.named("Evening bulletin", window) != nil
    }
    try await waitFor("Current schedule row announces its on-air status") {
      self.accessible(window).contains { element in
        self.attribute(element, "accessibilityLabel") as? String == "Evening bulletin"
          && (self.attribute(element, "accessibilityValue") as? String)?.contains(L("epg.now")) == true
      }
    }
    let scheduleRow = try XCTUnwrap(named("Tomorrow bulletin", window))
    let expectedLocale = direction == .rightToLeft ? Locale(identifier: "ar") : AppLocale.current
    let expectedStart = parsed[1].start.formatted(.dateTime.weekday().hour().minute().locale(expectedLocale))
    XCTAssertEqual(attribute(scheduleRow, "accessibilityValue") as? String, expectedStart + ", Harbor dispatches")
    try await capture(window, name: "Channel programme list")
    func searchField(_ view: NSView) -> NSSearchField? {
      if let field = view as? NSSearchField { return field }
      return view.subviews.lazy.compactMap { searchField($0) }.first
    }
    let search = try XCTUnwrap(window.contentView?.superview.flatMap(searchField))
    window.makeFirstResponder(search)
    let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
    editor.insertText("evening", replacementRange: editor.selectedRange())
    await Task.yield()
    editor.selectAll(nil)
    editor.insertText("tomorrow", replacementRange: editor.selectedRange())
    try await waitFor("Latest channel search replaces the previous query") {
      self.named("Tomorrow bulletin", window) != nil && self.named("Evening bulletin", window) == nil
    }
    XCTAssertNil(named(L("epg.day.today"), window))
    XCTAssertNotNil(named(L("epg.day.tomorrow"), window))
    try db.writeSync { db in
      try db.execute(sql: "UPDATE epgProgramme SET title = ? WHERE playlistId = ? AND title = ?",
        arguments: ["Tomorrow amended", source.id, "Tomorrow bulletin"])
    }
    try await waitFor("Open schedule follows a database correction without refresh") {
      self.named("Tomorrow amended", window) != nil && self.named("Tomorrow bulletin", window) == nil
        && search.stringValue == "tomorrow"
    }
    let additional = programme(tomorrow.addingTimeInterval(7200), "Tomorrow extra")
    try xml.replacingOccurrences(of: "</tv>", with: additional + "</tv>")
      .write(to: directory.appendingPathComponent("guide.xml"), atomically: true, encoding: .utf8)
    try await press(L("epg.refresh"), in: window)
    try await waitFor("Refreshed channel schedule preserves its search and shows the added programme") {
      self.named("Tomorrow extra", window) != nil && self.named("Evening bulletin", window) == nil
        && search.stringValue == "tomorrow"
    }
    try "<tv></tv>".write(to: directory.appendingPathComponent("guide.xml"), atomically: true, encoding: .utf8)
    try await press(L("epg.refresh"), in: window)
    try await waitFor("Failed refresh leaves channel results visible with an error") {
      guard case .failed(let message) = store.refreshState[source.id] else { return false }
      return self.named(message, window) != nil && self.named("Tomorrow extra", window) != nil
        && self.named("Evening bulletin", window) == nil && search.stringValue == "tomorrow"
    }
    editor.selectAll(nil)
    editor.deleteBackward(nil)
    try await waitFor("Clearing schedule search restores programmes") {
      self.named("Evening bulletin", window) != nil
    }
    editor.insertText("tomorrow", replacementRange: editor.selectedRange())
    try await waitFor("Filtered programme ready to open") { self.named("Evening bulletin", window) == nil }
    try await press("Tomorrow bulletin", in: window)
    try await waitFor("Full programme description") { self.named("Harbor dispatches", window) != nil }
    try db.writeSync { db in
      try db.execute(sql: "UPDATE epgProgramme SET desc = ? WHERE playlistId = ? AND title = ?",
        arguments: ["Local schedule correction", source.id, "Tomorrow bulletin"])
    }
    try await waitFor("Open detail follows a database correction without refreshing XMLTV") {
      self.named("Local schedule correction", window) != nil
    }
    let refreshedXML = xml.replacingOccurrences(of: "</tv>", with: additional + "</tv>")
      .replacingOccurrences(of: "Tomorrow bulletin</title><desc>Harbor dispatches",
                            with: "Tomorrow bulletin</title><desc>Updated harbor report")
    try refreshedXML.write(to: directory.appendingPathComponent("guide.xml"), atomically: true, encoding: .utf8)
    try await press(L("epg.refresh"), in: window)
    try await waitFor("Open programme detail displays the corrected description") {
      self.named("Updated harbor report", window) != nil && self.named("Tomorrow bulletin", window) != nil
    }
    try await press("Harbor News", in: window)
    try await waitFor("Detail returns to the filtered channel schedule") {
      window.contentView?.superview.flatMap(searchField)?.stringValue == "tomorrow"
        && self.named("Tomorrow bulletin", window) != nil && self.named("Evening bulletin", window) == nil
    }
    func returnToGrid() async throws {
      let back = try XCTUnwrap(accessible(window).first {
        self.attribute($0, "accessibilityIdentifier") as? String == "guide.schedule.back"
      })
      back.perform(NSSelectorFromString("accessibilityPerformPress"))
      try await waitFor("Returning to grid preserves selected day and grid search") {
        window.contentView?.superview.flatMap(searchField)?.stringValue == ""
          && self.named("Evening bulletin", window) != nil && self.named("Tomorrow bulletin", window) == nil
      }
    }
    try await returnToGrid()
    try await press("Weather", in: window)
    try await waitFor("Another channel starts with its own empty schedule and search") {
      window.contentView?.superview.flatMap(searchField)?.stringValue == ""
        && self.named(L("epg.no_data.channel"), window) != nil
    }
    try await returnToGrid()
    try await press("Evening bulletin", in: window)
    try await waitFor("Programme opens again from preserved grid") {
      self.named("Harbor dispatches", window) != nil
    }
    print("GUIDE_CHECK programme")
    try await press(L("epg.detail.play_channel"), in: window)
    try await waitFor("Guide opens the selected live channel", timeout: 12) {
      player.current?.title == "Harbor News" && player.engine.isPlaybackEstablished
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    defaults.set(true, forKey: "mac.posterPresentation")
    let browser = self.window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(player).environmentObject(LocalizationManager.shared).defaultAppStorage(defaults))
    defer { browser.close() }
    let announced = L("epg.a11y.now_playing_format", "Evening bulletin")
    try await waitFor("Discover announces the live M3U programme") {
      self.named(announced, browser) != nil
    }
    try await press(ML("see_all"), in: browser)
    try await waitFor("Catalogue card announces the same programme") {
      self.named(announced, browser) != nil
    }
    try await capture(browser, name: "M3U programme cards")
    let nowPlaying = MPNowPlayingInfoCenter.default()
    try await waitFor("Live programme and channel appear in system metadata") {
      let info = nowPlaying.nowPlayingInfo
      return info?[MPMediaItemPropertyTitle] as? String == "Evening bulletin"
        && info?[MPMediaItemPropertyArtist] as? String == "Harbor News"
        && info?[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true
    }
    XCTAssertFalse(MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled)
    let onAir = L("epg.a11y.now_playing_format", "Evening bulletin")
    let next = L("epg.next_format", "\(L("epg.day.tomorrow")) \(EPGTimeFormat.time(tomorrow)) Tomorrow bulletin")
    try await waitFor("Expanded live player shows current and next programme") {
      self.named(onAir, window) != nil && self.named(next, window) != nil
    }
    try await capture(window, name: "Live player programme strip")
    try await press(ML("minimize"), in: window)
    try await waitFor("Mini player shows the channel") {
      !player.expanded && self.accessible(window).contains {
        self.attribute($0, "accessibilityLabel") as? String == "Harbor News"
          && self.attribute($0, "accessibilityValue") as? String == onAir
      }
    }
    try await capture(window, name: "Live mini player programme")
    try await press("Harbor News", in: window)
    try await waitFor("Expanded player restores the next programme") {
      player.expanded && self.named(next, window) != nil
    }
    try await db.write { db in
      try db.execute(sql: "UPDATE epgProgramme SET title=? WHERE playlistId=? AND channelKey=? AND title=?",
                     arguments: ["Special report", source.id, "harbor", "Tomorrow bulletin"])
    }
    let revised = L("epg.next_format", "\(L("epg.day.tomorrow")) \(EPGTimeFormat.time(tomorrow)) Special report")
    try await waitFor("Guide correction updates the live player without retuning") {
      self.named(revised, window) != nil && self.named(next, window) == nil
    }
    try await press(ML("next"), in: window)
    try await waitFor("Tuning an unlisted channel clears both programmes") {
      player.current?.title == "Weather" && self.named(onAir, window) == nil && self.named(revised, window) == nil
    }
    try await press(L("player.a11y.last_channel"), in: window)
    try await waitFor("Recall tunes the last channel and restores its programme") {
      player.current?.title == "Harbor News" && player.lastChannel?.title == "Weather"
        && player.engine.isPlaybackEstablished && self.named(revised, window) != nil
    }
    try await capture(window, name: "Recall previous live channel")
    for type: NSEvent.EventType in [.keyDown, .keyUp] {
      let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: "l", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37))
      window.sendEvent(event)
    }
    try await waitFor("A second recall swaps the two channels") {
      player.current?.title == "Weather" && player.lastChannel?.title == "Harbor News"
        && player.engine.isPlaybackEstablished
    }
    player.close()
    XCTAssertNil(player.lastChannel)
    let model = EPGGuideViewModel(source: .m3u(source))
    await model.load()
    await model.selectDay(tomorrow)
    XCTAssertTrue(
      model.layout(for: "harbor").cells.contains { $0.programme?.title == "Special report" })
  }

  func testCancellingScopedRefreshClosesThePendingRequestAndKeepsCatalogue() async throws {
    let provider = MockPanelServer(stream: .init(transportStream: Data()), script: .waitingCatalogue)
    try provider.start()
    defer { provider.stop() }
    let db = AppDatabase.empty()
    let source = Playlist(name: "Local provider", serverURL: "http://127.0.0.1:\(provider.port)",
                          username: "fixture", epgEnabled: false)
    try db.writeSync { db in
      try source.insert(db)
      try DBLiveStream(streamId: 4, name: "Local news", playlistId: source.id).insert(db)
    }
    let window = window(for: NavigationStack {
      MacCatalogView(source: source, kinds: [.live], title: MediaKind.live.title, search: "",
                     favorites: false, isSearch: false, open: { _, _ in })
    }.environment(\.appDatabase, db).environmentObject(DesktopPlayback(database: db)))
    defer { window.close() }
    try await waitFor("Live catalogue ready") { self.named("Local news", window) != nil }
    try await press(ML("refresh_catalog"), in: window)
    try await waitFor("Provider has pending refresh") { provider.stats.open == 1 }
    try await press(L("common.cancel"), in: window)
    try await waitFor("Pending catalogue connection closes") {
      provider.stats.open == 0 && self.named(L("common.cancel"), window) == nil
    }
    XCTAssertNil(named(L("common.try_again"), window))
    XCTAssertNotNil(named("Local news", window))
  }

  func testScopedCatalogueRefreshRetriesWithoutChangingOtherSections() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = LocalHTTPServer(directory: root)
    try server.start()
    defer { server.stop() }
    let source = Playlist(name: "Provider", serverURL: "http://127.0.0.1:\(server.port)",
                          username: "viewer", password: "test", epgEnabled: false)
    let db = AppDatabase.empty()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(false, forKey: "mac.posterPresentation")
    try db.writeSync { db in
      try source.insert(db)
      try DBLiveStream(streamId: 1, name: "Saved live", playlistId: source.id).insert(db)
      try DBVODStream(streamId: 1, name: "Saved vod", playlistId: source.id).insert(db)
      try DBSeries(seriesId: 1, name: "Saved series", playlistId: source.id).insert(db)
    }
    var expected: [MediaKind: String] = [.live: "Saved live", .vod: "Saved vod", .series: "Saved series"]
    let endpoint = root.appendingPathComponent("player_api.php")
    for kind in [MediaKind.live, .vod, .series] {
      let window = window(for: NavigationStack {
        MacCatalogView(source: source, kinds: [kind], title: kind.title, search: "",
                       favorites: false, isSearch: false, open: { _, _ in })
      }.environment(\.appDatabase, db).environmentObject(DesktopPlayback(database: db))
        .defaultAppStorage(defaults))
      defer { window.close() }
      let old = try XCTUnwrap(expected[kind])
      try await waitFor("Cached catalogue opens") { self.named(old, window) != nil }
      try await press(ML("refresh_catalog"), in: window)
      try await waitFor("Failed scoped refresh keeps items and offers retry") {
        self.named(old, window) != nil && self.named(L("common.try_again"), window) != nil
      }
      if kind == .vod { try await capture(window, name: "Scoped film refresh retry") }
      let title = "Updated " + kind.rawValue
      let record: [String: Any] = ["stream_id": 9, "series_id": 9, "category_id": "local",
                                    "name": title, "category_name": "Provider collection"]
      try JSONSerialization.data(withJSONObject: [record]).write(to: endpoint, options: .atomic)
      try await press(L("common.try_again"), in: window)
      try await waitFor("Only the refreshed catalogue changes") {
        self.named(title, window) != nil && self.named(old, window) == nil &&
          self.named(L("common.try_again"), window) == nil
      }
      expected[kind] = title
      let actual = try await db.read { db in
        try Dictionary(uniqueKeysWithValues: [MediaKind.live, .vod, .series].map { scope in
          (scope, try MacCatalogQuery(playlistID: source.id, kinds: [scope]).fetch(db).map(\.title))
        })
      }
      XCTAssertEqual(actual, expected.mapValues { [$0] })
      try FileManager.default.removeItem(at: endpoint)
    }
  }

  func testLiveTableMatchesProgrammeByChannelIDOrName() async throws {
    let db = AppDatabase.empty()
    let source = Playlist(name: "TV", serverURL: "https://media.invalid")
    try db.writeSync { db in
      try source.insert(db)
      try DBLiveStream(streamId: 1, name: "Channel One", epgChannelId: "station-id", playlistId: source.id).insert(db)
      try DBLiveStream(streamId: 2, name: "Channel Two", playlistId: source.id).insert(db)
    }
    let now = Date()
    func programme(_ key: String, _ title: String) -> EPGNowNext {
      EPGNowNext(now: EPGProgramme(channelKey: key, title: title,
        start: now.addingTimeInterval(-300), stop: now.addingTimeInterval(600)))
    }
    let firstKey = try XCTUnwrap(EPGConstants.normalizeChannelKey("station-id"))
    let secondKey = try XCTUnwrap(EPGConstants.normalizeChannelKey("Channel Two"))
    let index = EPGSnapshot(version: 1, byChannelKey: [
      firstKey: programme(firstKey, "Market report"), secondKey: programme(secondKey, "Coastal weather")])
    let window = window(for: MacCatalogView(source: source, kinds: [.live], title: MediaKind.live.title,
      search: "", favorites: false, isSearch: false, open: { _, _ in })
      .environment(\.appDatabase, db).environment(\.epgSnapshot, index)
      .environmentObject(DesktopPlayback(database: db)))
    defer { window.close() }
    try await waitFor("Native channel table shows both on-air titles") {
      self.named("Market report", window) != nil && self.named("Coastal weather", window) != nil
    }
    try await capture(window, name: "Live table programme titles")
    let snapshot = try await db.read { db in
      try MacCatalogQuery(playlistID: source.id, kinds: [.live]).fetch(db)
    }
    let selected = try XCTUnwrap(snapshot.first { $0.streamKey == "1" })
    let icon = "https://media.invalid/current.png"
    try db.writeSync { db in
      try DBCategory(id: "news", name: "Local news", type: "live", playlistId: source.id).insert(db)
      try db.execute(sql: "UPDATE liveStream SET name = ?, streamIcon = ?, categoryId = 'news' WHERE playlistId = ? AND streamId = 1",
                     arguments: ["Updated station", icon, source.id])
    }
    let media = try await MediaSelection.resolve(selected, in: source, database: db)
    XCTAssertEqual(media.title, "Updated station")
    XCTAssertEqual(media.secondaryTitle, "Local news")
    XCTAssertEqual(media.artwork, icon)
  }

  func testLiveTableLoadsNextPageOnScroll() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Stations", serverURL: "https://fixture.invalid", epgEnabled: false)
    try database.writeSync { db in
      try source.insert(db)
      for id in 1...320 {
        try DBLiveStream(streamId: id, name: "Station \(id)", sortIndex: id, playlistId: source.id)
          .insert(db)
      }
    }
    let view = NavigationStack {
      MacCatalogView(
        source: source, kinds: [.live], title: "Stations", search: "", favorites: false,
        isSearch: false, open: { _, _ in })
    }.environment(\.appDatabase, database).environmentObject(DesktopPlayback(database: database))
    let window = window(for: view)
    defer { window.close() }
    func table(in view: NSView) -> NSTableView? {
      (view as? NSTableView) ?? view.subviews.lazy.compactMap { table(in: $0) }.first
    }
    try await waitFor("First channel page ready") {
      window.contentView.flatMap(table)?.numberOfRows == 100
    }
    let stations = try XCTUnwrap(window.contentView.flatMap(table))
    stations.scrollRowToVisible(99)
    try await waitFor("Scrolling loads next channel page") { stations.numberOfRows == 200 }
    stations.scrollRowToVisible(199)
    try await waitFor("Third page loads") { stations.numberOfRows == 300 }
    stations.scrollRowToVisible(299)
    try await waitFor("Final partial page loads") { stations.numberOfRows == 320 }
    stations.scrollRowToVisible(319)
    try await waitFor("Last station is reachable") { self.named("Station 320", window) != nil }
  }

  func testMetadataCancellationDoesNotOfferRetry() {
    for error: Error in [CancellationError(), URLError(.cancelled),
                         XtreamError.networkError(CancellationError()), XtreamError.networkError(URLError(.cancelled))] {
      XCTAssertNil(MacMediaDetail.metadataFailureMessage(error))
    }
    for error: Error in [XtreamError.networkError(URLError(.timedOut)), XtreamError.serverError("HTTP 503")] {
      XCTAssertEqual(MacMediaDetail.metadataFailureMessage(error), NetworkErrorText.describe(error))
    }
  }

  func testMovieMetadataRetryPreservesFavorite() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = LocalHTTPServer(directory: root)
    try server.start()
    defer { server.stop() }
    let source = Playlist(name: "Films", serverURL: "http://127.0.0.1:\(server.port)", username: "test", epgEnabled: false)
    let db = AppDatabase.empty()
    try db.writeSync { db in
      try source.insert(db)
      try DBVODStream(streamId: 1, name: "Harbor film", streamIcon: source.serverURL + "/poster.jpg", rating: "8", plot: "Saved synopsis", playlistId: source.id).insert(db)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(DesktopPlayback(database: db))
      .defaultAppStorage(defaults))
    defer { window.close() }
    try await waitFor("Discover shows film") { self.named("Harbor film", window) != nil }
    try await press("Harbor film", in: window)
    try await waitFor("Failed request keeps cached film information") {
      self.named("Saved synopsis", window) != nil && self.named(L("common.try_again"), window) != nil
    }
    XCTAssertNotNil(named(ML("enlarge_artwork"), window))
    let rating = try XCTUnwrap(BrowseAccessibility.ratingLabel("8"))
    XCTAssertNotNil(named(rating, window))
    try db.writeSync { db in
      try db.execute(sql: "UPDATE vodStream SET streamIcon = NULL, rating = NULL WHERE playlistId = ? AND streamId = 1", arguments: [source.id])
    }
    try await waitFor("Removed poster cannot reopen the stale artwork") {
      self.named(ML("enlarge_artwork"), window) == nil && self.named(rating, window) == nil
    }
    try await press(ML("favorite"), in: window)
    try await waitFor("Film favorited during provider failure") { self.named(ML("unfavorite"), window) != nil }
    let response = #"{"info":{"plot":"Restored film synopsis"},"movie_data":{"stream_id":1,"name":"Harbor film"}}"#
    try response.write(to: root.appendingPathComponent("player_api.php"), atomically: true, encoding: .utf8)
    try await press(L("common.try_again"), in: window)
    try await waitFor("Retry displays updated synopsis with favorite intact") {
      self.named("Restored film synopsis", window) != nil && self.named(ML("unfavorite"), window) != nil &&
        self.named(L("common.try_again"), window) == nil
    }
    let stored = try await db.read { db in
      try DBVODStream.filter(Column("playlistId") == source.id && Column("streamId") == 1).fetchOne(db)
    }
    XCTAssertEqual(stored?.metadataLoaded, true)
    server.stop()
    try selectSidebarRow(L("history.title"), in: window)
    try await waitFor("Left movie detail") { self.named("Restored film synopsis", window) == nil }
    try selectSidebarRow(ML("discover"), in: window)
    try await waitFor("Cached film in Discover") { self.named("Harbor film", window) != nil }
    try await press("Harbor film", in: window)
    try await waitFor("Reopened offline detail retains synopsis and favorite") {
      self.named("Restored film synopsis", window) != nil && self.named(ML("unfavorite"), window) != nil
    }
    XCTAssertNil(named(L("common.try_again"), window))
  }

  func testSeriesMetadataRetryCachesEpisodesAndRelatedNavigation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let server = LocalHTTPServer(directory: root)
    try server.start()
    defer { server.stop() }
    let source = Playlist(name: "Series", serverURL: "http://127.0.0.1:\(server.port)",
                          username: "fixture", epgEnabled: false)
    let db = AppDatabase.empty()
    try db.writeSync { db in
      try source.insert(db)
      try DBSeries(seriesId: 1, name: "Survey", cover: source.serverURL + "/poster.jpg", plot: "Saved synopsis", rating: "7", categoryId: "documentary",
                   playlistId: source.id).insert(db)
      try DBSeries(seriesId: 2, name: "Coastlines", plot: "Other series synopsis", categoryId: "documentary",
                   sortIndex: 1, seasonsLoaded: true, playlistId: source.id).insert(db)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(DesktopPlayback(database: db))
      .defaultAppStorage(defaults))
    defer { window.close() }
    try await waitFor("Discover shows series") { self.named("Survey", window) != nil }
    try await press("Survey", in: window)
    try await waitFor("Metadata failure retains saved synopsis and retry") {
      self.named("Saved synopsis", window) != nil && self.named(L("common.try_again"), window) != nil
    }
    XCTAssertNil(window.attachedSheet)
    let rating = try XCTUnwrap(BrowseAccessibility.ratingLabel("7"))
    XCTAssertNotNil(named(rating, window))
    XCTAssertNotNil(named(ML("enlarge_artwork"), window))
    let response = #"{"info":{"plot":"Restored synopsis","episode_run_time":"40"},"seasons":[{"season_number":1,"name":"First season"}],"episodes":{"1":[{"id":"ep1","episode_num":1,"title":"First voyage","container_extension":"mkv"}]}}"#
    let endpoint = root.appendingPathComponent("player_api.php")
    try response.write(to: endpoint, atomically: true, encoding: .utf8)
    try await press(L("common.try_again"), in: window)
    try await waitFor("Retry restores series plot and seasons") {
      self.named("Restored synopsis", window) != nil && self.named("First season", window) != nil
    }
    XCTAssertFalse(accessible(window).contains { attribute($0, "accessibilityIdentifier") as? String == "series.seasonPicker" })
    let seasonKey = DBSeason.scopedId(playlistId: source.id, seriesId: 1, seasonNumber: 1)
    let stored = try await db.read { try DBEpisode.filter(Column("seasonId") == seasonKey).fetchCount($0) }
    XCTAssertEqual(stored, 1)
    try db.writeSync { db in
      try db.execute(sql: "UPDATE series SET plot = ?, cover = NULL, rating = NULL, rating5Based = NULL WHERE playlistId = ? AND seriesId = 1",
        arguments: ["Updated synopsis", source.id])
      try db.execute(sql: "UPDATE season SET name = ? WHERE id = ?", arguments: ["Season renamed", seasonKey])
    }
    try await waitFor("Open series reflects corrected plot and selected season title") {
      self.named("Updated synopsis", window) != nil && self.named("Season renamed", window) != nil &&
        self.named(rating, window) == nil && self.named(ML("enlarge_artwork"), window) == nil
    }
    try FileManager.default.removeItem(at: endpoint)
    try await press("Coastlines", in: window)
    try await waitFor("Related series opens from detail") { self.named("Other series synopsis", window) != nil }
    try await press("Survey", in: window)
    try await waitFor("Returning to cached detail works offline") {
      self.named("Updated synopsis", window) != nil && self.named("Season renamed", window) != nil
    }
    try db.writeSync { db in
      _ = try DBSeason.deleteOne(db, key: seasonKey)
    }
    try await waitFor("Removed season disappears while series detail stays open") {
      self.named("Season renamed", window) == nil && self.named("Updated synopsis", window) != nil
        && self.named(L("series.no_seasons_info"), window) != nil
    }
    let replacementKey = DBSeason.scopedId(playlistId: source.id, seriesId: 1, seasonNumber: 2)
    try db.writeSync { db in
      try DBSeason(id: replacementKey, seasonNumber: 2, name: "New season", overview: "  The return voyage.  ", episodeCount: 1, seriesId: 1, playlistId: source.id).insert(db)
    }
    try await waitFor("Empty replacement season explains that it has no episodes") {
      self.named("New season", window) != nil && self.named(L("series.no_episodes_in_season"), window) != nil
        && self.named(L("movie.play"), window) == nil
    }
    try db.writeSync { db in
      try DBEpisode(id: DBEpisode.scopedId(playlistId: source.id, panelEpisodeId: "ep2"), episodeId: "ep2",
        episodeNum: 1, title: "Second voyage", seasonId: replacementKey).insert(db)
    }
    try await waitFor("Replacement season and episode appear without reopening") {
      self.named("New season", window) != nil && self.named("1. Second voyage", window) != nil
        && self.named(L("movie.play"), window) != nil && self.named("The return voyage.", window) != nil && self.named(L("detail.episode_count_plural", 1), window) != nil
        && self.named(L("series.no_episodes_in_season"), window) == nil
    }
    let thirdKey = DBSeason.scopedId(playlistId: source.id, seriesId: 1, seasonNumber: 3)
    try db.writeSync { db in
      try DBSeason(id: thirdKey, seasonNumber: 3, name: "Third season", seriesId: 1, playlistId: source.id).insert(db)
      try DBEpisode(id: DBEpisode.scopedId(playlistId: source.id, panelEpisodeId: "ep3"), episodeId: "ep3",
        episodeNum: 1, title: "Third voyage", seasonId: thirdKey).insert(db)
      try DBWatchHistory(id: "history2", playlistId: source.id, streamId: "ep2", type: "series",
        lastTimeMs: 60_000, durationMs: 600_000, lastWatchedAt: .now, seriesId: "1", title: "Voyage").insert(db)
    }
    try await waitFor("Second season makes the native season picker available") {
      self.accessible(window).contains { self.attribute($0, "accessibilityIdentifier") as? String == "series.seasonPicker" }
    }
    try await waitFor("History reaches the selected season") {
      self.accessible(window).contains { el in
        let label = self.attribute(el, "accessibilityLabel") as? String ?? ""
        return label.contains("Second voyage") && label.contains(L("detail.remaining_format", DetailFormatting.formatMs(540_000)))
      }
    }
    try db.writeSync { db in
      try DBWatchHistory(id: "history3", playlistId: source.id, streamId: "ep3", type: "series",
        lastTimeMs: 60_000, durationMs: 600_000, lastWatchedAt: .now, seriesId: "1", title: "Voyage").insert(db)
    }
    try await waitFor("Season selection follows playback across seasons") {
      self.accessible(window).contains { (self.attribute($0, "accessibilityLabel") as? String)?.contains("1. Third voyage") == true }
    }
    XCTAssertNil(self.named(L("common.try_again"), window))
  }

  func testSeriesHistoryShelfOpensOnlySeriesHistoryAndResumesOfflineEpisode() async throws {
    let database = AppDatabase.shared
    let source = Playlist(name: "Series shelf", serverURL: "https://fixture.invalid", epgEnabled: false)
    defer {
      _ = try? database.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    let stored = DownloadStorage.relativePath(playlistId: source.id, type: "series", streamId: "10", ext: "mkv")
    let clip = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    try FileManager.default.copyItem(at: clip, to: DownloadStorage.ensureParentDirectory(for: stored))
    try database.writeSync { db in
      try source.insert(db)
      try DBSeries(seriesId: 4, name: "Harbor series", cover: "https://fixture.invalid/series.png", seasonsLoaded: true, playlistId: source.id).insert(db)
      let season = DBSeason(id: UUID().uuidString, seasonNumber: 1, seriesId: 4, playlistId: source.id)
      try season.insert(db)
      try DBEpisode(id: UUID().uuidString, episodeId: "10", title: "Updated pilot", containerExtension: "mkv",
        seasonId: season.id).insert(db)
      for (type, title) in [("vod", "Other movie"), ("series", "Harbor pilot")] {
        try DBWatchHistory(id: "\(source.id)_\(type)_10", playlistId: source.id, streamId: "10",
          type: type, lastTimeMs: 6100, durationMs: 100000, lastWatchedAt: .now,
          seriesId: type == "series" ? "4" : nil, title: title, containerExtension: "mp4").insert(db)
      }
      try DBDownloadedItem(id: DownloadManager.idFor(episode: source.id, episodeId: "10"), playlistId: source.id,
        streamId: "10", type: "series", title: "Harbor pilot", remoteURL: "https://fixture.invalid/pilot.mkv",
        localPath: stored, containerExtension: "mkv", status: "completed", seriesId: "4").insert(db)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let player = DesktopPlayback(database: database)
    let window = window(for: SourceLibrary().environment(\.appDatabase, database)
      .environmentObject(LocalizationManager.shared).environmentObject(player).defaultAppStorage(defaults))
    defer { player.close(); window.close() }
    try await waitFor("Series in sidebar") { self.named(L("dashboard.series"), window) != nil }
    try selectSidebarRow(L("dashboard.series"), in: window)
    let seeAll = ML("see_all") + " · " + L("continue_watching.title")
    try await waitFor("Series shelf includes its own episode, without movie history") {
      self.named("Harbor pilot", window) != nil && self.named(seeAll, window) != nil && self.named("Other movie", window) == nil
    }
    try await capture(window, name: "Series continue watching shelf")
    try await press(seeAll, in: window)
    try await waitFor("Scoped history list includes the episode") {
      self.named(L("history.clear.title"), window) != nil && self.named("Harbor pilot", window) != nil &&
        self.named("Other movie", window) == nil
    }
    try await press("Harbor pilot", in: window)
    try await waitFor("Series history resumes local episode at six seconds") {
      player.engine.isPlaybackEstablished && player.position >= 5.5 && player.current?.seriesId == "4"
    }
    XCTAssertEqual(player.current?.secondaryTitle, "Harbor series")
    XCTAssertEqual(player.current?.artwork, "https://fixture.invalid/series.png")
    XCTAssertEqual(player.current?.ext, "mkv")
    XCTAssertTrue(player.current?.title.contains("Updated pilot") == true)
  }

  func testMovieCategoryShelfOpensSearchableCollectionAndPreservesPlaybackScope() async throws {
    let db = AppDatabase.shared
    let source = Playlist(name: "Category movies", serverURL: "https://fixture.invalid", epgEnabled: false)
    let hidden = HiddenCategoryStore.shared
    defer {
      hidden.removeAll(playlistId: source.id)
      _ = try? db.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    let movie = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let path = DownloadStorage.relativePath(playlistId: source.id, type: "vod", streamId: "1", ext: "mkv")
    try FileManager.default.copyItem(at: movie, to: DownloadStorage.ensureParentDirectory(for: path))
    try db.writeSync { db in
      try source.insert(db)
      for (index, group) in ["Cinema", "Serials", "Hidden", "Empty"].enumerated() {
        try DBCategory(id: group, name: group, type: "vod", sortIndex: index, playlistId: source.id).insert(db)
      }
      for id in 1...125 {
        try DBVODStream(streamId: id, name: "Feature \(id)", categoryId: "Cinema", containerExtension: "mkv",
          plot: "Edition \(id)", metadataLoaded: true, sortIndex: id, playlistId: source.id).insert(db)
      }
      for (id, group) in [(126, "Serials"), (127, "Hidden"), (128, "Removed")] {
        try DBVODStream(streamId: id, name: "Outside \(id)", categoryId: group, playlistId: source.id).insert(db)
      }
      try DBDownloadedItem(id: DownloadManager.idFor(vod: source.id, streamId: 1), playlistId: source.id,
        streamId: "1", type: "vod", title: "Feature 1", remoteURL: "https://fixture.invalid/movie.mkv",
        localPath: path, containerExtension: "mkv", status: "completed").insert(db)
    }
    hidden.setHidden(true, playlistId: source.id, type: "vod", categoryId: "Hidden")
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let player = DesktopPlayback(database: db)
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(player).defaultAppStorage(defaults))
    defer { player.close(); window.close() }
    try await waitFor("Movies in sidebar") { self.named(L("dashboard.movies"), window) != nil }
    try selectSidebarRow(L("dashboard.movies"), in: window)
    let more = ML("see_all") + " · Cinema"
    let first = BrowseAccessibility.cardLabel(title: "Feature 1", rating: nil, category: "Cinema")
    try await waitFor("Category preview shows movie") { self.named(more, window) != nil && self.named(first, window) != nil }
    XCTAssertNil(named(ML("see_all") + " · Hidden", window))
    try await capture(window, name: "Movie category shelves")
    try await press(more, in: window)
    try await waitFor("Whole category opens") { self.named(more, window) == nil && self.named(first, window) != nil }
    func field(_ view: NSView) -> NSSearchField? {
      if let search = view as? NSSearchField { return search }
      return view.subviews.lazy.compactMap { field($0) }.first
    }
    try await waitFor("Category search is available") { window.contentView?.superview.flatMap(field) != nil }
    let search = try XCTUnwrap(window.contentView?.superview.flatMap(field))
    window.makeFirstResponder(search)
    let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
    editor.insertText("Feature 125", replacementRange: editor.selectedRange())
    let last = BrowseAccessibility.cardLabel(title: "Feature 125", rating: nil, category: "Cinema")
    try await waitFor("Category search finds the 125th film") { self.named(last, window) != nil && self.named(first, window) == nil }
    try await capture(window, name: "Search within movie category")
    editor.selectAll(nil)
    editor.deleteBackward(nil)
    try await waitFor("Clearing category search restores first film") { self.named(first, window) != nil }
    try await press(first, in: window)
    try await waitFor("Movie details from category") { self.named("Edition 1", window) != nil }
    try await press(L("movie.play"), in: window)
    try await waitFor("Selected category is the full playback queue") {
      player.engine.isPlaybackEstablished && player.queue?.items.count == 125 && player.current?.streamId == "1"
    }
    XCTAssertEqual(player.queue?.items.map(\.id), (1...125).map(String.init))
  }

  func testFeaturedPagingWaitsSevenSecondsAndRespectsInactivityAndAccessibility() async throws {
    for (visible, hover, reduced, voiceOver, phase) in [
      (false, false, false, false, ScenePhase.active), (true, true, false, false, .active),
      (true, false, true, false, .active), (true, false, false, true, .active),
      (true, false, false, false, .background)
    ] {
      XCTAssertFalse(MacFeaturedCarousel.allowsAutomaticPaging(visible: visible, hovered: hover,
        reduceMotion: reduced, voiceOver: voiceOver, phase: phase))
    }
    let db = AppDatabase.empty()
    let source = Playlist(name: "Featured timer", serverURL: "https://fixture.invalid", epgEnabled: false)
    let query = MacCatalogQuery(playlistID: source.id, kinds: [.vod], order: .recent)
    let items = try db.writeSync { db in
      try source.insert(db)
      for id in 1...2 {
        try DBVODStream(streamId: id, name: "Page \(id)", metadataLoaded: true, added: String(id), playlistId: source.id).insert(db)
      }
      return try query.fetch(db)
    }
    func makeWindow(_ phase: ScenePhase) -> NSWindow {
      // Configure the window before presenting it. Disabling mouse events after
      // presentation can leave a hover already delivered to the carousel active.
      let testWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1140, height: 738),
                                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      testWindow.ignoresMouseEvents = true
      return window(for: ScrollView {
        MacFeaturedCarousel(source: source, items: items, query: query, open: { _, _ in })
      }.environment(\.appDatabase, db).environment(\.scenePhase, phase), in: testWindow)
    }
    let inactive = makeWindow(.inactive), active = makeWindow(.active)
    defer { active.close(); inactive.close() }
    try await waitFor("Initial featured pages") { self.named("Page 2", active) != nil && self.named("Page 2", inactive) != nil }
    try await Task.sleep(for: .seconds(1))
    XCTAssertNotNil(named("Page 2", active))
    try await waitFor("Visible active carousel automatically advances", timeout: 9) { self.named("Page 1", active) != nil }
    XCTAssertNotNil(named("Page 2", inactive))
  }

  func testFeaturedSeriesLoadsProviderArtworkAndOpensDetails() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let server = LocalHTTPServer(directory: dir)
    try server.start()
    defer { server.stop() }
    let base = "http://127.0.0.1:\(server.port)"
    let image = NSImage(size: NSSize(width: 800, height: 240), flipped: false) { rect in
      NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 45)
      return true
    }
    try XCTUnwrap(image.tiffRepresentation).write(to: dir.appendingPathComponent("wide.tiff"))
    let json = #"{"info":{"name":"Harbor","plot":"A coastal drama","genre":"Drama","releaseDate":"2024-03-12","backdrop_path":["\#(base)/wide.tiff"]},"episodes":{},"seasons":[]}"#
    try json.write(to: dir.appendingPathComponent("player_api.php"), atomically: true, encoding: .utf8)
    let source = Playlist(name: "Featured", serverURL: base, epgEnabled: false)
    let db = AppDatabase.empty()
    try db.writeSync {
      try source.insert($0)
      try DBCategory(id: "drama", name: "Drama", type: "series", playlistId: source.id).insert($0)
      try DBSeries(seriesId: 1, name: "Harbor", lastModified: "123", categoryId: "drama", playlistId: source.id).insert($0)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(DesktopPlayback(database: db)).environmentObject(LocalizationManager.shared).defaultAppStorage(defaults))
    defer { window.close() }
    try await waitFor("Series sidebar ready") { self.named(L("dashboard.series"), window) != nil }
    try selectSidebarRow(L("dashboard.series"), in: window)
    try await waitFor("Provider metadata stored and series still featured") {
      (try? db.writeSync { try DBSeries.fetchOne($0)?.backdropPath }) == base + "/wide.tiff"
        && self.named("Harbor", window) != nil
    }
    try await waitFor("Featured series exposes provider metadata") { self.named("2024 · Drama", window) != nil }
    try await capture(window, name: "Featured series backdrop")
    try await press("Harbor", in: window)
    try await waitFor("Featured series opens its synopsis") { self.named("A coastal drama", window) != nil }
  }

  func testSeriesTableShowsRecentCollectionOnlyWhenUsableDatesArrive() async throws {
    let source = Playlist(name: "Series provider", serverURL: "https://fixture.invalid", epgEnabled: false)
    let db = AppDatabase.empty()
    try db.writeSync {
      try source.insert($0)
      try DBCategory(id: "drama", name: "Drama", type: "series", playlistId: source.id).insert($0)
      try DBSeries(seriesId: 1, name: "Northern shore", plot: "A coastal drama", lastModified: "invalid",
        categoryId: "drama", seasonsLoaded: true, playlistId: source.id).insert($0)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    defaults.set(false, forKey: "mac.posterPresentation")
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(DesktopPlayback(database: db)).environmentObject(LocalizationManager.shared)
      .defaultAppStorage(defaults))
    defer { window.close() }
    try await waitFor("Series library available") { self.named(L("dashboard.series"), window) != nil }
    try selectSidebarRow(L("dashboard.series"), in: window)
    let link = ML("see_all") + " · " + L("recently_added.title")
    try await waitFor("Undated series remains in the normal table") { self.named("Northern shore", window) != nil }
    XCTAssertNil(named(link, window))
    try await db.write { try $0.execute(sql: "UPDATE series SET lastModified='1700000000' WHERE playlistId=?",
                                         arguments: [source.id]) }
    try await waitFor("Provider update adds the collection to the table") { self.named(link, window) != nil }
    try await press(link, in: window)
    try await waitFor("Full collection keeps the table presentation") {
      self.named("Northern shore", window) != nil && self.named(link, window) == nil &&
        self.accessible(window).compactMap { $0 as? NSTableView }.contains { $0.tableColumns.count == 3 && $0.numberOfRows == 1 }
    }
    try await capture(window, name: "Recently added series table")
    try await db.write { try $0.execute(sql: "UPDATE series SET lastModified=NULL WHERE playlistId=?", arguments: [source.id]) }
    try await waitFor("Collection removes series whose provider no longer supplies a date") {
      self.named("Northern shore", window) == nil && self.named(L("favorites.empty.no_result.title"), window) != nil
    }
  }

  func testRecentlyAddedOpensDatedMovieDetailAndPlaysTheTwentyVisibleTitles() async throws {
    try await checkRecentMovieQueue(fromFeaturedCard: false)
  }

  func testFeaturedMovieUsesOnlyTheFiveFeaturedTitles() async throws {
    try await checkRecentMovieQueue(fromFeaturedCard: true)
  }

  private func checkRecentMovieQueue(fromFeaturedCard: Bool) async throws {
    let db = AppDatabase.shared
    let source = Playlist(name: "Recent movies", serverURL: "https://fixture.invalid", epgEnabled: false)
    defer {
      _ = try? db.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    try db.writeSync { db in
      try source.insert(db)
      try DBCategory(id: "cinema", name: "Cinema", type: "vod", playlistId: source.id).insert(db)
      for id in 1...25 {
        try DBVODStream(streamId: id, name: "Movie \(id)", categoryId: "cinema", containerExtension: "mkv",
          plot: "Film edition \(id)", metadataLoaded: true, added: String(id), sortIndex: id, playlistId: source.id).insert(db)
      }
      try DBVODStream(streamId: 26, name: "Undated", categoryId: "cinema", playlistId: source.id).insert(db)
      let path = DownloadStorage.relativePath(playlistId: source.id, type: "vod", streamId: "25", ext: "mkv")
      try FileManager.default.copyItem(at: fixture, to: DownloadStorage.ensureParentDirectory(for: path))
      try DBDownloadedItem(id: DownloadManager.idFor(vod: source.id, streamId: 25), playlistId: source.id,
        streamId: "25", type: "vod", title: "Movie 25", remoteURL: "https://fixture.invalid/movie.mkv",
        localPath: path, containerExtension: "mkv", status: "completed").insert(db)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let player = DesktopPlayback(database: db)
    let window = window(for: SourceLibrary().environment(\.appDatabase, db).environmentObject(player)
      .environmentObject(LocalizationManager.shared).defaultAppStorage(defaults))
    defer { player.close(); window.close() }
    try await waitFor("Movies available in sidebar") { self.named(L("dashboard.movies"), window) != nil }
    try selectSidebarRow(L("dashboard.movies"), in: window)
    let allRecent = ML("see_all") + " · " + L("recently_added.title")
    try await waitFor("Recently added shelf ready") { self.named(allRecent, window) != nil }
    try await waitFor("Newest featured film") { self.named("Movie 25", window) != nil }
    try await press(ML("next"), in: window)
    try await waitFor("Next featured film") { self.named("Movie 24", window) != nil }
    try await press(ML("previous"), in: window)
    try await waitFor("Previous featured film") { self.named("Movie 25", window) != nil }
    try await capture(window, name: "Recently added movie shelf")
    if fromFeaturedCard {
      try await press("Movie 25", in: window)
    } else {
      try await press(ML("previous"), in: window)
      let collection = try XCTUnwrap(accessible(window).first {
        attribute($0, "accessibilityIdentifier") as? String == "featured.collection"
      })
      collection.perform(NSSelectorFromString("accessibilityPerformPress"))
      let newest = BrowseAccessibility.cardLabel(title: "Movie 25", rating: nil, category: "Cinema")
      try await waitFor("Dated collection opens without ordinary catalogue controls") {
        self.named(newest, window) != nil && self.named(allRecent, window) == nil &&
          self.named(L("category_picker.title"), window) == nil
      }
      try await capture(window, name: "Recently added movie collection")
      try await press(newest, in: window)
    }
    try await waitFor("Newest movie opens its normal detail") { self.named("Film edition 25", window) != nil }
    try await press(L("movie.play"), in: window)
    let expected = fromFeaturedCard ? 5 : 20
    try await waitFor("Movie plays with the queue of its originating page") {
      player.engine.isPlaybackEstablished && player.current?.streamId == "25" && player.queue?.items.count == expected
    }
    XCTAssertEqual(player.queue?.items.map(\.id), ((26 - expected)...25).reversed().map(String.init))
  }

  func testRelatedMoviesOpenDetailAndUseTheirShelfAsThePlaybackQueue() async throws {
    let db = AppDatabase.shared
    let source = Playlist(name: "Cinema", serverURL: "https://fixture.invalid", epgEnabled: false)
    defer {
      _ = try? db.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    try db.writeSync { db in
      try source.insert(db)
      for id in 0...24 {
        try DBVODStream(streamId: id + 1, name: String(format: "Tide %02d", id),
          categoryId: "coast", rating: id == 1 ? "8.6" : nil, containerExtension: "mkv", plot: "Edition \(id)", metadataLoaded: true,
          sortIndex: id, playlistId: source.id).insert(db)
      }
      try DBVODStream(streamId: 99, name: "Elsewhere", categoryId: "elsewhere",
        metadataLoaded: true, playlistId: source.id).insert(db)
      let path = DownloadStorage.relativePath(playlistId: source.id, type: "vod", streamId: "2", ext: "mkv")
      try FileManager.default.copyItem(at: fixture, to: DownloadStorage.ensureParentDirectory(for: path))
      try DBDownloadedItem(id: DownloadManager.idFor(vod: source.id, streamId: 2), playlistId: source.id,
        streamId: "2", type: "vod", title: "Tide 01", remoteURL: "https://fixture.invalid/movie.mkv",
        localPath: path, containerExtension: "mkv", status: "completed").insert(db)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    let player = DesktopPlayback(database: db)
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(player).defaultAppStorage(defaults))
    defer { player.close(); window.close() }
    try await waitFor("Discover source movie") { self.named("Tide 00", window) != nil }
    try await press("Tide 00", in: window)
    try await waitFor("Related shelf opens on current movie") {
      self.named("Edition 0", window) != nil && self.named("Tide 01", window) != nil
    }
    let relatedFilm = try XCTUnwrap(named("Tide 01", window))
    XCTAssertEqual(attribute(relatedFilm, "accessibilityValue") as? String,
      BrowseAccessibility.ratingLabel(ContentRating.displayText("8.6")))
    try await capture(window, name: "Related films shelf")
    try db.writeSync { db in
      try db.execute(sql: "UPDATE vodStream SET rating = ? WHERE playlistId = ? AND streamId = 2",
        arguments: ["7.2", source.id])
    }
    let revisedRating = BrowseAccessibility.ratingLabel(ContentRating.displayText("7.2"))
    try await waitFor("Related card updates its rating while the detail stays open") {
      guard let card = self.named("Tide 01", window) else { return false }
      return self.attribute(card, "accessibilityValue") as? String == revisedRating
    }
    try db.writeSync { db in
      try db.execute(sql: "UPDATE vodStream SET rating = NULL WHERE playlistId = ? AND streamId = 2",
        arguments: [source.id])
    }
    try await waitFor("Related card clears the removed rating") {
      guard let card = self.named("Tide 01", window) else { return false }
      return (self.attribute(card, "accessibilityValue") as? String ?? "").isEmpty
    }
    try await press("Tide 01", in: window)
    try await waitFor("Native navigation opens related detail") { self.named("Edition 1", window) != nil }
    let revisedTitle = "Tide restored"
    let revisedCover = "http://127.0.0.1:1/tide.jpg"
    try db.writeSync { db in
      try db.execute(sql: "UPDATE vodStream SET name = ?, streamIcon = ? WHERE playlistId = ? AND streamId = 2",
        arguments: [revisedTitle, revisedCover, source.id])
    }
    try await waitFor("Movie detail displays revised title") { self.named(revisedTitle, window) != nil }
    try await press(L("movie.play"), in: window)
    try await waitFor("Related film decodes with related shelf queue") {
      player.engine.isPlaybackEstablished && player.current?.streamId == "2" && player.queue?.items.count == 20
    }
    XCTAssertEqual(player.current?.title, revisedTitle)
    XCTAssertEqual(player.current?.artwork, revisedCover)
    XCTAssertEqual(player.queue?.items.map(\.id), (2...21).map(String.init))
    XCTAssertEqual(player.queueIndex, 0)
    let commands = MPRemoteCommandCenter.shared()
    try await waitFor("Movie queue keeps system skip buttons") {
      commands.skipForwardCommand.isEnabled && commands.skipBackwardCommand.isEnabled
        && !commands.nextTrackCommand.isEnabled && !commands.previousTrackCommand.isEnabled
    }
    XCTAssertEqual(player.systemPlayback.perform(.step(1)), .noSuchContent)
    XCTAssertEqual(player.systemPlayback.perform(.pause), .success)
    try await waitFor("Movie paused for skip") { player.isPaused }
    let position = player.position
    XCTAssertEqual(player.systemPlayback.perform(.skip(2)), .success)
    try await waitFor("Remote skip moves within the same movie") {
      player.current?.streamId == "2" && abs(player.position - position - 2) < 0.8
    }
  }

  func testCatalogPosterCanBeReadFromDiskAfterLeavingTheGrid() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let server = LocalHTTPServer(directory: dir)
    try server.start()
    defer { server.stop() }
    let name = UUID().uuidString + ".tiff"
    let art = NSImage(size: NSSize(width: 900, height: 1350), flipped: false) { rect in
      NSColor.systemTeal.setFill()
      rect.fill()
      return true
    }
    try XCTUnwrap(art.tiffRepresentation).write(to: dir.appendingPathComponent(name))
    let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/" + name))
    let db = AppDatabase.empty()
    let source = Playlist(name: "Posters", serverURL: "https://fixture.invalid")
    let item = try db.writeSync { db in
      try source.insert(db)
      try DBVODStream(streamId: 1, name: "Poster", streamIcon: url.absoluteString, playlistId: source.id).insert(db)
      return try XCTUnwrap(MacCatalogQuery(playlistID: source.id, kinds: [.vod]).fetch(db).first)
    }
    let window = window(for: CatalogArtwork(item: item, poster: true).frame(width: 128))
    defer { window.close() }
    let request = CachedImage.request(url: url, width: 160, height: 240, contentMode: .fill, loadProfile: .grid)
    let pipeline = ImagePipeline.shared
    try await waitFor("Rendered poster thumbnail reaches disk") { pipeline.cache.containsData(for: request) }
    pipeline.cache.removeCachedImage(for: request, caches: .memory)
    let result = try await pipeline.imageTask(with: request).response
    XCTAssertEqual(result.cacheType, .disk)
  }

  func testDetailPosterOpensInWorkspaceZoomsAndReturnsToMovie() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    func artwork(_ size: NSSize) throws -> Data {
      let picture = NSImage(size: size, flipped: false) { rect in
        NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 80)
        let circle = NSRect(x: rect.width * 0.2, y: rect.height * 0.36,
                            width: rect.width * 0.6, height: rect.width * 0.6)
        NSColor.white.withAlphaComponent(0.65).setFill()
        NSBezierPath(ovalIn: circle).fill()
        ("TIDELINE" as NSString).draw(at: CGPoint(x: 16, y: 22), withAttributes: [
          .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white])
        return true
      }
      return try XCTUnwrap(picture.tiffRepresentation)
    }
    let server = LocalHTTPServer(directory: dir)
    try server.start()
    defer { server.stop() }
    let base = "http://127.0.0.1:\(server.port)"
    try artwork(NSSize(width: 800, height: 240)).write(to: dir.appendingPathComponent("wide.tiff"))
    let db = AppDatabase.empty()
    let source = Playlist(name: "Local cinema", serverURL: base, epgEnabled: false)
    try db.writeSync { db in
      try source.insert(db)
      try DBVODStream(streamId: 7, name: "Tideline", streamIcon: base + "/cover.tiff",
        director: "A. Rivera", cast: "Morgan Lee, Deniz Kaya",
        plot: "Two cartographers follow a changing coast.", genre: "Drama / Mystery, Romance | Adventure",
        releaseDate: "2024", rating5Based: 4.15, backdropPath: base + "/wide.tiff", youtubeTrailer: "  AbC123_9-xY\n", duration: "88 min",
        metadataLoaded: true, playlistId: source.id).insert(db)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    var openedTrailer: URL?
    let window = window(for: SourceLibrary().environment(\.appDatabase, db)
      .environmentObject(LocalizationManager.shared).environmentObject(DesktopPlayback(database: db))
      .environment(\.openURL, OpenURLAction { url in openedTrailer = url; return .handled })
      .defaultAppStorage(defaults))
    defer { window.close() }
    try await waitFor("Discover features fixture movie") { self.named("Tideline", window) != nil }
    try await press("Tideline", in: window)
    try await waitFor("Detail offers poster enlargement") { self.named(ML("enlarge_artwork"), window) != nil }
    try await waitFor("Provider genre separators become readable in detail") {
      self.named("Drama · Mystery · Romance · Adventure", window) != nil
    }
    let rating = try XCTUnwrap(BrowseAccessibility.ratingLabel(ContentRating.displayText(8.3)))
    try await waitFor("Detail converts provider five-point score to a localized ten-point score") {
      self.named(rating, window) != nil
    }
    let originalSize = try XCTUnwrap(window.contentView).bounds.size
    window.setContentSize(NSSize(width: 800, height: 560))
    try await waitFor("Movie actions fit within the minimum window width") {
      let frame = window.frame
      return [L("movie.play"), ML("favorite"), L("download.action")].allSatisfy { title in
        guard let control = self.named(title, window),
              let rect = (self.attribute(control, "accessibilityFrame") as? NSValue)?.rectValue else { return false }
        return rect.width > 0 && rect.minX >= frame.minX && rect.maxX <= frame.maxX
      }
    }
    try await capture(window, name: "Movie actions at minimum window width")
    window.setContentSize(originalSize)
    try await press(L("movie.trailer"), in: window)
    XCTAssertEqual(openedTrailer?.absoluteString, "https://www.youtube.com/watch?v=AbC123_9-xY")
    try db.writeSync { db in
      try db.execute(sql: "UPDATE vodStream SET rating5Based = ?, youtubeTrailer = ?, director = ?, [cast] = ? WHERE playlistId = ? AND streamId = 7",
        arguments: [3.5, "  ", " \n", "  Morgan Lee  ", source.id])
    }
    let updatedRating = try XCTUnwrap(BrowseAccessibility.ratingLabel(ContentRating.displayText(7)))
    try await waitFor("Open movie detail follows corrected rating and removed trailer") {
      self.named(updatedRating, window) != nil && self.named(L("movie.trailer"), window) == nil
        && self.named(L("movie.director"), window) == nil && self.named("Morgan Lee", window) != nil
    }
    try await press(ML("enlarge_artwork"), in: window)
    try await waitFor("Artwork missing from provider offers retry") {
      self.named(L("common.try_again"), window) != nil
    }
    XCTAssertNil(window.attachedSheet)
    try artwork(NSSize(width: 240, height: 360)).write(to: dir.appendingPathComponent("cover.tiff"))
    try await press(L("common.try_again"), in: window)
    func magnificationIs(_ factor: Double) -> Bool {
      self.accessible(window).contains {
        self.attribute($0, "accessibilityIdentifier") as? String == "artwork.image" &&
          self.attribute($0, "accessibilityValue") as? String == factor.formatted(.percent)
      }
    }
    try await waitFor("Retry loads native image at fitted size") { magnificationIs(1) }
    try await capture(window, name: "Artwork fitted in main window")
    try await press(ML("zoom_in"), in: window)
    try await waitFor("Zoom increases to two times fit") { magnificationIs(2) }
    try await press(ML("fit_artwork"), in: window)
    try await waitFor("Fit restores original magnification") { magnificationIs(1) }
    try await press(L("common.close"), in: window)
    try await waitFor("Closing artwork restores movie detail") {
      self.named("Two cartographers follow a changing coast.", window) != nil && self.named(ML("enlarge_artwork"), window) != nil
    }
    try await capture(window, name: "Movie detail with backdrop")
  }

  func testFilteredMovieQueueFollowsPersistedOrderBeyondFirstPage() async throws {
    let fixture = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let database = AppDatabase.shared
    let source = Playlist(
      name: "Archive", serverURL: "https://fixture.invalid", username: "user", password: "pass",
      epgEnabled: false)
    defer {
      _ = try? database.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    try database.writeSync { db in
      try source.insert(db)
      for id in 1...122 {
        try DBVODStream(
          streamId: id, name: String(format: "Coast %03d", id), rating: id == 122 ? "5" : "8",
          containerExtension: "mkv", metadataLoaded: true, sortIndex: id, playlistId: source.id
        ).insert(db)
      }
      for id in [120, 121] {
        let key = String(id)
        let path = DownloadStorage.relativePath(
          playlistId: source.id, type: "vod", streamId: key, ext: "mkv")
        try FileManager.default.copyItem(
          at: fixture, to: DownloadStorage.ensureParentDirectory(for: path))
        try DBDownloadedItem(
          id: DownloadManager.idFor(vod: source.id, streamId: id), playlistId: source.id,
          streamId: key, type: "vod", title: "Coast " + key,
          remoteURL: "https://fixture.invalid/" + key,
          localPath: path, containerExtension: "mkv", status: "completed"
        ).insert(db)
      }
    }
    let suite = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(source.id.uuidString, forKey: "lastPlaylistId")
    defaults.set(CatalogOrder.za.rawValue, forKey: "mac.catalog.sort.vod")
    let session = DesktopPlayback(database: database)
    let library = window(
      for: SourceLibrary().environment(\.appDatabase, database)
        .environmentObject(LocalizationManager.shared).environmentObject(session).defaultAppStorage(
          defaults))
    defer {
      session.close()
      library.close()
    }
    try await waitFor("Discover movie shelf") { self.named(ML("see_all"), library) != nil }
    try await press(ML("see_all"), in: library)
    try await press(L("filter.title"), in: library)
    let popover = try XCTUnwrap(library.childWindows?.first { $0.isVisible })
    try await press(L("filter.rating_7_plus"), in: popover)
    popover.performClose(nil)
    let first = BrowseAccessibility.cardLabel(title: "Coast 121", rating: "8", category: "")
    try await waitFor("First movie in descending order") { self.named(first, library) != nil }
    try await press(first, in: library)
    try await press(L("movie.play"), in: library)
    try await waitFor("Filtered queue spans all pages", timeout: 15) {
      session.current?.streamId == "121" && session.engine.isPlaybackEstablished
        && session.queue?.items.count == 121
    }
    XCTAssertEqual(session.queueIndex, 0)
    XCTAssertEqual(session.queue?.items.last?.id, "1")
    let player = window(
      for: MacPlayerView(
        session: session, engine: session.engine, media: try XCTUnwrap(session.current)))
    defer { player.close() }
    try await press(ML("next"), in: player)
    try await waitFor("Next visible movie decodes") {
      session.current?.streamId == "120" && session.engine.isPlaybackEstablished
    }
    XCTAssertEqual(session.queueIndex, 1)
    XCTAssertEqual(session.queue?.items.count, 121)
    XCTAssertTrue(MPRemoteCommandCenter.shared().skipForwardCommand.isEnabled)
  }

  func testMovieFilterPopoverChangesVisibleCatalogue() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Films", serverURL: "https://fixture.invalid")
    try database.writeSync { db in
      try source.insert(db)
      try DBVODStream(
        streamId: 1, name: "Harbor", rating: "7.5", containerExtension: "mkv", playlistId: source.id
      ).insert(db)
      try DBVODStream(
        streamId: 2, name: "Crossing", rating: "5", containerExtension: "mp4", playlistId: source.id
      ).insert(db)
    }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let view = NavigationStack {
      MacCatalogView(
        source: source, kinds: [.vod], title: "Films", search: "", favorites: false,
        isSearch: false, open: { _, _ in })
    }.environment(\.appDatabase, database).environmentObject(DesktopPlayback(database: database))
      .defaultAppStorage(defaults)
    let window = window(for: view)
    defer { window.close() }
    let crossing = BrowseAccessibility.cardLabel(title: "Crossing", rating: "5", category: "")
    let harbor = BrowseAccessibility.cardLabel(title: "Harbor", rating: "7.5", category: "")
    try await waitFor("Film catalogue ready") { self.named(crossing, window) != nil }
    try await press(L("filter.title"), in: window)
    let popover = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await press(L("filter.rating_7_plus"), in: popover)
    try await waitFor("Lower-rated film excluded") { self.named(crossing, window) == nil }
    try await press("MKV", in: popover)
    XCTAssertNotNil(named(harbor, window))
    try await capture(popover, name: "Movie catalogue filters")
    try await press(L("filter.clear"), in: popover)
    try await waitFor("Clearing filters restores the film") {
      self.named(crossing, window) != nil
    }
  }

  func testPlayerChannelPickerSearchesAcrossGroupsAndTunesTheSelectedQueue() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-recovery", withExtension: "ts"))
    try FileManager.default.copyItem(at: video, to: root.appendingPathComponent("live.ts"))
    let server = LocalHTTPServer(directory: root)
    try server.start()
    defer { server.stop() }
    let base = "http://127.0.0.1:\(server.port)/live.ts"
    let source = Playlist(name: "Local guide", serverURL: "", type: .m3u, epgEnabled: false)
    let database = AppDatabase.empty()
    var channels = [ParsedM3UChannel(name: "Morning news", url: base, groupTitle: "News")]
    channels += (1...10_000).map {
      ParsedM3UChannel(name: "Sports \($0)", url: base + "?id=\($0)", groupTitle: "Sports")
    }
    channels += [
      ParsedM3UChannel(name: "Sports film", url: "https://fixture.invalid/movie.mkv", groupTitle: "Sports"),
      ParsedM3UChannel(name: "Only film", url: "https://fixture.invalid/film.mp4", groupTitle: "Films"),
      ParsedM3UChannel(name: "Hidden channel", url: base + "?hidden", groupTitle: "Hidden")
    ]
    try await M3UImporter.replace(playlist: source, channels: channels, epgURL: nil, in: database)
    let hidden = HiddenCategoryStore.shared
    hidden.setHidden(true, playlistId: source.id, type: "m3u", categoryId: "Hidden")
    defer { hidden.setHidden(false, playlistId: source.id, type: "m3u", categoryId: "Hidden") }
    let first = try await database.read {
      try XCTUnwrap(MacCatalogQuery(playlistID: source.id, kinds: [.m3u], selectedGroup: "News").fetch($0).first)
    }
    let session = DesktopPlayback(database: database)
    let window = window(for: Color.clear.modifier(MacPlaybackPresentation(playback: session))
      .environment(\.appDatabase, database))
    defer { session.close(); window.close() }
    session.start(try await MediaSelection.resolve(first, in: source, database: database))
    try await waitFor("Live decoder and channel menu ready") {
      session.engine.isPlaybackEstablished && self.named(L("player.all_channels"), window) != nil
    }
    func bannerVisible() -> Bool {
      self.accessible(window).contains {
        self.attribute($0, "accessibilityIdentifier") as? String == "liveChannelBanner"
      }
    }
    XCTAssertFalse(bannerVisible())
    try await press(L("player.all_channels"), in: window)
    let list = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await waitFor("Current group and channel") {
      self.named("Morning news", list) != nil && self.named("News", list) != nil
    }
    try await press("News", in: list)
    let categories = try XCTUnwrap(list.childWindows?.first { $0.isVisible })
    try await waitFor("Other live category available") { self.named("Sports", categories) != nil }
    XCTAssertNil(named("Hidden", categories))
    XCTAssertNil(named("Films", categories))
    try await press("Sports", in: categories)
    try await waitFor("Sports channels replace news") {
      self.named("Sports 1", list) != nil && self.named("Morning news", list) == nil
    }
    func field(_ view: NSView) -> NSTextField? {
      if let text = view as? NSTextField, text.isEditable { return text }
      return view.subviews.lazy.compactMap { field($0) }.first
    }
    let input = try XCTUnwrap(list.contentView.flatMap(field))
    list.makeFirstResponder(input)
    let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
    editor.insertText("9999", replacementRange: editor.selectedRange())
    try await waitFor("Find channel beyond initial hundred") { self.named("Sports 9999", list) != nil }
    try await capture(list, name: "Search another channel group")
    try await press("Sports 9999", in: list)
    try await waitFor("Selected station plays with the whole sports group") {
      session.current?.title == "Sports 9999" && session.queue?.items.count == 10_000 && session.engine.isPlaybackEstablished
    }
    try await waitFor("Tuning across groups shows channel banner") { bannerVisible() }
    try await press(ML("next"), in: window)
    try await waitFor("Next stays in selected group") { session.current?.title == "Sports 10000" && session.engine.isPlaybackEstablished }
    try await waitFor("New station banner shown after rapid change") { bannerVisible() }
    try await capture(window, name: "Live channel change banner")
    try await waitFor("Channel banner disappears while playback continues", timeout: 6) {
      !bannerVisible() && session.engine.isPlaybackEstablished
    }
  }

  func testCatalogPickerHidesSelectedGroupAndRestoresItWithoutClosing() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Category visibility", serverURL: "https://fixture.invalid")
    let groups = [CatalogGroup(id: "news", name: "News"), CatalogGroup(id: "sport", name: "Sports")]
    try database.writeSync { db in
      try source.insert(db)
      for group in groups {
        try DBCategory(id: group.id, name: group.name, type: "live", playlistId: source.id).insert(db)
      }
      for i in 1...3 {
        try DBLiveStream(streamId: i, name: "One \(i)", categoryId: i == 3 ? "missing" : "news", playlistId: source.id).insert(db)
      }
    }
    let hidden = HiddenCategoryStore.shared
    defer { hidden.removeAll(playlistId: source.id) }
    hidden.setHidden(true, playlistId: source.id, type: "series", categoryId: "news")
    var selected: String? = "news"
    let allGroups = try database.writeSync { try MacCatalogQuery.groups(in: $0, playlist: source.id, kind: .live) }
    let window = window(for: MacCategoryPicker(groups: allGroups, kind: .live,
      selection: Binding(get: { selected }, set: { selected = $0 }), playlistID: source.id)
      .environment(\.appDatabase, database))
    defer { window.close() }
    try await press("News", in: window)
    let menu = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    try await waitFor("Group counts include orphans and empty groups") {
      ["0", "1", "2"].allSatisfy { self.named($0, menu) != nil }
    }
    try await press(L("category_picker.hide") + " · News", in: menu)
    try await waitFor("Selected category moves under Hidden without closing the picker") {
      menu.isVisible && selected == nil && hidden.isHidden(playlistId: source.id, type: "live", categoryId: "news")
        && self.named(L("category_picker.hidden_section"), menu) != nil
    }
    try await capture(menu, name: "Category visibility controls")
    try await press("News", in: menu)
    try await waitFor("Tapping the hidden category restores it and keeps the menu open") {
      menu.isVisible && !hidden.isHidden(playlistId: source.id, type: "live", categoryId: "news") && selected == nil
    }
    XCTAssertTrue(hidden.isHidden(playlistId: source.id, type: "series", categoryId: "news"))
    try await press("News", in: menu)
    try await waitFor("Restored category can now be selected") { selected == "news" && !menu.isVisible }
  }

  func testSearchableCategoryPickerSelectsLastGroup() async throws {
    let groups = (1...1200).map { CatalogGroup(id: String($0), name: "Category \($0)") }
    var selected: String?
    let picker = MacCategoryPicker(
      groups: groups, kind: .vod,
      selection: Binding(
        get: { selected }, set: { selected = $0 }))
    let window = window(for: picker)
    defer { window.close() }
    try await press(L("category_picker.title"), in: window)
    let popover = try XCTUnwrap(window.childWindows?.first { $0.isVisible })
    func findField(_ view: NSView) -> NSTextField? {
      if let field = view as? NSTextField, field.isEditable { return field }
      return view.subviews.lazy.compactMap { findField($0) }.first
    }
    let field = try XCTUnwrap(popover.contentView.flatMap(findField))
    popover.makeFirstResponder(field)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    editor.selectAll(nil)
    editor.insertText("1200", replacementRange: editor.selectedRange())
    try await Task.sleep(for: .milliseconds(500))
    try await capture(popover, name: "Category search diagnostic")
    try await waitFor("Category search filters to the last group") {
      self.named("Category 1200", popover) != nil && self.named("Category 1", popover) == nil
    }
    try await capture(popover, name: "Category search")
    try await press("Category 1200", in: popover)
    XCTAssertEqual(selected, "1200")
    try await waitFor("Picker dismisses after selection") { !popover.isVisible }
  }

  func testLongSeasonScrollsToLastEpisode() async throws {
    let database = AppDatabase.empty()
    let source = Playlist(name: "Series", serverURL: "https://fixture.invalid")
    let series = DBSeries(
      seriesId: 3, name: "Evening Report", seasonsLoaded: true, playlistId: source.id)
    let season = DBSeason(id: "archive", seasonNumber: 1, seriesId: 3, playlistId: source.id)
    try database.writeSync { db in
      try source.insert(db)
      try series.insert(db)
      try season.insert(db)
      for index in 1...1500 {
        try DBEpisode(
          id: String(index), episodeId: String(index), episodeNum: index,
          title: "Evening edition", duration: index == 1499 ? "90 min" : "24 min",
          rating: index == 1499 ? "8.4" : nil, seasonId: season.id
        ).insert(db)
      }
      try DBWatchHistory(
        id: "partial", playlistId: source.id, streamId: "1499", type: "series",
        lastTimeMs: 720_000, durationMs: 5_400_000, lastWatchedAt: Date().addingTimeInterval(-60),
        seriesId: "3", title: "Evening edition"
      ).insert(db)
      try DBWatchHistory(
        id: "watched", playlistId: source.id, streamId: "1500", type: "series",
        lastTimeMs: 1_440_000, durationMs: 1_440_000, lastWatchedAt: .now,
        seriesId: "3", title: "Evening edition"
      ).insert(db)
    }
    let item = CatalogItem(
      playlistId: source.id, kind: "series", streamKey: "3", title: series.name,
      category: "", artwork: nil, rating: nil, favorite: false, sortIndex: 0)
    let session = DesktopPlayback(database: database)
    let window = window(
      for: MacMediaDetail(item: item, source: source)
        .environment(\.appDatabase, database).environmentObject(session))
    defer { window.close() }
    func findScroll(_ view: NSView) -> NSScrollView? {
      if let scroll = view as? NSScrollView { return scroll }
      return view.subviews.lazy.compactMap { findScroll($0) }.first
    }
    let scroll = try XCTUnwrap(window.contentView.flatMap(findScroll))
    try await waitFor("Full season scroll extent") {
      (scroll.documentView?.frame.height ?? 0) > 70_000
    }
    try await waitFor("Last episode visible after scrolling") {
      guard let doc = scroll.documentView else { return false }
      let clip = scroll.contentView
      clip.scroll(to: NSPoint(x: 0, y: doc.isFlipped ? doc.bounds.height - clip.bounds.height : 0))
      scroll.reflectScrolledClipView(clip)
      window.contentView?.layoutSubtreeIfNeeded()
      return self.accessible(window).contains { element in
        let label = self.attribute(element, "accessibilityLabel") as? String ?? ""
        return label.contains("1500. Evening edition") && label.contains(L("detail.watched"))
      }
    }
    let remaining = L("detail.remaining_format", DetailFormatting.formatMs(4_680_000))
    let rating = try XCTUnwrap(BrowseAccessibility.ratingLabel(ContentRating.displayText(8.4)))
    try await waitFor("Episode shows its own rating and remaining time over one hour") {
      self.accessible(window).contains {
        let label = self.attribute($0, "accessibilityLabel") as? String ?? ""
        return label.contains("1499. Evening edition") && label.contains(rating) && label.contains(remaining)
      }
    }
    try await capture(window, name: "Long season")
  }

  func testSeriesDetailResumesOfflineEpisodeAfterCatalogRefresh() async throws {
    do {
      let database = AppDatabase.shared
      let source = Playlist(
        name: "Test Library", serverURL: "https://fixture.invalid",
        username: "test", password: "test")
      let fixture = try XCTUnwrap(
        Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
      let path = DownloadStorage.relativePath(
        playlistId: source.id, type: "episode", streamId: "12", ext: "mkv")
      let file = try DownloadStorage.ensureParentDirectory(for: path)
      defer {
        _ = try? database.writeSync { try source.delete($0) }
        Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
      }
      try FileManager.default.copyItem(at: fixture, to: file)
      try database.writeSync { db in
        try source.insert(db)
        try DBSeries(seriesId: 7, name: "Harbor", seasonsLoaded: true, playlistId: source.id)
          .insert(
            db)
        try DBWatchHistory(
          id: "\(source.id)_series_12", playlistId: source.id, streamId: "12", type: "series",
          lastTimeMs: 5_500, durationMs: 8_000, lastWatchedAt: Date(), seriesId: "7",
          title: "Night crossing", secondaryTitle: "Harbor", containerExtension: "mkv"
        ).insert(db)
        try DBDownloadedItem(
          id: DownloadManager.idFor(episode: source.id, episodeId: "12"), playlistId: source.id,
          streamId: "12", type: "episode", title: "Night crossing",
          remoteURL: "https://fixture.invalid/12",
          localPath: path, containerExtension: "mkv", status: "completed"
        ).insert(db)
      }
      let item = CatalogItem(
        playlistId: source.id, kind: "series", streamKey: "7", title: "Harbor",
        category: "Drama", artwork: nil, rating: nil, favorite: false, sortIndex: 0)
      let session = DesktopPlayback(database: database)
      let detail = MacMediaDetail(item: item, source: source).environment(\.appDatabase, database)
        .environmentObject(session)
      let window = window(for: detail)
      defer {
        session.close()
        window.close()
      }
      try await waitFor("Series resume action") { self.named(L("detail.resume"), window) != nil }
      let revisedCover = "http://127.0.0.1:1/harbor.jpg"
      try database.writeSync { db in
        try db.execute(sql: "UPDATE series SET name = ?, cover = ? WHERE playlistId = ? AND seriesId = 7",
          arguments: ["Harbor restored", revisedCover, source.id])
      }
      try await waitFor("Offline series detail shows updated name") { self.named("Harbor restored", window) != nil }
      try await capture(window, name: "Resume series")
      try await press(L("detail.resume"), in: window)
      try await waitFor("Resume stored episode at its saved time") {
        session.current?.streamId == "12" && session.engine.isPlaybackEstablished
          && session.engine.position >= 5.4
      }
      XCTAssertEqual(session.current?.secondaryTitle, "Harbor restored")
      XCTAssertEqual(session.current?.artwork, revisedCover)
    } catch {
      print("SERIES_DETAIL_ERROR", String(reflecting: error))
      throw error
    }
  }

  func testEpisodeQueueChangesSeasonAndAutoplays() async throws {
    let fixture = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "selected-tracks", withExtension: "mkv"))
    let db = AppDatabase.shared
    let source = Playlist(
      name: "Queue", serverURL: "https://queue.invalid", username: "user", password: "example")
    defer {
      _ = try? db.writeSync { try source.delete($0) }
      Task.detached { DownloadStorage.removePlaylistDirectory(playlistId: source.id) }
    }
    let series = DBSeries(seriesId: 10, name: "Harbor", cover: "http://127.0.0.1:1/harbor.jpg", playlistId: source.id)
    func episode(_ number: Int) -> DBEpisode {
      DBEpisode(
        id: DBEpisode.scopedId(playlistId: source.id, panelEpisodeId: String(number)),
        episodeId: String(number), episodeNum: 1, title: "Episode \(number)",
        containerExtension: "mkv", cover: number == 1 ? "http://127.0.0.1:1/episode-one.jpg" : " \n",
        seasonId: DBSeason.scopedId(playlistId: source.id, seriesId: 10, seasonNumber: number))
    }
    let first = episode(1)
    let second = episode(2)
    try db.writeSync { db in
      try source.insert(db)
      try series.insert(db)
      for (index, ep) in [first, second].enumerated() {
        try DBSeason(id: ep.seasonId, seasonNumber: index + 1, seriesId: 10, playlistId: source.id)
          .insert(db)
        try ep.insert(db)
        let key = String(index + 1)
        let relative = DownloadStorage.relativePath(
          playlistId: source.id, type: "episode", streamId: key, ext: "mkv")
        let file = try DownloadStorage.ensureParentDirectory(for: relative)
        try FileManager.default.copyItem(at: fixture, to: file)
        try DBDownloadedItem(
          id: DownloadManager.idFor(episode: source.id, episodeId: key), playlistId: source.id,
          streamId: key, type: "episode",
          title: ep.title ?? key, remoteURL: "https://queue.invalid/" + key, localPath: relative,
          containerExtension: "mkv", status: "completed"
        ).insert(db)
      }
    }
    try db.writeSync { db in
      try DBEpisode(id: "1", episodeNum: 9, title: "Old episode title", seasonId: second.seasonId).insert(db)
      let queue = try SeriesPlaybackOrdering.orderedEpisodes(seriesId: 10, playlistId: source.id, db: db)
      XCTAssertEqual(queue.map(\.id), [first.id, second.id])
      let displayed = try SeriesDetailData.seasonEpisodes(seasonId: second.seasonId, playlistId: source.id, db: db)
      XCTAssertEqual(displayed.episodes.map(\.id), [second.id])
      XCTAssertEqual(try SeriesDetailData.firstEpisode(seriesId: 10, playlistId: source.id, db: db)?.id, first.id)
    }
    let item = CatalogItem(
      playlistId: source.id, kind: "series", streamKey: "10", title: "Harbor", category: "",
      artwork: nil, rating: nil, favorite: false, sortIndex: 0)
    let preferences = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let session = DesktopPlayback(database: db, preferences: preferences)
    let media = try MediaSelection.episode(first, series: item, source: source)
    let window = window(for: MacPlayerView(session: session, engine: session.engine, media: media))
    defer {
      session.close()
      window.close()
    }
    preferences.set(true, forKey: "player.autoPlayNextEpisode")
    session.start(media)
    try await waitFor("Two seasons in playback queue", timeout: 12) {
      session.engine.isPlaybackEstablished && session.queue?.items.count == 2
    }
    session.setSleepTimer(seconds: 900, presetMinutes: 15)
    let deadline = try XCTUnwrap(session.sleepDeadline)
    session.engine.seek(to: 6.8)
    try await waitFor("Next episode countdown offers cancel while first episode remains selected") {
      session.current?.streamId == "1" && session.nextEpisodeSeconds != nil
        && self.named(L("common.cancel"), window) != nil
    }
    try await capture(window, name: "Next episode countdown")
    try await waitFor("Episode 2 starts automatically", timeout: 16) {
      session.current?.streamId == "2" && session.engine.isPlaybackEstablished
    }
    XCTAssertEqual(session.current?.artwork, series.cover)
    XCTAssertEqual(session.sleepDeadline, deadline)
    XCTAssertEqual(session.sleepPresetMinutes, 15)
    try await waitFor("Previous episode available from media controls") {
      let commands = MPRemoteCommandCenter.shared()
      return commands.previousTrackCommand.isEnabled && !commands.nextTrackCommand.isEnabled
        && !commands.skipForwardCommand.isEnabled && !commands.skipBackwardCommand.isEnabled
    }
    XCTAssertEqual(session.systemPlayback.perform(.skip(-15)), .commandFailed)
    XCTAssertEqual(session.systemPlayback.perform(.step(1)), .noSuchContent)
    XCTAssertEqual(session.systemPlayback.perform(.step(-1)), .success)
    try await waitFor("Previous episode restarts", timeout: 12) {
      session.current?.streamId == "1" && session.engine.isPlaybackEstablished
    }
    XCTAssertEqual(session.current?.artwork, first.cover)
    XCTAssertEqual(session.sleepDeadline, deadline)
    XCTAssertEqual(session.sleepPresetMinutes, 15)
    session.engine.seek(to: 6.8)
    try await waitFor("Returning to the first episode offers the countdown again") {
      session.nextEpisodeSeconds != nil && self.named(L("common.cancel"), window) != nil
    }
    try await press(L("common.cancel"), in: window)
    try await waitFor("Cancel dismisses the countdown") { session.nextEpisodeSeconds == nil }
    try await Task.sleep(for: .seconds(5.2))
    XCTAssertEqual(session.current?.streamId, "1")
    session.start(media)
    try await waitFor("Episode plays again with queue available") {
      session.engine.isPlaybackEstablished && session.queue?.items.count == 2
    }
    session.engine.seek(to: 6.8)
    try await waitFor("Autoplay pending before sleep timer expires") { session.nextEpisodeSeconds != nil }
    session.setSleepTimer(seconds: 0.1)
    try await waitFor("Sleep timer cancels pending autoplay") {
      session.sleepDeadline == nil && session.nextEpisodeSeconds == nil
    }
    try await Task.sleep(for: .seconds(5.2))
    XCTAssertEqual(session.current?.streamId, "1")
    session.start(media)
    try await waitFor("Fresh episode playback after sleep timer") {
      session.engine.isPlaybackEstablished && session.queue?.items.count == 2
    }
    session.engine.seek(to: 6.8)
    try await waitFor("Countdown before preference changes") { session.nextEpisodeSeconds != nil }
    preferences.set(false, forKey: "player.autoPlayNextEpisode")
    try await waitFor("Disabling autoplay dismisses countdown", timeout: 2) { session.nextEpisodeSeconds == nil }
    try await Task.sleep(for: .seconds(5.2))
    XCTAssertEqual(session.current?.streamId, "1")
    preferences.set(true, forKey: "player.autoPlayNextEpisode")
    session.start(media)
    try await waitFor("Playing again with autoplay enabled") {
      session.engine.isPlaybackEstablished && session.queue?.items.count == 2
    }
    session.engine.seek(to: 6.8)
    try await waitFor("Countdown before scrubbing") { session.nextEpisodeSeconds != nil }
    session.setScrubbing(true)
    XCTAssertNil(session.nextEpisodeSeconds)
    try await Task.sleep(for: .seconds(5.2))
    XCTAssertEqual(session.current?.streamId, "1")
    session.setScrubbing(false)
    session.seek(to: 2)
    try await waitFor("Scrub lands in the first episode") { abs(session.position - 2) < 1 }
    if session.isPaused { session.toggle() }
    session.expanded = false
    let mini = self.window(for: MacPlayerBar(session: session, engine: session.engine, media: media))
    defer { mini.close() }
    session.engine.seek(to: 6.8)
    try await waitFor("Immediate advance button appears") {
      self.named(L("player.autonext.countdown", 5), mini) != nil
    }
    try await press(L("player.autonext.countdown", 5), in: mini)
    try await waitFor("Immediate advance selects episode two before countdown expires", timeout: 3) {
      session.current?.streamId == "2" && session.engine.isPlaybackEstablished
    }
    XCTAssertFalse(session.expanded)
    session.close()
    XCTAssertNil(session.sleepDeadline)
    XCTAssertEqual(session.sleepPresetMinutes, 0)
  }

  private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
      self.description = description
      print("Mac UI check: " + description)
    }
  }
}
