import Combine
import Foundation
import GRDB
import GRDBQuery
import Nuke
import SwiftUI
import Testing
@testable import another_iptv_player

/// The pieces of the detail screens that can be checked without a screen: the text
/// formatters, the request of the hero poster, and the two database behaviours the
/// favourite star and the download button rely on.
@Suite("Detail components")
struct DetailComponentsTests {

    private let english = Locale(identifier: "en")
    private let turkish = Locale(identifier: "tr")

    // MARK: Runtime

    @Test
    func bareMinutesAreFormattedInTheGivenLanguage() throws {
        let short = try #require(DetailFormatting.seriesRuntime("45", locale: english))
        #expect(short.contains("45"))
        #expect(short.contains("min"))
        #expect(!short.contains("dk"))

        let long = try #require(DetailFormatting.seriesRuntime("105", locale: english))
        #expect(long.contains("1"))
        #expect(long.contains("45"))
        #expect(!long.contains("105"))
        #expect(!long.contains("dk"))

        let turkishShort = try #require(DetailFormatting.seriesRuntime("45", locale: turkish))
        #expect(turkishShort.contains("45"))
        #expect(turkishShort.contains("dk"))
    }

    @Test
    func fullHoursCarryNoMinutes() throws {
        let twoHours = try #require(DetailFormatting.seriesRuntime("120", locale: english))
        #expect(twoHours.contains("2"))
        #expect(!twoHours.contains("0 min"))
    }

    @Test
    func runtimeTextOfThePanelIsPassedThrough() {
        #expect(DetailFormatting.seriesRuntime("45 min", locale: english) == "45 min")
        #expect(DetailFormatting.seriesRuntime("1h 20m", locale: turkish) == "1h 20m")
        #expect(DetailFormatting.seriesRuntime("  50m ", locale: english) == "50m")
        #expect(DetailFormatting.seriesRuntime("N/A", locale: english) == "N/A")
    }

    @Test
    func missingOrZeroRuntimeIsNoRuntime() {
        #expect(DetailFormatting.seriesRuntime(nil, locale: english) == nil)
        #expect(DetailFormatting.seriesRuntime("", locale: english) == nil)
        #expect(DetailFormatting.seriesRuntime("   ", locale: english) == nil)
        #expect(DetailFormatting.seriesRuntime("0", locale: english) == nil)
        #expect(DetailFormatting.seriesRuntime("00", locale: english) == nil)
        #expect(DetailFormatting.seriesRuntime("-5", locale: english) == nil)
    }

    @Test
    func absurdMinuteCountsAreNotFormatted() {
        // Shown as sent, and never multiplied into an overflow.
        #expect(DetailFormatting.seriesRuntime("99999", locale: english) == "99999")
        #expect(DetailFormatting.seriesRuntime("9223372036854775807", locale: english) == "9223372036854775807")
    }

    // MARK: Percentage

    @Test
    func percentageFollowsTheLanguage() {
        #expect(DetailFormatting.percent(0.45, locale: english) == "45%")
        #expect(DetailFormatting.percent(0.45, locale: turkish) == "%45")
    }

    @Test
    func percentageIsTruncatedSoARunningDownloadNeverReadsComplete() {
        #expect(DetailFormatting.percent(0.996, locale: english) == "99%")
        #expect(DetailFormatting.percent(0.9999, locale: english) == "99%")
        #expect(DetailFormatting.percent(1, locale: english) == "100%")
        #expect(DetailFormatting.percent(0.004, locale: english) == "0%")
    }

    @Test
    func percentageStaysInsideItsRange() {
        #expect(DetailFormatting.percent(-0.5, locale: english) == "0%")
        #expect(DetailFormatting.percent(3, locale: english) == "100%")
        #expect(DetailFormatting.percent(.nan, locale: english) == "0%")
        #expect(DetailFormatting.percent(.infinity, locale: english) == "0%")
    }

    // MARK: Playback position

    @Test
    func positionKeepsItsShape() {
        #expect(DetailFormatting.formatMs(754_000, locale: english) == "12:34")
        #expect(DetailFormatting.formatMs(3_723_000, locale: english) == "1:02:03")
        #expect(DetailFormatting.formatMs(5_000, locale: english) == "0:05")
        #expect(DetailFormatting.formatMs(0, locale: english) == "0:00")
        #expect(DetailFormatting.formatMs(-1, locale: english) == "0:00")
        #expect(DetailFormatting.formatMs(3_600_000, locale: english) == "1:00:00")
        #expect(DetailFormatting.formatMs(3_599_000, locale: turkish) == "59:59")
    }

    @Test
    func positionIsTruncatedToWholeSeconds() {
        #expect(DetailFormatting.formatMs(5_999, locale: english) == "0:05")
        #expect(DetailFormatting.formatMs(3_599_999, locale: english) == "59:59")
    }

    // MARK: Hero poster

