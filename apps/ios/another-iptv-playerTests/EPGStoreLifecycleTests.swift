import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// What the guide store does on its own: on a return from the background, when
/// the network comes back, and when 'Show TV guide' is switched.
///
/// Each test owns a store over an in-memory database, a private defaults suite
/// and a stubbed session. The stores here have no lifecycle observers; the tests
/// call the handlers the observers would call.
@Suite("EPG store lifecycle")
struct EPGStoreLifecycleTests {

    private let suiteName = "EPGStoreLifecycleTests.\(UUID().uuidString)"
    private let channelKey = "news.tv"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    private func discardDefaults() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// A store bound to `playlist`, with its first index built.
    private func makeActiveStore(_ playlist: Playlist, database: AppDatabase, defaults: UserDefaults) async -> EPGStore {
        let store = EPGTestSupport.makeStore(database: database, defaults: defaults)
        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        // `setActivePlaylist` starts a reload of its own. Its reads are queued
        // ahead of this one, so once this returns that reload has published too
        // and the snapshot version stands still.
        await store.tick()
        return store
    }

    private func replaceProgramme(title: String, playlist: Playlist, in database: AppDatabase) async throws {
        let now = Int64(Date().timeIntervalSince1970)
        let key = channelKey
        try await database.write { db in
            try db.execute(sql: "DELETE FROM epgProgramme WHERE playlistId = ?", arguments: [playlist.id])
            try DBEPGProgramme(playlistId: playlist.id, channelKey: key,
                               startTs: now - 60, stopTs: now + 1_800, title: title).insert(db)
        }
    }

    private func nowTitle(_ store: EPGStore) -> String? {
        store.snapshot?[channelKey]?.now?.title
    }

    // MARK: Return from the background

    /// The minute timer sleeps before its first tick, so without this the cards
    /// keep the programme from before the background stay for up to a minute.
    @Test
    func returningFromTheBackgroundRebuildsTheIndexAtOnce() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.xtreamPlaylist()
        try await EPGTestSupport.seedMatchingGuide(in: database, playlist: playlist, title: "Before")
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        #expect(nowTitle(store) == "Before")
        let versionBefore = try #require(store.snapshot?.version)

        store.applicationDidEnterBackground()
        try await replaceProgramme(title: "After", playlist: playlist, in: database)
        await store.applicationDidBecomeActive()

