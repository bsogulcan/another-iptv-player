import Foundation
import GRDB
import Testing
@testable import another_iptv_player

/// `M3UImporter.replace` as an upsert of the playlist row, and the channel ids it
/// writes.
@Suite("M3U importer")
struct M3UImporterTests {

    private func channel(_ name: String, url: String, group: String? = nil) -> ParsedM3UChannel {
        ParsedM3UChannel(name: name, url: url, groupTitle: group)
    }

    private func storedPlaylist(_ id: UUID, in database: AppDatabase) async throws -> Playlist? {
        try await database.read { db in try Playlist.fetchOne(db, key: id) }
    }

    private func storedChannels(_ playlistId: UUID, in database: AppDatabase) async throws -> [DBM3UChannel] {
        try await database.read { db in
            try DBM3UChannel
                .filter(Column("playlistId") == playlistId)
                .order(Column("sortIndex"))
                .fetchAll(db)
        }
    }

    // MARK: Playlist row

    /// The refresh paths pass the playlist value their screen was opened with.
    /// Whatever settings saved since then must survive the import.
    @Test
    func refreshFromAStaleCopyKeepsColumnsTheImportDoesNotOwn() async throws {
        let database = AppDatabase.empty()
        let original = Playlist(name: "Lists", serverURL: "http://host/list.m3u", type: .m3u,
                                m3uEpgURL: "http://host/old-guide.xml")
        try await M3UImporter.replace(
            playlist: original,
            channels: [channel("One", url: "http://host/1.ts")],
            epgURL: original.m3uEpgURL,
            in: database
        )
        let staleCopy = original

        try await database.updatePlaylist(id: original.id) {
            $0.filterAdultContent = true
            $0.epgURLOverride = "https://guide.example/manual.xml"
            $0.epgEnabled = false
            $0.serverTimezone = "Europe/Berlin"
            $0.timeshiftStyle = "path-no-m3u8"
        }
        let beforeRefresh = try await storedPlaylist(original.id, in: database)

        try await M3UImporter.replace(
            playlist: staleCopy,
            channels: [channel("One", url: "http://host/1.ts"), channel("Two", url: "http://host/2.ts")],
            epgURL: "http://host/new-guide.xml",
            in: database
        )

        let row = try await storedPlaylist(original.id, in: database)
        #expect(row?.filterAdultContent == true)
        #expect(row?.epgURLOverride == "https://guide.example/manual.xml")
        #expect(row?.epgEnabled == false)
        #expect(row?.serverTimezone == "Europe/Berlin")
        #expect(row?.timeshiftStyle == "path-no-m3u8")
        #expect(row?.createdAt == beforeRefresh?.createdAt)
        // What the import owns is written.
        #expect(row?.m3uEpgURL == "http://host/new-guide.xml")
        #expect(row?.name == "Lists")
        #expect(row?.serverURL == "http://host/list.m3u")
        #expect(row?.kind == .m3u)

        let channels = try await storedChannels(original.id, in: database)
        #expect(channels.map(\.name) == ["One", "Two"])
    }

    @Test
    func importOfAnUnknownPlaylistInsertsItAsGiven() async throws {
        let database = AppDatabase.empty()
        let playlist = Playlist(name: "New", serverURL: "http://host/new.m3u",
                                filterAdultContent: true, type: .m3u)

        try await M3UImporter.replace(
            playlist: playlist,
            channels: [channel("One", url: "http://host/1.ts", group: "News")],
            epgURL: "http://host/guide.xml",
            in: database
        )

        let row = try await storedPlaylist(playlist.id, in: database)
        #expect(row?.name == "New")
        #expect(row?.serverURL == "http://host/new.m3u")
        #expect(row?.kind == .m3u)
        #expect(row?.filterAdultContent == true)
        #expect(row?.m3uEpgURL == "http://host/guide.xml")
        #expect(row?.epgEnabled == true)

        let channels = try await storedChannels(playlist.id, in: database)
        #expect(channels.count == 1)
        #expect(channels.first?.groupTitle == "News")
        #expect(channels.first?.playlistId == playlist.id)
    }

