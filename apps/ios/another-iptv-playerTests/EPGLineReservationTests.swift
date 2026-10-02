import Combine
import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// When channel cards reserve the now/next line, and how the snapshot follows:
/// a placeholder from the moment a playlist with an expected guide becomes active,
/// kept while nothing is known yet or while the guide has something for the
/// playlist's channels; nil when the guide is switched off, when none is expected,
/// and when a refresh attempt has finished and matched none of the channels.
///
/// Each test owns a store over an in-memory database, a private defaults suite and
/// a stubbed session: a refresh either gets the guide a test serves or fails like
/// a dead connection.
@Suite("EPG now/next line reservation")
struct EPGLineReservationTests {

    private let suiteName = "EPGLineReservationTests.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    private func discardDefaults() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func xtream(epgEnabled: Bool = true) -> Playlist {
        Playlist(name: "Panel", serverURL: "http://panel:8080", username: "u", password: "p",
                 epgEnabled: epgEnabled)
    }

    private func m3u(header: String? = nil, override: String? = nil, epgEnabled: Bool = true) -> Playlist {
        Playlist(name: "List", serverURL: "http://host/list.m3u", type: .m3u,
                 m3uEpgURL: header, epgURLOverride: override, epgEnabled: epgEnabled)
    }

    private func makeDatabase(with playlist: Playlist, sourceRow: Bool) async throws -> AppDatabase {
        try await makeDatabase(with: playlist, source: sourceRow
            ? DBEPGSource(playlistId: playlist.id, sourceType: EPGSourceType.xtreamXMLTV.rawValue)
            : nil)
    }

    private func makeDatabase(with playlist: Playlist, source: DBEPGSource?) async throws -> AppDatabase {
        let database = AppDatabase.empty()
        try await database.write { db in
            try playlist.insert(db)
            try source?.insert(db)
        }
        return database
    }

    private func makeStore(_ database: AppDatabase, _ defaults: UserDefaults) -> EPGStore {
        EPGTestSupport.makeStore(database: database, defaults: defaults)
    }

    /// One live channel with the EPG id `news.tv`, for a playlist that is stored already.
    private func addChannel(to playlist: Playlist, in database: AppDatabase) async throws {
        try await database.write { db in
            try DBLiveStream(streamId: 1, name: "News", epgChannelId: "news.tv", playlistId: playlist.id).insert(db)
        }
    }

    // MARK: The rule

    @Test
    func guideIsExpectedWhenThereIsASourceAndItIsSwitchedOn() {
        #expect(EPGStore.expectsGuide(xtream()))
        #expect(!EPGStore.expectsGuide(xtream(epgEnabled: false)))

        #expect(!EPGStore.expectsGuide(m3u()))
        #expect(EPGStore.expectsGuide(m3u(header: "http://host/guide.xml")))
        #expect(EPGStore.expectsGuide(m3u(override: "https://guide.example/manual.xml")))
        // A blank override is no override.
        #expect(!EPGStore.expectsGuide(m3u(override: "   ")))
        #expect(!EPGStore.expectsGuide(m3u(header: "http://host/guide.xml", epgEnabled: false)))
    }

    @Test
    func lineIsReservedBeforeAnythingLoadedWhenAGuideIsExpected() throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }

        #expect(EPGStore.isLineReserved(for: xtream(), defaults: defaults))
        #expect(EPGStore.isLineReserved(for: m3u(header: "http://host/guide.xml"), defaults: defaults))
        #expect(!EPGStore.isLineReserved(for: xtream(epgEnabled: false), defaults: defaults))
        #expect(!EPGStore.isLineReserved(for: m3u(), defaults: defaults))
    }

    /// A remembered answer outweighs the expectation in both directions, except
    /// that nothing reserves the line of a guide that is switched off.
    @Test
    func aRememberedAnswerOutweighsTheExpectation() throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let expected = xtream()
        let notExpected = m3u()
        var switchedOff = expected
        switchedOff.epgEnabled = false

        defaults.set(false, forKey: "epg.lineReserved.\(expected.id.uuidString)")
        defaults.set(true, forKey: "epg.lineReserved.\(notExpected.id.uuidString)")
        #expect(!EPGStore.isLineReserved(for: expected, defaults: defaults))
        #expect(EPGStore.isLineReserved(for: notExpected, defaults: defaults))

        defaults.set(true, forKey: "epg.lineReserved.\(expected.id.uuidString)")
        #expect(EPGStore.isLineReserved(for: expected, defaults: defaults))
        #expect(!EPGStore.isLineReserved(for: switchedOff, defaults: defaults))
    }

    // MARK: Snapshot

    @Test
    func expectedGuideGetsAPlaceholderAtOnceAndKeepsIt() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let store = makeStore(try await makeDatabase(with: playlist, sourceRow: false), defaults)
        defer { store.setActivePlaylist(nil) }

        #expect(store.snapshot == nil)
        #expect(store.isLineReserved(for: playlist))

        store.setActivePlaylist(playlist)
        // Synchronously, before the store has read anything.
        #expect(store.snapshot != nil)
        #expect(store.snapshot?.byChannelKey.isEmpty == true)
        #expect(store.isLineReserved(for: playlist))

        // No source row, no programmes: the index comes back empty, the line stays.
        await store.reload(playlist: playlist)
        #expect(store.snapshot != nil)
        #expect(store.snapshot?.byChannelKey.isEmpty == true)
        #expect(store.isLineReserved(for: playlist))

        await store.tick()
        #expect(store.snapshot != nil)
    }

    @Test
    func playlistWithoutAGuideStaysCompact() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = m3u()
        let store = makeStore(try await makeDatabase(with: playlist, sourceRow: false), defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        #expect(store.snapshot == nil)

        await store.reload(playlist: playlist)
        #expect(store.snapshot == nil)
        #expect(!store.isLineReserved(for: playlist))
        #expect(!EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    @Test
    func leavingTheDashboardClearsTheSnapshot() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let store = makeStore(try await makeDatabase(with: playlist, sourceRow: false), defaults)

        store.setActivePlaylist(playlist)
        #expect(store.snapshot != nil)

        store.setActivePlaylist(nil)
        #expect(store.snapshot == nil)
        // With no active playlist the answer comes from the rule again.
        #expect(store.isLineReserved(for: playlist))
    }

    /// The guide was switched on, or an XMLTV URL saved, while the playlist is on
    /// screen: settings saves the row and calls the store, which reserves the line
    /// then, without waiting for a download.
    @Test
    func aGuideThatBecomesExpectedReservesTheLineRightAway() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = m3u()
        let database = try await makeDatabase(with: playlist, sourceRow: false)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        #expect(store.snapshot == nil)

        let withGuide = try #require(try await database.updatePlaylist(id: playlist.id) {
            $0.epgURLOverride = "https://guide.example/manual.xml"
        })
        await store.reload(playlist: withGuide)

        #expect(store.snapshot != nil)
        #expect(store.isLineReserved(for: withGuide))
    }

    // MARK: Copies older than the row

    /// The dashboard and the settings sections keep the playlist value they were
    /// opened with. The row has had its guide switched on since; a call that still
    /// carries the old value must not take the line away again.
    @Test
    func aStaleCopyCannotDropTheLineOfAnXtreamPlaylist() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let staleCopy = xtream(epgEnabled: false)
        var row = staleCopy
        row.epgEnabled = true
        let database = AppDatabase.empty()
        try await EPGTestSupport.seedMatchingGuide(in: database, playlist: row)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(staleCopy)
        // The first frame can only go by the copy.
        #expect(store.snapshot == nil)
        await store.reload(playlist: staleCopy)
        #expect(store.isGuideEnabled)
        #expect(store.snapshot?["news.tv"]?.now?.title == "Bulletin")

        // The stored guide is fresh, so nothing is downloaded.
        await store.refreshIfStale(playlist: staleCopy)
        #expect(store.snapshot != nil)

        await store.tick()
        #expect(store.snapshot != nil)
        #expect(store.isLineReserved(for: staleCopy))
        #expect(EPGStore.isLineReserved(for: row, defaults: defaults))
    }

    /// Before anything was downloaded the same holds for the placeholder.
    @Test
    func aStaleCopyCannotDropThePlaceholderOfAnXtreamPlaylist() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let staleCopy = xtream(epgEnabled: false)
        var row = staleCopy
        row.epgEnabled = true
        let store = makeStore(try await makeDatabase(with: row, sourceRow: false), defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(staleCopy)
        await store.reload(playlist: staleCopy)
        #expect(store.snapshot != nil)
        #expect(store.snapshot?.byChannelKey.isEmpty == true)

        // Nothing downloaded, nothing on air: the minute tick keeps the placeholder.
        await store.tick()
        #expect(store.snapshot != nil)
        #expect(store.isLineReserved(for: staleCopy))
        #expect(EPGStore.isLineReserved(for: row, defaults: defaults))
    }

    @Test
    func aStaleCopyCannotDropTheLineOfAnM3UPlaylist() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let staleCopy = m3u()
        var row = staleCopy
        row.epgURLOverride = "https://guide.example/manual.xml"
        let database = AppDatabase.empty()
        try await EPGTestSupport.seedMatchingGuide(in: database, playlist: row)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(staleCopy)
        #expect(store.snapshot == nil)
        await store.reload(playlist: staleCopy)
        #expect(store.snapshot?["news.tv"]?.now?.title == "Bulletin")

        // The stored guide is fresh, so nothing is downloaded.
        await store.refreshIfStale(playlist: staleCopy)
        await store.tick()
        #expect(store.snapshot != nil)
        #expect(store.isLineReserved(for: staleCopy))
    }

    /// The other direction: the row has given the guide up, the copy still asks
    /// for one. The line goes, as it would on the next launch.
    @Test
    func aStaleCopyCannotKeepALineTheRowGaveUp() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let staleCopy = xtream()
        var row = staleCopy
        row.epgEnabled = false
        let store = makeStore(try await makeDatabase(with: row, sourceRow: false), defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(staleCopy)
        // The first frame can only go by the copy.
        #expect(store.snapshot != nil)

        await store.reload(playlist: staleCopy)
        #expect(!store.isGuideEnabled)
        #expect(store.snapshot == nil)
        #expect(!store.isLineReserved(for: staleCopy))
        #expect(!EPGStore.isLineReserved(for: row, defaults: defaults))
    }

    /// Without a stored row there is nothing to check the copy against; it can
    /// still reserve the line.
    @Test
    func aPlaylistWithoutAStoredRowGoesByTheCopy() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let store = makeStore(AppDatabase.empty(), defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        #expect(store.snapshot != nil)

        var switchedOff = playlist
        switchedOff.epgEnabled = false
        await store.refreshIfStale(playlist: switchedOff)
        await store.tick()
        #expect(store.snapshot != nil)
    }

    // MARK: A guide that matches nothing

    /// A panel that serves no guide for this playlist's channels: once a refresh
    /// has finished there is nothing left to wait for, and the cards give the
    /// line back. The answer is remembered, so the next launch starts without it.
    @Test
    func aFinishedAttemptThatMatchedNothingGivesTheLineUp() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let database = try await makeDatabase(with: playlist,
                                              source: EPGTestSupport.source(playlist, attempt: 60, success: 60))
        try await addChannel(to: playlist, in: database)

        let firstLaunch = makeStore(database, defaults)
        firstLaunch.setActivePlaylist(playlist)
        // Nothing is known on the very first frame; the expectation reserves it.
        #expect(firstLaunch.snapshot != nil)
        await firstLaunch.reload(playlist: playlist)
        #expect(firstLaunch.snapshot == nil)
        #expect(!firstLaunch.isLineReserved(for: playlist))
        firstLaunch.setActivePlaylist(nil)

        #expect(!EPGStore.isLineReserved(for: playlist, defaults: defaults))

        let secondLaunch = makeStore(database, defaults)
        defer { secondLaunch.setActivePlaylist(nil) }
        #expect(!secondLaunch.isLineReserved(for: playlist))
        secondLaunch.setActivePlaylist(playlist)
        // Compact from the first frame, and it stays that way.
        #expect(secondLaunch.snapshot == nil)
        await secondLaunch.reload(playlist: playlist)
        #expect(secondLaunch.snapshot == nil)
        await secondLaunch.tick()
        #expect(secondLaunch.snapshot == nil)
    }

    @Test
    func aFailedAttemptCountsAsFinished() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let database = try await makeDatabase(
            with: playlist, source: EPGTestSupport.source(playlist, attempt: 60, success: nil, error: "HTTP 404")
        )
        try await addChannel(to: playlist, in: database)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)

        #expect(store.snapshot == nil)
        #expect(!EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    /// An attempt that has started and not reported back says nothing yet: the
    /// line waits for it.
    @Test
    func anAttemptWithoutAnOutcomeKeepsTheLine() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let database = try await makeDatabase(with: playlist,
                                              source: EPGTestSupport.source(playlist, attempt: 5, success: nil))
        try await addChannel(to: playlist, in: database)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        await store.tick()

        #expect(store.snapshot != nil)
        #expect(store.snapshot?.byChannelKey.isEmpty == true)
        #expect(EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    /// The guide knows the channel but has nothing on air for it right now: the
    /// line stays, empty, because the next programme will fill it.
    @Test
    func aMatchedChannelKeepsTheLineWithNothingOnAir() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let database = try await makeDatabase(with: playlist,
                                              source: EPGTestSupport.source(playlist, attempt: 60, success: 60))
        try await addChannel(to: playlist, in: database)
        try await database.write { db in
            try DBEPGChannel(playlistId: playlist.id, channelKey: "news.tv", displayName: "News").insert(db)
        }
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        await store.tick()

        #expect(store.snapshot != nil)
        #expect(store.snapshot?.byChannelKey.isEmpty == true)
        #expect(EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    /// The first refresh of a new playlist fails (here: the panel does not answer).
    /// The placeholder was held for that refresh, and goes with its outcome.
    @Test
    func theLineGoesWhenTheFirstRefreshEndsWithoutAMatch() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = EPGTestSupport.xtreamPlaylist()
        let database = try await makeDatabase(with: playlist, source: nil)
        try await addChannel(to: playlist, in: database)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        #expect(store.snapshot != nil)

        await store.refreshIfStale(playlist: playlist)

        if case .failed = store.refreshState[playlist.id] {} else {
            Issue.record("the refresh was expected to fail")
        }
        #expect(store.snapshot == nil)
        #expect(!EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    /// A guide that has none of the playlist's channels downloads and parses fine;
    /// it is still "nothing to show".
    @Test
    func theLineGoesWhenTheDownloadedGuideHasNoneOfTheChannels() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let host = EPGTestSupport.uniqueHost()
        let playlist = EPGTestSupport.xtreamPlaylist(host: host)
        let database = try await makeDatabase(with: playlist, source: nil)
        try await addChannel(to: playlist, in: database)
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: ["someone.else"]), onHost: host)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }

        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        #expect(store.snapshot != nil)

        await store.refreshIfStale(playlist: playlist)

        #expect(store.snapshot == nil)
        #expect(!EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    @Test
    func aLaterRefreshThatMatchesBringsTheLineBack() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let host = EPGTestSupport.uniqueHost()
        let playlist = EPGTestSupport.xtreamPlaylist(host: host)
        let database = try await makeDatabase(
            with: playlist, source: EPGTestSupport.source(playlist, attempt: 3_600, success: nil, error: "HTTP 404")
        )
        try await addChannel(to: playlist, in: database)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }
        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        #expect(store.snapshot == nil)
        #expect(!EPGStore.isLineReserved(for: playlist, defaults: defaults))

        // The panel has a guide now.
        EPGTestSupport.serve(EPGTestSupport.guideXML(channelIds: ["news.tv"], title: "Bulletin"), onHost: host)
        await store.refreshIfStale(playlist: playlist)

        #expect(store.snapshot?["news.tv"]?.now?.title == "Bulletin")
        #expect(store.isLineReserved(for: playlist))
        #expect(EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    /// With the answer known, a refresh must not put the line back for its own
    /// duration only to take it away again.
    @Test
    func aRefreshThatMatchesNothingAgainLeavesTheLineAlone() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = EPGTestSupport.xtreamPlaylist()
        let database = try await makeDatabase(
            with: playlist, source: EPGTestSupport.source(playlist, attempt: 3_600, success: nil, error: "HTTP 404")
        )
        try await addChannel(to: playlist, in: database)
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }
        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        await store.tick()
        #expect(store.snapshot == nil)

        var published: [Bool] = []
        let subscription = store.$snapshot.dropFirst().sink { published.append($0 != nil) }
        defer { subscription.cancel() }
        await store.refreshIfStale(playlist: playlist)
        await store.forceRefresh(playlist: playlist)

        #expect(!published.contains(true))
        #expect(store.snapshot == nil)
    }

    /// The same with a guide that does match: a refresh that fails leaves the
    /// stored guide in place, and the line with it.
    @Test
    func aFailedRefreshLeavesAMatchingGuideOnScreen() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = EPGTestSupport.xtreamPlaylist()
        let database = AppDatabase.empty()
        try await EPGTestSupport.seedMatchingGuide(
            in: database, playlist: playlist,
            source: EPGTestSupport.source(playlist, attempt: 7 * 3_600, success: 7 * 3_600)
        )
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }
        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        await store.tick()
        #expect(store.snapshot?["news.tv"]?.now?.title == "Bulletin")

        var published: [Bool] = []
        let subscription = store.$snapshot.dropFirst().sink { published.append($0 != nil) }
        defer { subscription.cancel() }
        await store.refreshIfStale(playlist: playlist)

        if case .failed = store.refreshState[playlist.id] {} else {
            Issue.record("the refresh was expected to fail")
        }
        #expect(!published.contains(false))
        #expect(store.snapshot?["news.tv"]?.now?.title == "Bulletin")
        #expect(EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    @Test
    func deletingAPlaylistForgetsItsRememberedAnswer() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let database = try await makeDatabase(with: playlist,
                                              source: EPGTestSupport.source(playlist, attempt: 60, success: 60))
        let store = makeStore(database, defaults)
        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)
        store.setActivePlaylist(nil)
        #expect(!EPGStore.isLineReserved(for: playlist, defaults: defaults))

        EPGStore.forgetLineReservation(playlistId: playlist.id, defaults: defaults)

        // Back to the expectation alone.
        #expect(EPGStore.isLineReserved(for: playlist, defaults: defaults))
    }

    // MARK: Alias map

    @Test
    func resolutionSnapshotResolvesLikeTheStore() async throws {
        let defaults = try makeDefaults()
        defer { discardDefaults() }
        let playlist = xtream()
        let database = try await makeDatabase(with: playlist, sourceRow: true)
        try await database.write { db in
            // Guide channel "bbc.one" with a display name; the playlist's channel has
            // no EPG id and is matched by that name.
            try DBEPGChannel(playlistId: playlist.id, channelKey: "bbc.one", displayName: "BBC One").insert(db)
            try DBEPGChannel(playlistId: playlist.id, channelKey: "itv.1", displayName: "ITV").insert(db)
            try DBLiveStream(streamId: 1, name: "BBC One", playlistId: playlist.id).insert(db)
            try DBLiveStream(streamId: 2, name: "ITV 1", epgChannelId: "ITV.1", playlistId: playlist.id).insert(db)
            try DBLiveStream(streamId: 3, name: "Unknown", epgChannelId: "none", playlistId: playlist.id).insert(db)
        }
        let store = makeStore(database, defaults)
        defer { store.setActivePlaylist(nil) }
        store.setActivePlaylist(playlist)
        await store.reload(playlist: playlist)

        let aliases = store.resolutionSnapshot
        #expect(aliases["bbc one"] == "bbc.one")
        #expect(aliases["itv.1"] == "itv.1")
        #expect(aliases["none"] == nil)

        let lookups: [(idKey: String?, nameKey: String?)] = [
            (nil, "bbc one"),
            ("itv.1", "itv 1"),
            ("none", "unknown"),
            (nil, "unknown"),
            (nil, nil)
        ]
        for lookup in lookups {
            #expect(EPGStore.storedKey(idKey: lookup.idKey, nameKey: lookup.nameKey, in: aliases)
                    == store.storedKey(idKey: lookup.idKey, nameKey: lookup.nameKey))
        }
        #expect(EPGStore.storedKey(idKey: nil, nameKey: "bbc one", in: aliases) == "bbc.one")
        // An id nothing resolves falls back to itself; a name alone does not.
        #expect(EPGStore.storedKey(idKey: "none", nameKey: "unknown", in: aliases) == "none")
        #expect(EPGStore.storedKey(idKey: nil, nameKey: "unknown", in: aliases) == nil)
    }
}
