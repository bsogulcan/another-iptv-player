import { AppDB } from "../data/db";
import { HistoryKind, WatchHistoryRecord } from "../data/records";
import { getRecentHistory } from "../data/watchHistoryRepo";

/**
 * Continue-watching shelf assembly. Series entries are deduped to one card
 * per series (the most recently watched episode), matching tvOS.
 */
export async function continueWatchingItems(
  db: AppDB,
  playlistId: string,
  type?: HistoryKind,
  limit = 20,
): Promise<WatchHistoryRecord[]> {
  const recent = await getRecentHistory(db, playlistId, 100);
  const filtered = type ? recent.filter((h) => h.type === type) : recent;

  const result: WatchHistoryRecord[] = [];
  const seenSeries = new Set<number>();
  for (const entry of filtered) {
    if (entry.type === "series" && entry.seriesId !== undefined) {
      if (seenSeries.has(entry.seriesId)) continue;
      seenSeries.add(entry.seriesId);
    }
    result.push(entry);
    if (result.length >= limit) break;
  }
  return result;
}

export function progressRatio(entry: WatchHistoryRecord): number | undefined {
  if (entry.durationMs <= 0) return undefined;
  return entry.lastTimeMs / entry.durationMs;
}
