import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it } from "vitest";
import { getDb, resetDbForTests } from "@/data/db";
import {
  refreshXtreamCatalog,
  syncXtreamCatalog,
  XtreamCatalogSource,
} from "@/data/xtreamImporter";
import { importM3UPlaylist } from "@/data/m3uImporter";
import { getAllPlaylists } from "@/data/playlistRepo";
import {
  getCategories,
  getLiveStreams,
  getSeriesList,
  getVodStreams,
} from "@/data/catalogRepo";
import { getM3UChannels } from "@/data/m3uRepo";
import { isFavorite, toggleFavorite } from "@/data/favoritesRepo";
import { PlaylistRecord } from "@/data/records";

const PID = "pl-1";

function playlist(filterAdult: boolean): PlaylistRecord {
  return {
    id: PID,
    name: "Panel",
    type: "xtream",
    serverURL: "http://example.com",
    username: "u",
    password: "p",
    filterAdultContent: filterAdult,
    createdAt: 1,
  };
}

const source: XtreamCatalogSource = {
  getCategories: (kind) =>
    Promise.resolve(
      kind === "live"
        ? [
            { categoryId: "10", categoryName: "News" },
            { categoryId: "66", categoryName: "XXX Movies" },
          ]
        : kind === "vod"
          ? [{ categoryId: "20", categoryName: "Cinema" }]
          : [{ categoryId: "30", categoryName: "Shows" }],
    ),
  getLiveStreams: () =>
    Promise.resolve([
      { streamId: 1, name: "Haber TV", categoryId: "10" },
      { streamId: 2, name: "Hidden", categoryId: "66" },
      { streamId: 3, name: "Flagged", categoryId: "10", isAdult: 1 },
      { name: "no id, dropped" },
    ]),
  getVodStreams: () =>
    Promise.resolve([
      { streamId: 7, name: "Film", categoryId: "20", containerExtension: "mkv" },
    ]),
  getSeries: () =>
    Promise.resolve([{ seriesId: 9, name: "Dizi", categoryId: "30" }]),
};

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  resetDbForTests();
});

describe("syncXtreamCatalog", () => {
  it("imports full catalog preserving server order", async () => {
    const db = await getDb();
    const phases: string[] = [];
    await syncXtreamCatalog(db, source, playlist(false), (p) =>
      phases.push(p.phase),
    );

    expect((await getAllPlaylists(db)).map((p) => p.id)).toEqual([PID]);
    expect((await getCategories(db, PID, "live")).map((c) => c.categoryId)).toEqual(["10", "66"]);
    expect((await getLiveStreams(db, PID)).map((s) => s.streamId)).toEqual([1, 2, 3]);
    expect((await getVodStreams(db, PID))[0].containerExtension).toBe("mkv");
    expect((await getSeriesList(db, PID))[0].seasonsLoaded).toBe(false);
    expect(phases).toEqual(["categories", "live", "vod", "series"]);
    // Adult flag is recorded even when the filter is off.
    const flagged = (await getLiveStreams(db, PID)).find((s) => s.streamId === 3);
    expect(flagged?.isAdult).toBe(true);
  });

  it("drops adult categories and streams when the playlist opts in", async () => {
    const db = await getDb();
    await syncXtreamCatalog(db, source, playlist(true));

    expect((await getCategories(db, PID, "live")).map((c) => c.categoryId)).toEqual(["10"]);
    // 2 dropped via adult category, 3 dropped via is_adult flag.
    expect((await getLiveStreams(db, PID)).map((s) => s.streamId)).toEqual([1]);
  });

  it("refresh replaces catalog but keeps favorites", async () => {
    const db = await getDb();
    await syncXtreamCatalog(db, source, playlist(false));
    await toggleFavorite(db, PID, "live", "1");

    await refreshXtreamCatalog(db, source, playlist(false));

    expect((await getLiveStreams(db, PID)).map((s) => s.streamId)).toEqual([1, 2, 3]);
    expect(await isFavorite(db, PID, "live", "1")).toBe(true);
  });
});

describe("importM3UPlaylist", () => {
  it("imports parsed channels with stable ids and playlist order", async () => {
    const db = await getDb();
    const m3uPlaylist: PlaylistRecord = {
      ...playlist(false),
      id: "m3u-1",
      type: "m3u",
    };
    await importM3UPlaylist(db, m3uPlaylist, [
      { name: "One", url: "http://h/1.ts", groupTitle: "News" },
      { name: "Two", url: "http://h/2.ts", userAgent: "VLC/3.0" },
    ]);

    const channels = await getM3UChannels(db, "m3u-1");
    expect(channels.map((c) => c.name)).toEqual(["One", "Two"]);
    expect(channels[1].userAgent).toBe("VLC/3.0");
    expect(channels[0].id).toHaveLength(64);
  });
});
