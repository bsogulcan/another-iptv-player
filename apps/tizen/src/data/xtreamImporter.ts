import {
  XtreamCategory,
  XtreamLiveStream,
  XtreamSeriesListItem,
  XtreamVodStream,
} from "../models/xtream";
import {
  adultCategoryIds,
  isAdultCategoryName,
  isAdultLiveStream,
  isAdultVODStream,
} from "../models/adultContentFilter";
import { AppDB, bulkPut, deletePlaylistRows } from "./db";
import {
  CatalogKind,
  CategoryRecord,
  LiveStreamRecord,
  PlaylistRecord,
  SeriesRecord,
  VodStreamRecord,
} from "./records";
import { savePlaylist } from "./playlistRepo";
import { invalidateCatalog } from "./catalogCache";

// Full catalog import, mirroring iOS XtreamImporter.syncAndSave: the playlist
// row is saved first (so it exists even if the content import fails), then
// categories + live + vod + series are bulk-upserted preserving server order.
// Adult filtering is applied at insert time when the playlist opts in.

export type ImportPhase =
  | "categories"
  | "live"
  | "vod"
  | "series";

export interface ImportProgress {
  phase: ImportPhase;
  written: number;
  total: number;
}

/** The slice of XtreamClient the importer needs (structural, for testability). */
export interface XtreamCatalogSource {
  getCategories(kind: CatalogKind): Promise<XtreamCategory[]>;
  getLiveStreams(): Promise<XtreamLiveStream[]>;
  getVodStreams(): Promise<XtreamVodStream[]>;
  getSeries(): Promise<XtreamSeriesListItem[]>;
}

// Record building walks up to ~100k parsed entries; done synchronously it
// extends the JSON.parse freeze. Chunk with yields so the progress UI paints.
const BUILD_CHUNK = 2000;

