import Combine
import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// The M3U store's revision counter, id lookup and filter handling, on a store of
/// its own over an in-memory database.
@Suite("M3U content store")
struct M3UContentStoreTests {

    private let playlist = Playlist(name: "Lists", serverURL: "http://host/list.m3u", type: .m3u)

    private var parsedChannels: [ParsedM3UChannel] {
        [
            ParsedM3UChannel(name: "News One", url: "http://host/live/1.ts", groupTitle: "News"),
            ParsedM3UChannel(name: "Loose", url: "http://host/live/2.ts", groupTitle: nil),
            ParsedM3UChannel(name: "News Two", url: "http://host/live/3.ts", groupTitle: " News "),
            ParsedM3UChannel(name: "Late Night", url: "http://host/live/4.ts", groupTitle: "Adult"),
            ParsedM3UChannel(name: "XXX Channel", url: "http://host/live/5.ts", groupTitle: "Mixed"),
            ParsedM3UChannel(name: "Blank group", url: "http://host/live/6.ts", groupTitle: "   ")
        ]
    }

    private func id(_ url: String) -> String {
        M3UImporter.stableChannelID(playlistId: playlist.id, url: url)
    }

    private func seededDatabase() async throws -> AppDatabase {
        let database = AppDatabase.empty()
        try await M3UImporter.replace(playlist: playlist, channels: parsedChannels, epgURL: nil, in: database)
        return database
    }

    // MARK: Revision

