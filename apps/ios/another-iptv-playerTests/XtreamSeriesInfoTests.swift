import Foundation
import Testing
@testable import another_iptv_player

@Suite("XtreamSeriesInfo season resolution")
struct XtreamSeriesInfoTests {

    private func decode(_ json: String) throws -> XtreamSeriesInfoResponse {
        try JSONDecoder().decode(
            XtreamSeriesInfoResponse.self,
            from: json.data(using: .utf8)!
        )
    }

    private func episodes(_ ids: [String]) -> String {
        ids.map { #"{"id": "\#($0)", "episode_num": 1}"# }.joined(separator: ",")
    }

    // MARK: - episodesBySeasonNumber

    @Test
    func groupsEpisodesByNumericSeason() throws {
        let info = try decode(#"""
        {"seasons": [], "episodes": {"1": [\#(episodes(["a"]))], "2": [\#(episodes(["b"]))]}}
        """#)

        #expect(info.episodesBySeasonNumber[1]?.count == 1)
        #expect(info.episodesBySeasonNumber[2]?.count == 1)
    }

    @Test
    func zeroPaddedKeysNormalizeToSameSeason() throws {
        let info = try decode(#"""
        {"seasons": [], "episodes": {"01": [\#(episodes(["a"]))]}}
        """#)

        #expect(info.episodesBySeasonNumber[1]?.count == 1)
    }

    @Test
    func nonNumericKeysAreIgnored() throws {
        let info = try decode(#"""
        {"seasons": [], "episodes": {"specials": [\#(episodes(["a"]))]}}
        """#)

        #expect(info.episodesBySeasonNumber.isEmpty)
    }

    // MARK: - resolvedSeasons

    @Test
    func seasonsArrayIsPreservedWithItsMetadata() throws {
        let info = try decode(#"""
        {"seasons": [{"season_number": 1, "name": "First"}],
         "episodes": {"1": [\#(episodes(["a"]))]}}
        """#)

        let resolved = info.resolvedSeasons
        #expect(resolved.count == 1)
        #expect(resolved[0].number == 1)
        #expect(resolved[0].metadata?.name == "First")
    }

    /// The bug from PR #107: the panel declares season 1, but keys its episodes
    /// under "2". The uncovered bucket used to be dropped entirely.
    @Test
    func episodeBucketWithoutMatchingSeasonStillYieldsASeason() throws {
        let info = try decode(#"""
        {"seasons": [{"season_number": 1, "name": "First"}],
         "episodes": {"2": [\#(episodes(["a", "b"]))]}}
        """#)

        let resolved = info.resolvedSeasons
        #expect(resolved.map(\.number) == [1, 2])
        #expect(resolved[1].metadata == nil)
        #expect(info.episodesBySeasonNumber[2]?.count == 2)
    }

    @Test
    func onlySeasonTwoExistsAndIsFullyRecovered() throws {
        let info = try decode(#"""
        {"seasons": [], "episodes": {"2": [\#(episodes(["a", "b", "c"]))]}}
        """#)

        let resolved = info.resolvedSeasons
        #expect(resolved.map(\.number) == [2])
        #expect(info.episodesBySeasonNumber[2]?.count == 3)
    }

    @Test
    func seasonsWithoutNumbersAreSkipped() throws {
        let info = try decode(#"""
        {"seasons": [{"name": "Unnumbered"}], "episodes": {"1": [\#(episodes(["a"]))]}}
        """#)

        #expect(info.resolvedSeasons.map(\.number) == [1])
    }

    @Test
    func syntheticSeasonsAreOrderedNumerically() throws {
        let info = try decode(#"""
        {"seasons": [], "episodes": {"10": [\#(episodes(["a"]))], "2": [\#(episodes(["b"]))]}}
        """#)

        #expect(info.resolvedSeasons.map(\.number) == [2, 10])
    }

    @Test
    func missingEpisodesDictionaryYieldsDeclaredSeasonsOnly() throws {
        let info = try decode(#"{"seasons": [{"season_number": 1}]}"#)

        #expect(info.resolvedSeasons.map(\.number) == [1])
        #expect(info.episodesBySeasonNumber.isEmpty)
    }
}
