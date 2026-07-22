/**
 * Ported 1:1 from apps/ios/another-iptv-playerTests/XtreamSeriesInfoTests.swift
 * (same case names, same JSON inputs, same expected values), plus fixture
 * round-trips for the shared Xtream samples.
 */

import { describe, expect, it } from "vitest";
import {
  episodesBySeasonNumber,
  parseXtreamAuthResponse,
  parseXtreamCategoryList,
  parseXtreamLiveStreamList,
  parseXtreamSeriesInfo,
  parseXtreamSeriesList,
  parseXtreamVodInfo,
  parseXtreamVodStreamList,
  resolvedSeasons,
} from "../src/models/xtream";

import authSuccess from "../../../shared/fixtures/xtream/auth_success.json";
import liveCategories from "../../../shared/fixtures/xtream/get_live_categories.json";
import liveStreams from "../../../shared/fixtures/xtream/get_live_streams.json";
import vodStreams from "../../../shared/fixtures/xtream/get_vod_streams.json";
import seriesList from "../../../shared/fixtures/xtream/get_series_list.json";
import vodInfo from "../../../shared/fixtures/xtream/get_vod_info.json";
import seriesInfoBasic from "../../../shared/fixtures/xtream/get_series_info_basic.json";
import seriesInfoStringKeys from "../../../shared/fixtures/xtream/get_series_info_string_season_keys.json";
import seriesInfoUndeclared from "../../../shared/fixtures/xtream/get_series_info_undeclared_seasons.json";
import mixedBadElements from "../../../shared/fixtures/xtream/mixed_bad_elements.json";

function decode(json: string) {
  return parseXtreamSeriesInfo(JSON.parse(json));
}

function episodes(ids: string[]): string {
  return ids.map((id) => `{"id": "${id}", "episode_num": 1}`).join(",");
}

describe("XtreamSeriesInfo season resolution", () => {
  // MARK: - episodesBySeasonNumber

  it("groupsEpisodesByNumericSeason", () => {
    const info = decode(
      `{"seasons": [], "episodes": {"1": [${episodes(["a"])}], "2": [${episodes(["b"])}]}}`,
    );

    expect(episodesBySeasonNumber(info).get(1)?.length).toBe(1);
    expect(episodesBySeasonNumber(info).get(2)?.length).toBe(1);
  });

  it("zeroPaddedKeysNormalizeToSameSeason", () => {
    const info = decode(
      `{"seasons": [], "episodes": {"01": [${episodes(["a"])}]}}`,
    );

    expect(episodesBySeasonNumber(info).get(1)?.length).toBe(1);
  });

  it("nonNumericKeysAreIgnored", () => {
    const info = decode(
      `{"seasons": [], "episodes": {"specials": [${episodes(["a"])}]}}`,
    );

    expect(episodesBySeasonNumber(info).size).toBe(0);
  });

  // MARK: - resolvedSeasons

  it("seasonsArrayIsPreservedWithItsMetadata", () => {
    const info = decode(
      `{"seasons": [{"season_number": 1, "name": "First"}],
       "episodes": {"1": [${episodes(["a"])}]}}`,
    );

    const resolved = resolvedSeasons(info);
    expect(resolved.length).toBe(1);
    expect(resolved[0].number).toBe(1);
    expect(resolved[0].metadata?.name).toBe("First");
  });

  // The bug from PR #107: the panel declares season 1, but keys its episodes
  // under "2". The uncovered bucket used to be dropped entirely.
  it("episodeBucketWithoutMatchingSeasonStillYieldsASeason", () => {
    const info = decode(
      `{"seasons": [{"season_number": 1, "name": "First"}],
       "episodes": {"2": [${episodes(["a", "b"])}]}}`,
    );

    const resolved = resolvedSeasons(info);
    expect(resolved.map((season) => season.number)).toEqual([1, 2]);
    expect(resolved[1].metadata).toBeUndefined();
    expect(episodesBySeasonNumber(info).get(2)?.length).toBe(2);
  });

  it("onlySeasonTwoExistsAndIsFullyRecovered", () => {
    const info = decode(
      `{"seasons": [], "episodes": {"2": [${episodes(["a", "b", "c"])}]}}`,
    );

    const resolved = resolvedSeasons(info);
    expect(resolved.map((season) => season.number)).toEqual([2]);
    expect(episodesBySeasonNumber(info).get(2)?.length).toBe(3);
  });

  it("seasonsWithoutNumbersAreSkipped", () => {
    const info = decode(
      `{"seasons": [{"name": "Unnumbered"}], "episodes": {"1": [${episodes(["a"])}]}}`,
    );

    expect(resolvedSeasons(info).map((season) => season.number)).toEqual([1]);
  });

  it("syntheticSeasonsAreOrderedNumerically", () => {
    const info = decode(
      `{"seasons": [], "episodes": {"10": [${episodes(["a"])}], "2": [${episodes(["b"])}]}}`,
    );

    expect(resolvedSeasons(info).map((season) => season.number)).toEqual([2, 10]);
  });

  it("missingEpisodesDictionaryYieldsDeclaredSeasonsOnly", () => {
    const info = decode(`{"seasons": [{"season_number": 1}]}`);

    expect(resolvedSeasons(info).map((season) => season.number)).toEqual([1]);
    expect(episodesBySeasonNumber(info).size).toBe(0);
  });
});

