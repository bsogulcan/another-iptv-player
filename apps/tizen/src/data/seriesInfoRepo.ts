import { AppDB } from "./db";
import { SeriesInfoRecord, VodInfoRecord } from "./records";

// Lazy-enrichment cache (iOS metadataLoaded/seasonsLoaded pattern): detail
// screens fetch get_series_info / get_vod_info once, persist here, and read
// from the cache on later visits.

export function getSeriesInfo(
  db: AppDB,
  playlistId: string,
  seriesId: number,
): Promise<SeriesInfoRecord | undefined> {
  return db.get("seriesInfo", `${playlistId}_${seriesId}`);
}

export async function saveSeriesInfo(
  db: AppDB,
  record: SeriesInfoRecord,
): Promise<void> {
  await db.put("seriesInfo", record);
  const series = await db.get("series", `${record.playlistId}_${record.seriesId}`);
  if (series && !series.seasonsLoaded) {
    await db.put("series", { ...series, seasonsLoaded: true });
  }
}

export function getVodInfo(
  db: AppDB,
  playlistId: string,
  vodId: number,
): Promise<VodInfoRecord | undefined> {
  return db.get("vodInfo", `${playlistId}_${vodId}`);
}

export async function saveVodInfo(
  db: AppDB,
  record: VodInfoRecord,
): Promise<void> {
  await db.put("vodInfo", record);
}
