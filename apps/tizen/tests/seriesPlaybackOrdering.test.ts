import { describe, expect, it } from "vitest";
import {
  emptyNavigationContext,
  episodeIndex,
  neighbors,
  orderedEpisodes,
  type EpisodeIdentity,
  type OrderableEpisode,
  type OrderableSeason,
} from "@/models/seriesPlaybackOrdering";

// Port of apps/ios/another-iptv-playerTests/SeriesPlaybackOrderingTests.swift.
// The Swift `orderedEpisodes` / `neighbors` tests require a GRDB database and
// are covered here by pure equivalents under "TS port additions".

function episode(id: string, episodeId: string | null = null): EpisodeIdentity {
  return { id, episodeId };
}

describe("SeriesPlaybackOrdering", () => {
  it("indexFindsByEpisodeId", () => {
    const eps = [
      episode("row-1", "ep-100"),
      episode("row-2", "ep-200"),
      episode("row-3", "ep-300"),
    ];
    expect(episodeIndex("ep-200", eps)).toBe(1);
  });

  it("indexFallsBackToRowId", () => {
    const eps = [episode("row-1", null), episode("row-2", null)];
    expect(episodeIndex("row-2", eps)).toBe(1);
  });

  it("indexReturnsNilWhenAbsent", () => {
    const eps = [episode("row-1", "ep-100")];
    expect(episodeIndex("unknown", eps)).toBeNull();
  });

  it("indexInEmptyListIsNil", () => {
    expect(episodeIndex("anything", [])).toBeNull();
  });

  it("emptyNavigationContextHasNoNeighbors", () => {
    const ctx = emptyNavigationContext;
    expect(ctx.previous).toBeNull();
    expect(ctx.next).toBeNull();
  });

  // MARK: - TS port additions
  // The Swift versions of orderedEpisodes/neighbors read from GRDB; the pure
  // ports take arrays, so their ordering logic is covered directly here.

  it("orderedEpisodesSortsBySeasonThenEpisode", () => {
    const seasons: OrderableSeason[] = [
      { id: "s2", seasonNumber: 2 },
      { id: "s1", seasonNumber: 1 },
    ];
    const eps: OrderableEpisode[] = [
      { id: "e3", seasonId: "s2", episodeNum: 1 },
      { id: "e2", seasonId: "s1", episodeNum: 2 },
      { id: "e1", seasonId: "s1", episodeNum: 1 },
      { id: "orphan", seasonId: "s9", episodeNum: 1 },
    ];
    const ordered = orderedEpisodes(seasons, eps);
    expect(ordered.map((e) => e.id)).toEqual(["e1", "e2", "e3"]);
  });

  it("neighborsReturnsAdjacentEpisodes", () => {
    const eps: OrderableEpisode[] = [
      { id: "e1", episodeId: "ep-100", seasonId: "s1", episodeNum: 1 },
      { id: "e2", episodeId: "ep-200", seasonId: "s1", episodeNum: 2 },
      { id: "e3", episodeId: "ep-300", seasonId: "s1", episodeNum: 3 },
    ];
    const mid = neighbors("ep-200", eps);
    expect(mid.previous?.id).toBe("e1");
    expect(mid.next?.id).toBe("e3");

    const first = neighbors("ep-100", eps);
    expect(first.previous).toBeNull();
    expect(first.next?.id).toBe("e2");

    const missing = neighbors("nope", eps);
    expect(missing.previous).toBeNull();
    expect(missing.next).toBeNull();
  });
});
