import Foundation
import GRDB
import Testing
@testable import another_iptv_player

@Suite("Detail metadata persistence")
struct DetailMetadataTests {
    @Test func movieWritePreservesRefreshedCatalogAndOtherPlaylist() throws {
        let database = AppDatabase.empty()
        let owner = Playlist(name: "Owner", serverURL: "https://example.com")
        let other = Playlist(name: "Other", serverURL: "https://other.invalid")
        let response = try JSONDecoder().decode(XtreamVODInfoResponse.self, from: Data(#"{"info":{"plot":"Received plot","rating":"8.2"}}"#.utf8))
        try database.writeSync { db in
            for playlist in [owner, other] {
                try playlist.insert(db)
                try DBVODStream(streamId: 7, name: "Refreshed name", categoryId: "fresh-category", containerExtension: "mkv", playlistId: playlist.id).insert(db)
            }
            #expect(try DetailMetadata.storeMovie(response, streamId: 7, playlistId: owner.id, db: db))
            let row = try #require(try DBVODStream.filter(Column("playlistId") == owner.id).fetchOne(db))
            #expect(row.name == "Refreshed name")
            #expect(row.categoryId == "fresh-category")
            #expect(row.containerExtension == "mkv")
            #expect(row.plot == "Received plot")
            #expect(row.rating5Based == 4.1)
            #expect(row.metadataLoaded)
            let untouched = try #require(try DBVODStream.filter(Column("playlistId") == other.id).fetchOne(db))
            #expect(!untouched.metadataLoaded)
            #expect(untouched.plot == nil)
            #expect(try !DetailMetadata.storeMovie(response, streamId: 999, playlistId: owner.id, db: db))
        }
    }

    @Test func optimisticSeriesHeaderDoesNotPretendEpisodesWereStored() throws {
        let base = DBSeries(seriesId: 7, name: "Show", playlistId: UUID())
        let response = try JSONDecoder().decode(XtreamSeriesInfoResponse.self, from: Data(#"{"info":{"plot":"New synopsis"},"episodes":{}}"#.utf8))
        let preview = DetailMetadata.series(base, response: response)
        #expect(preview.plot == "New synopsis")
        #expect(!preview.seasonsLoaded)
        #expect(preview.name == base.name)
    }

    @Test func absentInfoPreservesExistingMovieDetails() throws {
        var base = DBVODStream(streamId: 7, name: "Movie", playlistId: UUID())
        base.plot = "Keep this"
        let response = try JSONDecoder().decode(XtreamVODInfoResponse.self, from: Data("{}".utf8))
        let preview = DetailMetadata.movie(base, response: response)
        #expect(preview.plot == "Keep this")
        #expect(preview.metadataLoaded)
    }
}
