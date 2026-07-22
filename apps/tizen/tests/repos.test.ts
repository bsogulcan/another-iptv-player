import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it } from "vitest";
import { bulkPut, getDb, resetDbForTests } from "@/data/db";
import {
  deletePlaylist,
  getAllPlaylists,
  savePlaylist,
} from "@/data/playlistRepo";
import {
  getCategories,
  getLiveStreams,
  getVodStreams,
  hasCategories,
} from "@/data/catalogRepo";
import {
  getFavorites,
  isFavorite,
  toggleFavorite,
} from "@/data/favoritesRepo";
import {
  clearHistory,
  getRecentHistory,
  getResumePositionMs,
  saveProgress,
} from "@/data/watchHistoryRepo";
import {
  getM3UChannels,
  groupChannels,
  replaceM3UChannels,
} from "@/data/m3uRepo";
import { stableM3UChannelId } from "@/data/sha256";
import {
  LiveStreamRecord,
  M3UChannelRecord,
  PlaylistRecord,
} from "@/data/records";

const PID = "playlist-1";

function playlist(id: string): PlaylistRecord {
  return {
    id,
    name: "Test",
    type: "xtream",
    serverURL: "http://example.com",
    username: "u",
    password: "p",
    filterAdultContent: false,
    createdAt: 1,
  };
}

function liveStream(streamId: number, categoryId: string): LiveStreamRecord {
  return {
    id: `${PID}_${streamId}`,
    playlistId: PID,
    streamId,
    name: `Channel ${streamId}`,
    categoryId,
    isAdult: false,
    sortIndex: streamId,
  };
}

function m3uChannel(url: string, sortIndex: number, group?: string): M3UChannelRecord {
  return {
    id: stableM3UChannelId(PID, url),
    playlistId: PID,
    name: `ch-${sortIndex}`,
    url,
    groupTitle: group,
    sortIndex,
  };
}

beforeEach(() => {
  // Fresh IndexedDB universe per test.
  globalThis.indexedDB = new IDBFactory();
  resetDbForTests();
});

describe("playlistRepo", () => {
  it("saves, lists and deletes playlists with all owned rows", async () => {
    const db = await getDb();
    await savePlaylist(db, playlist(PID));
    await savePlaylist(db, { ...playlist("playlist-2"), createdAt: 2 });

    await bulkPut(db, "liveStreams", [liveStream(1, "c1"), liveStream(2, "c1")]);
    await toggleFavorite(db, PID, "live", "1");
    await saveProgress(db, {
      playlistId: PID,
      type: "vod",
      streamId: "9",
      lastTimeMs: 60_000,
      durationMs: 100_000,
      lastWatchedAt: 5,
      title: "Movie",
    });

    expect((await getAllPlaylists(db)).map((p) => p.id)).toEqual([
      PID,
      "playlist-2",
    ]);

    await deletePlaylist(db, PID);

    expect((await getAllPlaylists(db)).map((p) => p.id)).toEqual([
      "playlist-2",
    ]);
    // Simple-index store rows must be gone (regression: array-bound range
    // never matches string index keys, silently deleting nothing).
    expect(await getLiveStreams(db, PID)).toEqual([]);
    // Compound-index store rows must be gone too.
    expect(await getFavorites(db, PID)).toEqual([]);
    expect(await getRecentHistory(db, PID)).toEqual([]);
  });
});

describe("catalogRepo", () => {
  it("returns categories of one kind in sortIndex order", async () => {
    const db = await getDb();
    await bulkPut(db, "categories", [
      { id: `${PID}_live_b`, playlistId: PID, kind: "live", categoryId: "b", name: "B", sortIndex: 1 },
      { id: `${PID}_live_a`, playlistId: PID, kind: "live", categoryId: "a", name: "A", sortIndex: 0 },
      { id: `${PID}_vod_c`, playlistId: PID, kind: "vod", categoryId: "c", name: "C", sortIndex: 0 },
    ]);

    const live = await getCategories(db, PID, "live");
    expect(live.map((c) => c.categoryId)).toEqual(["a", "b"]);
    expect(await hasCategories(db, PID)).toBe(true);
    expect(await hasCategories(db, "other")).toBe(false);
  });

  it("filters streams by category and keeps server order", async () => {
    const db = await getDb();
    await bulkPut(db, "liveStreams", [
      liveStream(3, "c2"),
      liveStream(1, "c1"),
      liveStream(2, "c1"),
    ]);

    const c1 = await getLiveStreams(db, PID, "c1");
    expect(c1.map((s) => s.streamId)).toEqual([1, 2]);
    const all = await getLiveStreams(db, PID);
    expect(all.map((s) => s.streamId)).toEqual([1, 2, 3]);
    expect(await getVodStreams(db, PID)).toEqual([]);
  });
});