describe("shared Xtream fixtures", () => {
  it("parses auth_success.json", () => {
    const auth = parseXtreamAuthResponse(authSuccess);

    expect(auth.userInfo?.username).toBe("family_tv");
    expect(auth.userInfo?.auth).toBe(1);
    expect(auth.userInfo?.status).toBe("Active");
    expect(auth.userInfo?.expDate).toBe("1779878400");
    expect(auth.userInfo?.maxConnections).toBe("2");
    expect(auth.serverInfo?.url).toBe("example-panel.tv");
    // Int in the JSON, coerced to string.
    expect(auth.serverInfo?.port).toBe("8080");
    expect(auth.serverInfo?.timezone).toBe("Europe/Istanbul");
  });

  it("parses get_live_categories.json", () => {
    const categories = parseXtreamCategoryList(liveCategories);

    expect(categories.length).toBe(3);
    expect(categories[0].categoryId).toBe("1");
    expect(categories[0].categoryName).toBe("News");
    expect(categories[0].parentId).toBe(0);
    // Mixed types: int category_id and string parent_id both normalize.
    expect(categories[1].categoryId).toBe("2");
    expect(categories[1].parentId).toBe(0);
  });

  it("parses get_live_streams.json", () => {
    const streams = parseXtreamLiveStreamList(liveStreams);

    expect(streams.length).toBe(2);
    expect(streams[0].streamId).toBe(101);
    expect(streams[0].name).toBe("News Channel HD");
    expect(streams[0].epgChannelId).toBe("news.example");
    expect(streams[0].isAdult).toBe(0);
    // Mixed types: string stream_id, int category_id, null epg_channel_id.
    expect(streams[1].streamId).toBe(202);
    expect(streams[1].categoryId).toBe("2");
    expect(streams[1].epgChannelId).toBeUndefined();
    expect(streams[1].isAdult).toBe(0);
  });

  it("parses get_vod_streams.json", () => {
    const streams = parseXtreamVodStreamList(vodStreams);

    expect(streams.length).toBe(2);
    expect(streams[0].streamId).toBe(9001);
    // Double in the JSON, coerced to string.
    expect(streams[0].rating).toBe("7.5");
    expect(streams[0].containerExtension).toBe("mkv");
    expect(streams[1].streamId).toBe(9002);
    expect(streams[1].rating).toBe("8");
  });

  it("parses get_series_list.json (camelCase releaseDate)", () => {
    const series = parseXtreamSeriesList(seriesList);

    expect(series.length).toBe(2);
    expect(series[0].seriesId).toBe(501);
    expect(series[0].name).toBe("Harbor Lights");
    expect(series[0].releaseDate).toBe("2021-09-14");
    expect(series[0].categoryId).toBe("21");
    expect(series[1].seriesId).toBe(502);
    // Int rating and last_modified coerced to strings.
    expect(series[1].rating).toBe("7");
    expect(series[1].lastModified).toBe("1712000000");
  });

  it("parses get_vod_info.json (lowercase releasedate)", () => {
    const response = parseXtreamVodInfo(vodInfo);

    expect(response.info?.name).toBe("The Long Voyage (2024)");
    expect(response.info?.releaseDate).toBe("2024-03-08");
    expect(response.info?.rating).toBe("7.1");
    // String in the JSON, coerced to int.
    expect(response.info?.durationSecs).toBe(10140);
    expect(response.info?.backdropPath?.length).toBe(2);
    expect(response.movieData?.streamId).toBe(9001);
    expect(response.movieData?.containerExtension).toBe("mkv");
  });

  it("parses get_series_info_basic.json", () => {
    const info = parseXtreamSeriesInfo(seriesInfoBasic);

    const resolved = resolvedSeasons(info);
    expect(resolved.length).toBe(1);
    expect(resolved[0].number).toBe(1);
    expect(resolved[0].metadata?.name).toBe("First");
    expect(episodesBySeasonNumber(info).get(1)?.length).toBe(1);
  });

  it("parses get_series_info_string_season_keys.json", () => {
    const info = parseXtreamSeriesInfo(seriesInfoStringKeys);

    expect(episodesBySeasonNumber(info).get(1)?.length).toBe(1);
    expect(resolvedSeasons(info).map((season) => season.number)).toEqual([1]);
  });

  it("parses get_series_info_undeclared_seasons.json", () => {
    const info = parseXtreamSeriesInfo(seriesInfoUndeclared);

    const resolved = resolvedSeasons(info);
    expect(resolved.map((season) => season.number)).toEqual([1, 2]);
    expect(resolved[1].metadata).toBeUndefined();
    expect(episodesBySeasonNumber(info).get(2)?.length).toBe(2);
  });

  it("drops corrupt elements in mixed_bad_elements.json", () => {
    const categories = parseXtreamCategoryList(mixedBadElements);

    expect(categories.length).toBe(3);
    expect(categories.map((category) => category.categoryId)).toEqual([
      "1",
      "2",
      "3",
    ]);
  });
});