    /// The hero poster is in the first frame of a push only because its request is the one
    /// the shelf and grid cards already made; the viewer opens on the poster for the same
    /// reason.
    @Test
    func heroPosterSharesItsCacheEntryWithThePosterCards() {
        let url = URL(string: "https://img.example.com/posters/1.jpg")!
        let cache = ImagePipeline.shared.cache
        for window in [CGSize(width: 402, height: 874), CGSize(width: 834, height: 1194), CGSize(width: 1366, height: 1024)] {
            let metrics = PosterMetrics(windowSize: window)
            let hero = DetailHero.posterRequest(url: url, metrics: metrics)
            for profile in [ImageLoadProfile.shelf, .grid] {
                let card = CachedImage.request(
                    url: url,
                    width: metrics.categoryGridPosterWidth,
                    height: metrics.categoryGridPosterHeight,
                    contentMode: .fill,
                    loadProfile: profile
                )
                #expect(cache.makeImageCacheKey(for: hero) == cache.makeImageCacheKey(for: card), "\(window) \(profile)")
                #expect(hero.thumbnail == card.thumbnail, "\(window) \(profile)")
            }
            // Shelves use their own metrics; the two must stay the same size for the
            // shelf card to be the same entry.
            #expect(metrics.shelfPosterWidth == metrics.categoryGridPosterWidth)
            #expect(metrics.shelfPosterHeight == metrics.categoryGridPosterHeight)
        }
    }

    // MARK: Favourite write

    /// What the star's write relies on: the favourite table has a composite primary key,
    /// and writing "on" twice must neither throw nor leave two rows.
    @Test
    func writingTheSameFavouriteTwiceKeepsOneRow() throws {
        let playlist = Playlist(name: "Detail", serverURL: "http://host:8080")
        let database = AppDatabase.empty()
        let pid = playlist.id
        try database.writeSync { db in
            try playlist.insert(db)
            try DBVODStream(streamId: 5, name: "Film", playlistId: pid).insert(db)
            try DBFavorite(streamId: 5, playlistId: pid, type: "vod").insert(db, onConflict: .ignore)
            try DBFavorite(streamId: 5, playlistId: pid, type: "vod").insert(db, onConflict: .ignore)
        }
        let count = try database.writeSync { db in
            try DBFavorite.filter(Column("streamId") == 5 && Column("playlistId") == pid).fetchCount(db)
        }
        #expect(count == 1)

        // Removing twice is as harmless.
        let remaining = try database.writeSync { db -> Int in
            for _ in 0..<2 {
                try DBFavorite
                    .filter(Column("streamId") == 5 && Column("playlistId") == pid && Column("type") == "vod")
                    .deleteAll(db)
            }
            return try DBFavorite.fetchCount(db)
        }
        #expect(remaining == 0)
    }

    // MARK: Download row observation

    private func download(id: String, playlistId: UUID, status: DownloadStatus) -> DBDownloadedItem {
        DBDownloadedItem(
            id: id,
            playlistId: playlistId,
            streamId: id,
            type: "vod",
            title: "Film \(id)",
            secondaryTitle: nil,
            imageURL: nil,
            remoteURL: "http://host:8080/movie/\(id).mkv",
            localPath: "Downloads/\(id).mkv",
            containerExtension: "mkv",
            status: status.rawValue,
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    /// Every write to the downloads table re-runs the fetch of every mounted download
    /// button. Only the button whose row changed may be told.
    @Test
    func downloadRowObservationIgnoresWritesToOtherRows() async throws {
        let playlist = Playlist(name: "Detail", serverURL: "http://host:8080")
        let database = AppDatabase.empty()
        let pid = playlist.id
        let mine = download(id: "vod.1", playlistId: pid, status: .queued)
        try database.writeSync { db in
            try playlist.insert(db)
            try mine.insert(db)
        }

        var received: [DownloadStatus?] = []
        let cancellable = DownloadedItemByIDRequest(id: mine.id)
            .publisher(in: database)
            .sink { received.append($0?.downloadStatus) }
        defer { cancellable.cancel() }

        func wait(until condition: () -> Bool) async throws {
            var waits = 0
            while !condition(), waits < 1_000 {
                try await Task.sleep(nanoseconds: 5_000_000)
                waits += 1
            }
        }

        try await wait { received.count == 1 }
        #expect(received == [.queued])

        // Another item's row comes and changes: nothing for this observer.
        var other = download(id: "vod.2", playlistId: pid, status: .queued)
        try await database.write { db in try other.insert(db) }
        try await Task.sleep(nanoseconds: 50_000_000)
        other.status = DownloadStatus.downloading.rawValue
        let changedOther = other
        try await database.write { db in try changedOther.update(db) }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Its own row changes: exactly one more value.
        var changedMine = mine
        changedMine.status = DownloadStatus.downloading.rawValue
        let downloading = changedMine
        try await database.write { db in try downloading.update(db) }
        try await wait { received.last == .some(.downloading) }
        #expect(received == [.queued, .downloading])
    }
}
