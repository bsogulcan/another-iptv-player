import { AppDB, playlistKeyRange } from "./db";
import {
  CatalogKind,
  CategoryRecord,
  LiveStreamRecord,
  SeriesRecord,
  VodStreamRecord,
} from "./records";

export async function getCategories(
  db: AppDB,
  playlistId: string,
  kind: CatalogKind,
): Promise<CategoryRecord[]> {
  const range = IDBKeyRange.bound(
    [playlistId, kind],
    [playlistId, kind, []],
  );
  return db.getAllFromIndex("categories", "byPlaylistKind", range);
}

export async function hasCategories(
  db: AppDB,
  playlistId: string,
): Promise<boolean> {
  const count = await db.countFromIndex(
    "categories",
    "byPlaylistKind",
    playlistKeyRange("categories", playlistId),
  );
  return count > 0;
}

function sortByIndex<T extends { sortIndex: number }>(rows: T[]): T[] {
  return rows.sort((a, b) => a.sortIndex - b.sortIndex);
}

export async function getLiveStreams(
  db: AppDB,
  playlistId: string,
  categoryId?: string,
): Promise<LiveStreamRecord[]> {
  const rows = categoryId
    ? await db.getAllFromIndex(
        "liveStreams",
        "byPlaylistCategory",
        IDBKeyRange.only([playlistId, categoryId]),
      )
    : await db.getAllFromIndex(
        "liveStreams",
        "byPlaylist",
        playlistKeyRange("liveStreams", playlistId),
      );
  return sortByIndex(rows);
}

export async function getVodStreams(
  db: AppDB,
  playlistId: string,
  categoryId?: string,
): Promise<VodStreamRecord[]> {
  const rows = categoryId
    ? await db.getAllFromIndex(
        "vodStreams",
        "byPlaylistCategory",
        IDBKeyRange.only([playlistId, categoryId]),
      )
    : await db.getAllFromIndex(
        "vodStreams",
        "byPlaylist",
        playlistKeyRange("vodStreams", playlistId),
      );
  return sortByIndex(rows);
}

export async function getSeriesList(
  db: AppDB,
  playlistId: string,
  categoryId?: string,
): Promise<SeriesRecord[]> {
  const rows = categoryId
    ? await db.getAllFromIndex(
        "series",
        "byPlaylistCategory",
        IDBKeyRange.only([playlistId, categoryId]),
      )
    : await db.getAllFromIndex(
        "series",
        "byPlaylist",
        playlistKeyRange("series", playlistId),
      );
  return sortByIndex(rows);
}

export function getSeriesById(
  db: AppDB,
  playlistId: string,
  seriesId: number,
): Promise<SeriesRecord | undefined> {
  return db.get("series", `${playlistId}_${seriesId}`);
}

export function getVodById(
  db: AppDB,
  playlistId: string,
  streamId: number,
): Promise<VodStreamRecord | undefined> {
  return db.get("vodStreams", `${playlistId}_${streamId}`);
}