describe("favoritesRepo", () => {
  it("toggles and lists favorites most-recent first", async () => {
    const db = await getDb();
    expect(await toggleFavorite(db, PID, "live", "1")).toBe(true);
    expect(await isFavorite(db, PID, "live", "1")).toBe(true);
    expect(await toggleFavorite(db, PID, "live", "1")).toBe(false);
    expect(await isFavorite(db, PID, "live", "1")).toBe(false);

    await toggleFavorite(db, PID, "vod", "5");
    await toggleFavorite(db, PID, "series", "7");
    const all = await getFavorites(db, PID);
    expect(all).toHaveLength(2);
    expect(await getFavorites(db, PID, "vod")).toHaveLength(1);
  });
});

describe("watchHistoryRepo", () => {
  it("applies iOS progress rules", async () => {
    const db = await getDb();

    // vod without duration → dropped
    await saveProgress(db, {
      playlistId: PID,
      type: "vod",
      streamId: "1",
      lastTimeMs: 30_000,
      durationMs: 0,
      lastWatchedAt: 1,
      title: "No duration",
    });
    expect(await getRecentHistory(db, PID)).toEqual([]);

    // live → stored with zeroed progress
    await saveProgress(db, {
      playlistId: PID,
      type: "live",
      streamId: "2",
      lastTimeMs: 30_000,
      durationMs: 0,
      lastWatchedAt: 2,
      title: "Live",
    });
    const [live] = await getRecentHistory(db, PID);
    expect(live.lastTimeMs).toBe(0);
    expect(live.durationMs).toBe(0);

    // resume: live never resumes, vod below 5s doesn't resume
    await saveProgress(db, {
      playlistId: PID,
      type: "vod",
      streamId: "3",
      lastTimeMs: 4000,
      durationMs: 100_000,
      lastWatchedAt: 3,
      title: "Almost start",
    });
    expect(await getResumePositionMs(db, PID, "live", "2")).toBeUndefined();
    expect(await getResumePositionMs(db, PID, "vod", "3")).toBeUndefined();

    await saveProgress(db, {
      playlistId: PID,
      type: "vod",
      streamId: "3",
      lastTimeMs: 60_000,
      durationMs: 100_000,
      lastWatchedAt: 4,
      title: "Midway",
    });
    expect(await getResumePositionMs(db, PID, "vod", "3")).toBe(60_000);
  });

  it("orders by recency, upserts by id, and clears", async () => {
    const db = await getDb();
    for (const [streamId, at] of [
      ["1", 10],
      ["2", 30],
      ["3", 20],
    ] as const) {
      await saveProgress(db, {
        playlistId: PID,
        type: "vod",
        streamId,
        lastTimeMs: 60_000,
        durationMs: 100_000,
        lastWatchedAt: at,
        title: `Movie ${streamId}`,
      });
    }
    // Re-watch movie 1 → same row updated, now most recent.
    await saveProgress(db, {
      playlistId: PID,
      type: "vod",
      streamId: "1",
      lastTimeMs: 80_000,
      durationMs: 100_000,
      lastWatchedAt: 40,
      title: "Movie 1",
    });

    const recent = await getRecentHistory(db, PID);
    expect(recent.map((h) => h.streamId)).toEqual(["1", "2", "3"]);
    expect(recent[0].lastTimeMs).toBe(80_000);

    await clearHistory(db, PID);
    expect(await getRecentHistory(db, PID)).toEqual([]);
  });
});

describe("m3uRepo", () => {
  it("replaces channels while favorites survive via stable ids", async () => {
    const db = await getDb();
    const url = "http://host/stream/1.ts";
    await replaceM3UChannels(db, PID, [
      m3uChannel(url, 0, "News"),
      m3uChannel("http://host/stream/2.ts", 1),
    ]);

    const channelId = stableM3UChannelId(PID, url);
    await toggleFavorite(db, PID, "m3u", channelId);

    // Re-import (e.g. refreshed playlist, same URLs) → same ids.
    await replaceM3UChannels(db, PID, [
      m3uChannel(url, 0, "News"),
      m3uChannel("http://host/stream/3.ts", 1),
    ]);

    const channels = await getM3UChannels(db, PID);
    expect(channels).toHaveLength(2);
    expect(await isFavorite(db, PID, "m3u", channelId)).toBe(true);
  });

  it("groups by group-title preserving playlist order", () => {
    const grouped = groupChannels(
      [
        m3uChannel("u1", 0, "News"),
        m3uChannel("u2", 1),
        m3uChannel("u3", 2, "News"),
        m3uChannel("u4", 3, "Sports"),
      ],
      "Other",
    );
    expect(grouped.groupNames).toEqual(["News", "Other", "Sports"]);
    expect(grouped.channelsByGroup.get("News")).toHaveLength(2);
  });
});