    @Test
    func loadReloadAndUnloadEachBumpTheRevision() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)
        let initial = store.revision

        await store.loadPlaylist(playlist)
        let afterLoad = store.revision
        #expect(afterLoad != initial)
        #expect(store.channels.count == 6)
        #expect(store.loadError == nil)

        // Nothing changed in the database: the lists are equal, the revision is not.
        // That is the point of it: observers do not have to compare the lists.
        let channelsBefore = store.channels
        await store.reloadIfActive(playlist: playlist)
        let afterReload = store.revision
        #expect(afterReload != afterLoad)
        #expect(store.channels == channelsBefore)

        store.unload()
        #expect(store.revision != afterReload)
        #expect(store.channels.isEmpty)
        #expect(store.groupNames.isEmpty)
        #expect(store.channel(id: id("http://host/live/1.ts")) == nil)
    }

    @Test
    func reloadOfAnInactivePlaylistChangesNothing() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)
        let initial = store.revision

        await store.reloadIfActive(playlist: playlist)

        #expect(store.revision == initial)
        #expect(store.channels.isEmpty)
    }

    @Test
    func switchingPlaylistDropsARefreshError() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)
        await store.loadPlaylist(playlist)
        store.refreshError = "download failed"

        // Loading the same playlist again keeps it: the failed refresh is still
        // the latest news about this list.
        await store.loadPlaylist(playlist)
        #expect(store.refreshError == "download failed")

        let other = Playlist(name: "Other", serverURL: "http://other/list.m3u", type: .m3u)
        try await M3UImporter.replace(playlist: other, channels: [], epgURL: nil, in: database)
        await store.loadPlaylist(other)
        #expect(store.refreshError == nil)
        #expect(store.activePlaylistId == other.id)
        #expect(store.channels.isEmpty)
    }

    // MARK: Loading flag

    /// A reload that arrives while the first load is still reading (the adult
    /// filter toggled in settings) supersedes it. The flag belongs to whichever
    /// request is the latest, so it must not drop while there is still nothing to
    /// show: the channels screen would put up its empty state.
    @Test
    func loadingFlagStaysUpWhenAReloadSupersedesTheFirstLoad() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)
        let playlist = self.playlist

        var reload: Task<Void, Never>?
        var droppedWhileEmpty = 0
        // `@Published` emits before the value is stored. The first `true` comes
        // from `loadPlaylist` ahead of its first suspension, so the reload queued
        // here runs while that load is waiting for its read.
        let observation = store.$isLoading.dropFirst().sink { isLoading in
            if isLoading {
                guard reload == nil else { return }
                reload = Task { @MainActor in await store.reloadIfActive(playlist: playlist) }
            } else if store.channels.isEmpty {
                droppedWhileEmpty += 1
            }
        }
        defer { observation.cancel() }

        await store.loadPlaylist(playlist)
        let queued = try #require(reload)
        await queued.value

        #expect(droppedWhileEmpty == 0)
        #expect(!store.isLoading)
        #expect(store.channels.count == 6)
        #expect(store.loadError == nil)
    }

    @Test
    func loadingFlagIsDownAfterEveryKindOfRequest() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)

        await store.loadPlaylist(playlist)
        #expect(!store.isLoading)

        await store.reloadIfActive(playlist: playlist)
        #expect(!store.isLoading)

        // An empty playlist: the reload is the only request and owns the flag.
        let empty = Playlist(name: "Empty", serverURL: "http://empty/list.m3u", type: .m3u)
        try await M3UImporter.replace(playlist: empty, channels: [], epgURL: nil, in: database)
        await store.loadPlaylist(empty)
        await store.reloadIfActive(playlist: empty)
        #expect(!store.isLoading)
        #expect(store.channels.isEmpty)

        store.unload()
        #expect(!store.isLoading)
    }

    // MARK: Lookup

    @Test
    func channelLookupReturnsTheLoadedRow() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)
        await store.loadPlaylist(playlist)

        for channel in store.channels {
            #expect(store.channel(id: channel.id) == channel)
        }
        #expect(store.channel(id: id("http://host/live/3.ts"))?.name == "News Two")
        #expect(store.channel(id: "not-an-id") == nil)
    }

    @Test
    func groupsAndQueuesUseTheCanonicalKey() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)
        await store.loadPlaylist(playlist)

        // Order of first appearance; titles are trimmed, missing and blank ones
        // share the ungrouped key.
        #expect(store.groupNames == ["News", M3UContentStore.ungroupedLabel, "Adult", "Mixed"])

        let newsTwo = try #require(store.channel(id: id("http://host/live/3.ts")))
        #expect(M3UContentStore.groupKey(for: newsTwo) == "News")
        #expect(store.queue(for: newsTwo).map(\.name) == ["News One", "News Two"])

        let loose = try #require(store.channel(id: id("http://host/live/2.ts")))
        #expect(M3UContentStore.groupKey(for: loose) == M3UContentStore.ungroupedLabel)
        #expect(store.queue(for: loose).map(\.name) == ["Loose", "Blank group"])

        // A channel the store does not hold still gets a queue to play from.
        let stranger = DBM3UChannel(id: "x", playlistId: playlist.id, name: "Stranger",
                                    url: "http://host/x.ts", groupTitle: "Elsewhere")
        #expect(store.queue(for: stranger) == [stranger])
    }

    // MARK: Adult filter

    @Test
    func adultFilterHidesChannelsByNameAndByGroup() async throws {
        let database = try await seededDatabase()
        try await database.updatePlaylist(id: playlist.id) { $0.filterAdultContent = true }
        let store = M3UContentStore(database: database)

        var filtered = playlist
        filtered.filterAdultContent = true
        await store.loadPlaylist(filtered)

        #expect(store.channels.map(\.name) == ["News One", "Loose", "News Two", "Blank group"])
        #expect(store.groupNames == ["News", M3UContentStore.ungroupedLabel])
        // The lookup covers the visible list only, and its positions follow it.
        #expect(store.channel(id: id("http://host/live/4.ts")) == nil)
        #expect(store.channel(id: id("http://host/live/5.ts")) == nil)
        #expect(store.channel(id: id("http://host/live/6.ts"))?.name == "Blank group")
    }

    /// A refresh passes the playlist value its screen was opened with. The filter
    /// switched on since then lives in the row and must keep applying.
    @Test
    func filterSettingIsTakenFromTheStoredRow() async throws {
        let database = try await seededDatabase()
        let store = M3UContentStore(database: database)
        let staleCopy = playlist
        await store.loadPlaylist(staleCopy)
        #expect(store.channels.count == 6)

        try await database.updatePlaylist(id: playlist.id) { $0.filterAdultContent = true }
        await store.reloadIfActive(playlist: staleCopy)
        #expect(store.channels.count == 4)

        try await database.updatePlaylist(id: playlist.id) { $0.filterAdultContent = false }
        await store.loadPlaylist(staleCopy)
        #expect(store.channels.count == 6)
    }

    // MARK: Live / VOD

    @Test
    func liveClassificationTreatsUnparseableURLsAsLive() {
        func channel(_ url: String) -> DBM3UChannel {
            DBM3UChannel(id: url, playlistId: playlist.id, name: url, url: url)
        }
        let live = channel("http://host/live/user/pass/1.ts")
        let noExtension = channel("http://host/user/pass/1")
        let film = channel("http://host/movie/user/pass/9.mkv")
        let file = channel("http://host/files/clip.mp4")
        let empty = channel("")

        #expect(M3UContentStore.isLive(live))
        #expect(M3UContentStore.isLive(noExtension))
        #expect(!M3UContentStore.isLive(film))
        #expect(!M3UContentStore.isLive(file))
        #expect(M3UContentStore.isLive(empty))
        #expect(M3UContentStore.liveChannels(in: [film, live, empty, file, noExtension])
                == [live, empty, noExtension])
    }
}