function nextTick(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function buildChunked<S, R>(
  source: S[],
  build: (item: S, index: number) => R | null,
): Promise<R[]> {
  const records: R[] = [];
  for (let index = 0; index < source.length; index++) {
    if (index > 0 && index % BUILD_CHUNK === 0) await nextTick();
    const record = build(source[index], index);
    if (record !== null) records.push(record);
  }
  return records;
}

function categoryRecords(
  playlistId: string,
  kind: CatalogKind,
  categories: XtreamCategory[],
  filterAdult: boolean,
): CategoryRecord[] {
  const records: CategoryRecord[] = [];
  categories.forEach((category, index) => {
    if (category.categoryId === undefined) return;
    const name = category.categoryName ?? "";
    if (filterAdult && isAdultCategoryName(name)) return;
    records.push({
      id: `${playlistId}_${kind}_${category.categoryId}`,
      playlistId,
      kind,
      categoryId: category.categoryId,
      name,
      sortIndex: index,
    });
  });
  return records;
}

export async function syncXtreamCatalog(
  db: AppDB,
  client: XtreamCatalogSource,
  playlist: PlaylistRecord,
  onProgress?: (progress: ImportProgress) => void,
): Promise<void> {
  await savePlaylist(db, playlist);

  const filterAdult = playlist.filterAdultContent;
  const [liveCats, vodCats, seriesCats] = await Promise.all([
    client.getCategories("live"),
    client.getCategories("vod"),
    client.getCategories("series"),
  ]);

  const liveAdultIds = adultCategoryIds(
    liveCats.map((c) => ({ categoryId: c.categoryId, categoryName: c.categoryName })),
  );
  const vodAdultIds = adultCategoryIds(
    vodCats.map((c) => ({ categoryId: c.categoryId, categoryName: c.categoryName })),
  );
  const seriesAdultIds = adultCategoryIds(
    seriesCats.map((c) => ({ categoryId: c.categoryId, categoryName: c.categoryName })),
  );

  const categories = [
    ...categoryRecords(playlist.id, "live", liveCats, filterAdult),
    ...categoryRecords(playlist.id, "vod", vodCats, filterAdult),
    ...categoryRecords(playlist.id, "series", seriesCats, filterAdult),
  ];
  await bulkPut(db, "categories", categories, 500, (written, total) =>
    onProgress?.({ phase: "categories", written, total }),
  );

  const [live, vod, series] = await Promise.all([
    client.getLiveStreams(),
    client.getVodStreams(),
    client.getSeries(),
  ]);

  await bulkPut(
    db,
    "liveStreams",
    await liveStreamRecords(playlist.id, live, filterAdult, liveAdultIds),
    500,
    (written, total) => onProgress?.({ phase: "live", written, total }),
  );
  await bulkPut(
    db,
    "vodStreams",
    await vodStreamRecords(playlist.id, vod, filterAdult, vodAdultIds),
    500,
    (written, total) => onProgress?.({ phase: "vod", written, total }),
  );
  await bulkPut(
    db,
    "series",
    await seriesRecords(playlist.id, series, filterAdult, seriesAdultIds),
    500,
    (written, total) => onProgress?.({ phase: "series", written, total }),
  );
  invalidateCatalog(playlist.id);
}

/**
 * Manual "refresh all": drops the playlist's catalog rows (favorites, history
 * and lazy info caches are kept) and re-imports from the network.
 */
export async function refreshXtreamCatalog(
  db: AppDB,
  client: XtreamCatalogSource,
  playlist: PlaylistRecord,
  onProgress?: (progress: ImportProgress) => void,
): Promise<void> {
  // finally: a failed re-import must not leave the session cache serving
  // the just-deleted catalog (sync only invalidates on success).
  try {
    await deletePlaylistRows(db, playlist.id, [
      "categories",
      "liveStreams",
      "vodStreams",
      "series",
    ]);
    await syncXtreamCatalog(db, client, playlist, onProgress);
  } finally {
    invalidateCatalog(playlist.id);
  }
}

function liveStreamRecords(
  playlistId: string,
  streams: XtreamLiveStream[],
  filterAdult: boolean,
  adultIds: Set<string>,
): Promise<LiveStreamRecord[]> {
  return buildChunked(streams, (stream, index) => {
    if (stream.streamId === undefined) return null;
    const isAdult = isAdultLiveStream(
      { isAdult: stream.isAdult, categoryId: stream.categoryId },
      adultIds,
    );
    if (filterAdult && isAdult) return null;
    return {
      id: `${playlistId}_${stream.streamId}`,
      playlistId,
      streamId: stream.streamId,
      name: stream.name ?? "",
      icon: stream.streamIcon,
      categoryId: stream.categoryId,
      epgChannelId: stream.epgChannelId,
      isAdult,
      sortIndex: index,
    };
  });
}

function vodStreamRecords(
  playlistId: string,
  streams: XtreamVodStream[],
  filterAdult: boolean,
  adultIds: Set<string>,
): Promise<VodStreamRecord[]> {
  return buildChunked(streams, (stream, index) => {
    if (stream.streamId === undefined) return null;
    const isAdult = isAdultVODStream(
      { isAdult: stream.isAdult, categoryId: stream.categoryId },
      adultIds,
    );
    if (filterAdult && isAdult) return null;
    return {
      id: `${playlistId}_${stream.streamId}`,
      playlistId,
      streamId: stream.streamId,
      name: stream.name ?? "",
      icon: stream.streamIcon,
      categoryId: stream.categoryId,
      rating: stream.rating,
      containerExtension: stream.containerExtension,
      added: stream.added,
      isAdult,
      sortIndex: index,
    };
  });
}

function seriesRecords(
  playlistId: string,
  seriesList: XtreamSeriesListItem[],
  filterAdult: boolean,
  adultIds: Set<string>,
): Promise<SeriesRecord[]> {
  return buildChunked(seriesList, (series, index) => {
    if (series.seriesId === undefined) return null;
    if (
      filterAdult &&
      series.categoryId !== undefined &&
      adultIds.has(series.categoryId)
    ) {
      return null;
    }
    return {
      id: `${playlistId}_${series.seriesId}`,
      playlistId,
      seriesId: series.seriesId,
      name: series.name ?? "",
      cover: series.cover,
      plot: series.plot,
      cast: series.cast,
      director: series.director,
      genre: series.genre,
      releaseDate: series.releaseDate,
      rating: series.rating,
      categoryId: series.categoryId,
      youtubeTrailer: series.youtubeTrailer,
      lastModified: series.lastModified,
      seasonsLoaded: false,
      sortIndex: index,
    };
  });
}