        #expect(nowTitle(store) == "After")
        #expect(try #require(store.snapshot?.version) > versionBefore)
    }

    /// Control Centre, a notification banner and the app switcher also end in
    /// "did become active", without the app having been away.
    @Test
    func becomingActiveWithoutABackgroundStayPublishesNothing() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.xtreamPlaylist()
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: playlist,
            source: EPGTestSupport.source(playlist, attempt: 7 * 3_600, success: 7 * 3_600)
        )
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        let sourceBefore = try await EPGTestSupport.storedSource(playlist, in: database)
        // No suspension between this read and the call: the minute timer could
        // otherwise publish in between.
        let versionBefore = try #require(store.snapshot?.version)

        await store.applicationDidBecomeActive()

        #expect(store.snapshot?.version == versionBefore)
        // And the stale guide is not fetched from here either.
        #expect(try await EPGTestSupport.storedSource(playlist, in: database) == sourceBefore)
    }

    /// The TTL was only looked at when a dashboard was mounted, so a process that
    /// stayed alive never refreshed its guide again.
    @Test
    func returningFromTheBackgroundRefreshesAGuideOlderThanItsTTL() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let host = EPGTestSupport.uniqueHost()
        let playlist = EPGTestSupport.xtreamPlaylist(host: host)
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: playlist, title: "Stored",
            source: EPGTestSupport.source(playlist, attempt: 7 * 3_600, success: 7 * 3_600)
        )
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: [channelKey], title: "Downloaded"), onHost: host)
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        #expect(nowTitle(store) == "Stored")

        store.applicationDidEnterBackground()
        await store.applicationDidBecomeActive()

        #expect(nowTitle(store) == "Downloaded")
        #expect(store.refreshState[playlist.id] == .idle)
        let source = try #require(try await EPGTestSupport.storedSource(playlist, in: database))
        #expect(try #require(source.lastSuccessAt).timeIntervalSinceNow > -60)
    }

    @Test
    func returningFromTheBackgroundLeavesAFreshGuideAlone() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let host = EPGTestSupport.uniqueHost()
        let playlist = EPGTestSupport.xtreamPlaylist(host: host)
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: playlist, title: "Stored",
            source: EPGTestSupport.source(playlist, attempt: 3_600, success: 3_600)
        )
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: [channelKey], title: "Downloaded"), onHost: host)
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        let sourceBefore = try await EPGTestSupport.storedSource(playlist, in: database)

        store.applicationDidEnterBackground()
        await store.applicationDidBecomeActive()

        #expect(nowTitle(store) == "Stored")
        #expect(try await EPGTestSupport.storedSource(playlist, in: database) == sourceBefore)
    }

    // MARK: Network back

    @Test
    func aReconnectRetriesAFailedGuideOnlyOutsideTheCooldown() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let host = EPGTestSupport.uniqueHost()
        let playlist = EPGTestSupport.xtreamPlaylist(host: host)
        // Stale, and the last attempt failed five minutes ago.
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: playlist, title: "Stored",
            source: EPGTestSupport.source(playlist, attempt: 5 * 60, success: 7 * 3_600, error: "offline")
        )
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: [channelKey], title: "Downloaded"), onHost: host)
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        let sourceBefore = try await EPGTestSupport.storedSource(playlist, in: database)

        await store.networkDidReconnect()

        #expect(nowTitle(store) == "Stored")
        #expect(try await EPGTestSupport.storedSource(playlist, in: database) == sourceBefore)

        // Twenty minutes after the failed attempt the cooldown is over.
        let earlier = Date().addingTimeInterval(-20 * 60)
        try await database.write { db in
            try db.execute(sql: "UPDATE epgSource SET fetchedAt = ? WHERE playlistId = ?",
                           arguments: [earlier, playlist.id])
        }

        await store.networkDidReconnect()

        #expect(nowTitle(store) == "Downloaded")
        let source = try #require(try await EPGTestSupport.storedSource(playlist, in: database))
        #expect(source.lastError == nil)
    }

    @Test
    func nothingIsFetchedOnAReconnectInTheBackground() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let host = EPGTestSupport.uniqueHost()
        let playlist = EPGTestSupport.xtreamPlaylist(host: host)
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: playlist, title: "Stored",
            source: EPGTestSupport.source(playlist, attempt: 7 * 3_600, success: 7 * 3_600)
        )
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: [channelKey], title: "Downloaded"), onHost: host)
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        let sourceBefore = try await EPGTestSupport.storedSource(playlist, in: database)

        store.applicationDidEnterBackground()
        await store.networkDidReconnect()

        #expect(try await EPGTestSupport.storedSource(playlist, in: database) == sourceBefore)
    }

    // MARK: 'Show TV guide'

    @Test
    func theGuideCountsAsEnabledWhileNoPlaylistIsActive() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.xtreamPlaylist(epgEnabled: false)
        try await database.write { db in try playlist.insert(db) }
        let store = EPGTestSupport.makeStore(database: database, defaults: defaults)
        #expect(store.isGuideEnabled)

        store.setActivePlaylist(playlist)
        #expect(!store.isGuideEnabled)
        await store.reload(playlist: playlist)
        #expect(!store.isGuideEnabled)

        store.setActivePlaylist(nil)
        #expect(store.isGuideEnabled)
    }

    @Test
    func switchingTheGuideOffRemovesTheLinesAndKeepsTheStoredGuide() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.xtreamPlaylist()
        try await EPGTestSupport.seedMatchingGuide(in: database, playlist: playlist, title: "Stored")
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        #expect(store.isGuideEnabled)
        #expect(nowTitle(store) == "Stored")
        let sourceBefore = try await EPGTestSupport.storedSource(playlist, in: database)

        let off = try #require(try await database.updatePlaylist(id: playlist.id) { $0.epgEnabled = false })
        await store.setGuideEnabled(false, playlist: off)

        #expect(!store.isGuideEnabled)
        #expect(store.snapshot == nil)
        #expect(!store.isLineReserved(for: off))
        // Neither the minute tick nor a return to the app brings the lines back.
        await store.tick()
        #expect(store.snapshot == nil)
        store.applicationDidEnterBackground()
        await store.applicationDidBecomeActive()
        #expect(store.snapshot == nil)
        #expect(try await EPGTestSupport.storedProgrammeCount(playlist, in: database) == 1)

        // Back on: the lines return from the stored rows, without a download.
        let on = try #require(try await database.updatePlaylist(id: playlist.id) { $0.epgEnabled = true })
        await store.setGuideEnabled(true, playlist: on)

        #expect(store.isGuideEnabled)
        #expect(nowTitle(store) == "Stored")
        #expect(try await EPGTestSupport.storedSource(playlist, in: database) == sourceBefore)
    }

    /// `tick` awaits a database read. A tick that was waiting for it when the
    /// switch went off must not publish its index afterwards.
    @Test
    func aTickInFlightWhenTheGuideGoesOffPublishesNothing() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.xtreamPlaylist()
        try await EPGTestSupport.seedMatchingGuide(in: database, playlist: playlist, title: "Stored")
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        let off = try #require(try await database.updatePlaylist(id: playlist.id) { $0.epgEnabled = false })

        // Hold the database so the tick's read has to wait.
        let release = DispatchSemaphore(value: 0)
        let hold = Task.detached {
            _ = try? await database.write { _ in release.wait() }
        }
        try await Task.sleep(for: .milliseconds(50))
        let tick = Task { await store.tick() }
        try await Task.sleep(for: .milliseconds(50))

        await store.setGuideEnabled(false, playlist: off)
        #expect(store.snapshot == nil)
        release.signal()
        await tick.value
        await hold.value

        #expect(store.snapshot == nil)
    }

    /// The dashboard keeps the playlist value it was opened with. The row is what
    /// counts: switched off there, the store shows nothing and downloads nothing,
    /// whatever the copy says and whichever entry point is used.
    @Test
    func theStoredRowSwitchesTheGuideOffForAStaleCopy() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let host = EPGTestSupport.uniqueHost()
        let staleCopy = EPGTestSupport.xtreamPlaylist(host: host)
        var row = staleCopy
        row.epgEnabled = false
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: row, title: "Stored",
            source: EPGTestSupport.source(row, attempt: 7 * 3_600, success: 7 * 3_600)
        )
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: [channelKey], title: "Downloaded"), onHost: host)
        let sourceBefore = try await EPGTestSupport.storedSource(row, in: database)

        let store = EPGTestSupport.makeStore(database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        store.setActivePlaylist(staleCopy)
        // The first frame can only go by the copy.
        #expect(store.isGuideEnabled)
        await store.reload(playlist: staleCopy)
        #expect(!store.isGuideEnabled)
        #expect(store.snapshot == nil)

        await store.refreshIfStale(playlist: staleCopy)
        await store.refreshIfStale(playlistId: staleCopy.id)
        await store.forceRefresh(playlist: staleCopy)

        #expect(!store.isGuideEnabled)
        #expect(store.snapshot == nil)
        #expect(try await EPGTestSupport.storedSource(row, in: database) == sourceBefore)
    }

    /// The other direction, and the path the settings screen uses today: it saves
    /// the row and calls `refreshIfStale`. The store notices the switch there.
    @Test
    func aRowSwitchedOnIsNoticedByTheNextRefreshCheck() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.xtreamPlaylist(epgEnabled: false)
        try await EPGTestSupport.seedMatchingGuide(in: database, playlist: playlist, title: "Stored")
        let store = await makeActiveStore(playlist, database: database, defaults: defaults)
        defer { store.setActivePlaylist(nil) }
        #expect(!store.isGuideEnabled)
        #expect(store.snapshot == nil)

        let on = try #require(try await database.updatePlaylist(id: playlist.id) { $0.epgEnabled = true })
        await store.refreshIfStale(playlist: on)

        #expect(store.isGuideEnabled)
        #expect(nowTitle(store) == "Stored")
    }

    @Test
    func refreshIfStaleByIdDoesNothingForAPlaylistThatIsGone() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let store = EPGTestSupport.makeStore(database: AppDatabase.empty(), defaults: defaults)

        await store.refreshIfStale(playlistId: UUID())

        #expect(store.refreshState.isEmpty)
        #expect(store.snapshot == nil)
    }
}