    /// The edit sheet rebuilds a `Playlist` with the same id and default settings.
    /// Name and URL come from it; the settings stay as stored.
    @Test
    func editWithANewNameAndURLRenamesWithoutResettingSettings() async throws {
        let database = AppDatabase.empty()
        let original = Playlist(name: "Old name", serverURL: "http://old/list.m3u", type: .m3u)
        try await M3UImporter.replace(playlist: original, channels: [channel("One", url: "http://old/1.ts")],
                                      epgURL: nil, in: database)
        try await database.updatePlaylist(id: original.id) {
            $0.epgURLOverride = "https://guide.example/manual.xml"
            $0.epgEnabled = false
        }

        let edited = Playlist(id: original.id, name: "New name", serverURL: "http://new/list.m3u", type: .m3u)
        try await M3UImporter.replace(playlist: edited, channels: [channel("Uno", url: "http://new/1.ts")],
                                      epgURL: nil, in: database)

        let row = try await storedPlaylist(original.id, in: database)
        #expect(row?.name == "New name")
        #expect(row?.serverURL == "http://new/list.m3u")
        #expect(row?.epgURLOverride == "https://guide.example/manual.xml")
        #expect(row?.epgEnabled == false)
        let count = try await database.read { db in try Playlist.fetchCount(db) }
        #expect(count == 1)
    }

    @Test
    func localFileImportClearsTheSourceURL() async throws {
        let database = AppDatabase.empty()
        let playlist = Playlist(name: "Lists", serverURL: "http://host/list.m3u", type: .m3u)
        try await M3UImporter.replace(playlist: playlist, channels: [channel("One", url: "http://host/1.ts")],
                                      epgURL: nil, in: database)

        try await M3UImporter.replace(playlist: playlist, channels: [channel("One", url: "http://host/1.ts")],
                                      epgURL: nil, clearServerURL: true, in: database)

        let row = try await storedPlaylist(playlist.id, in: database)
        #expect(row?.serverURL == "")
    }

    // MARK: Channel rows

    @Test
    func reimportReplacesTheChannelsAndKeepsTheirIds() async throws {
        let database = AppDatabase.empty()
        let playlist = Playlist(name: "Lists", serverURL: "http://host/list.m3u", type: .m3u)
        try await M3UImporter.replace(
            playlist: playlist,
            channels: [
                channel("One", url: "http://host/1.ts"),
                channel("Two", url: "http://host/2.ts"),
                channel("Three", url: "http://host/3.ts")
            ],
            epgURL: nil, in: database
        )
        let first = try await storedChannels(playlist.id, in: database)

        try await M3UImporter.replace(
            playlist: playlist,
            channels: [
                channel("Three renamed", url: "http://host/3.ts"),
                channel("One", url: "http://host/1.ts")
            ],
            epgURL: nil, in: database
        )
        let second = try await storedChannels(playlist.id, in: database)

        #expect(first.count == 3)
        #expect(second.map(\.name) == ["Three renamed", "One"])
        #expect(second.map(\.sortIndex) == [0, 1])
        // Favourites and history are keyed by the id: same URL, same id.
        #expect(second[0].id == first[2].id)
        #expect(second[1].id == first[0].id)
    }

    /// One URL listed under several groups stays several rows.
    @Test
    func repeatedURLsAreKeptAsSeparateRows() async throws {
        let database = AppDatabase.empty()
        let playlist = Playlist(name: "Lists", serverURL: "http://host/list.m3u", type: .m3u)

        try await M3UImporter.replace(
            playlist: playlist,
            channels: [
                channel("News", url: "http://host/1.ts", group: "All"),
                channel("News", url: "http://host/1.ts", group: "UK"),
                channel("News", url: " http://host/1.ts ", group: "Europe")
            ],
            epgURL: nil, in: database
        )

        let rows = try await storedChannels(playlist.id, in: database)
        #expect(rows.map(\.groupTitle) == ["All", "UK", "Europe"])
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(rows[0].id == M3UImporter.stableChannelID(playlistId: playlist.id, url: "http://host/1.ts"))
        #expect(rows[1].id == M3UImporter.stableChannelID(playlistId: playlist.id, url: "http://host/1.ts",
                                                          occurrence: 1))
        #expect(rows[2].id == M3UImporter.stableChannelID(playlistId: playlist.id, url: "http://host/1.ts",
                                                          occurrence: 2))
    }

    /// The rows are built before the write transaction opens. What reaches the
    /// database must be those rows, unchanged and in playlist order.
    @Test
    func theStoredRowsAreTheOnesBuiltBeforeTheWrite() async throws {
        let database = AppDatabase.empty()
        let playlist = Playlist(name: "Lists", serverURL: "http://host/list.m3u", type: .m3u)
        let channels = [
            ParsedM3UChannel(name: "One", url: "http://host/1.ts", tvgId: "one.tv", tvgName: "One HD",
                             tvgLogo: "http://host/1.png", tvgCountry: "TR", groupTitle: "News",
                             userAgent: "UA/1", catchup: "default", catchupSource: "http://host/c", catchupDays: 3),
            channel("One again", url: "http://host/1.ts", group: "All"),
            channel("No URL", url: ""),
            channel("Two", url: " http://host/2.ts ")
        ]

        let built = try M3UImporter.makeRows(playlistId: playlist.id, channels: channels)
        try await M3UImporter.replace(playlist: playlist, channels: channels, epgURL: nil, in: database)

        #expect(try await storedChannels(playlist.id, in: database) == built)
        #expect(built.map(\.sortIndex) == [0, 1, 2, 3])
        #expect(built.map(\.id) == [
            M3UImporter.stableChannelID(playlistId: playlist.id, url: "http://host/1.ts"),
            M3UImporter.stableChannelID(playlistId: playlist.id, url: "http://host/1.ts", occurrence: 1),
            M3UImporter.stableChannelID(playlistId: playlist.id, url: "", fallbackIndex: 2),
            M3UImporter.stableChannelID(playlistId: playlist.id, url: "http://host/2.ts")
        ])
        // The URL itself is stored as written; only the id key is trimmed.
        #expect(built[3].url == " http://host/2.ts ")
        #expect(built[0].tvgId == "one.tv")
        #expect(built[0].catchupDays == 3)
        #expect(built.allSatisfy { $0.playlistId == playlist.id })
    }

    // MARK: Ids

    /// Recorded SHA-256 values of the id keys. Stored favourites and watch history
    /// reference these ids, so the encoding must never drift.
    @Test
    func channelIdsAreTheLowercaseHexDigestOfTheirKey() throws {
        let playlistId = try #require(UUID(uuidString: "A1B2C3D4-0000-4000-8000-00000000ABCD"))

        #expect(M3UImporter.stableChannelID(playlistId: playlistId, url: "http://example.com/live/1.ts")
                == "2405e4bb4967268ce6262ebb63d09990456a067dca3260bf70e72a57f2bb8ba3")
        // Surrounding whitespace is not part of the key.
        #expect(M3UImporter.stableChannelID(playlistId: playlistId, url: "  http://example.com/live/1.ts\n")
                == "2405e4bb4967268ce6262ebb63d09990456a067dca3260bf70e72a57f2bb8ba3")
        #expect(M3UImporter.stableChannelID(playlistId: playlistId, url: "http://example.com/live/1.ts",
                                            occurrence: 2)
                == "bffb0899047413679a038658b01bce8e93dab88ffad136e4cb0dc762aeed4ec2")
        // No URL: the list position stands in.
        #expect(M3UImporter.stableChannelID(playlistId: playlistId, url: "", fallbackIndex: 7)
                == "4194089140286b3497c68a0414518281630bacdfd59bde3999e959b8af65529c")
        #expect(M3UImporter.stableChannelID(playlistId: playlistId, url: "   ", fallbackIndex: 7, occurrence: 1)
                == "23792fe71baa01507257c312d3d5f7c1d4b9380afc37b687870528f1832608af")
        #expect(M3UImporter.stableChannelID(playlistId: playlistId,
                                            url: "http://example.com/canl\u{0131}/\u{015F}.ts")
                == "dfe47939e4498c5cf52b03cd8f9e2f836e9fb87061ab80782f51f180543b11f7")
    }

    @Test
    func channelIdsDifferByPlaylist() {
        let url = "http://example.com/live/1.ts"
        let one = M3UImporter.stableChannelID(playlistId: UUID(), url: url)
        let other = M3UImporter.stableChannelID(playlistId: UUID(), url: url)
        #expect(one != other)
        #expect(one.count == 64)
        #expect(one.allSatisfy { "0123456789abcdef".contains($0) })
    }
}


extension M3UImporterTests {
    @Test
    func cancelledImportDoesNotCreateAPlaylist() async throws {
        let database = AppDatabase.empty()
        let playlist = EPGTestSupport.m3uPlaylist()
        let channels = [ParsedM3UChannel(name: "News", url: "https://example.invalid/news.ts")]
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await M3UImporter.replace(playlist: playlist, channels: channels, epgURL: nil, in: database)
        }
        do {
            try await task.value
            Issue.record("Cancelled import unexpectedly succeeded")
        } catch is CancellationError {
            // No rows should be published after the user cancels the import.
        }
        let stored = try await database.read { db in try Playlist.fetchOne(db, key: playlist.id) }
        #expect(stored == nil)
    }
}
