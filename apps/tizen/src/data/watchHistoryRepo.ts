import { AppDB } from "./db";
import { HistoryKind, WatchHistoryRecord } from "./records";

export function historyId(
  playlistId: string,
  type: HistoryKind,
  streamId: string,
): string {
  return `${playlistId}_${type}_${streamId}`;
}

/**
 * Upserts a progress entry. Mirrors iOS rules: live entries carry zero
 * progress; vod/series entries are only written once duration is known.
 */
export async function saveProgress(
  db: AppDB,
  entry: Omit<WatchHistoryRecord, "id">,
): Promise<void> {
  if (entry.type !== "live" && entry.durationMs <= 0) return;
  const record: WatchHistoryRecord = {
    ...entry,
    id: historyId(entry.playlistId, entry.type, entry.streamId),
    lastTimeMs: entry.type === "live" ? 0 : entry.lastTimeMs,
    durationMs: entry.type === "live" ? 0 : entry.durationMs,
  };
  await db.put("watchHistory", record);
}

export function getHistoryEntry(
  db: AppDB,
  playlistId: string,
  type: HistoryKind,
  streamId: string,
): Promise<WatchHistoryRecord | undefined> {
  return db.get("watchHistory", historyId(playlistId, type, streamId));
}

/** Most recent first. */
export async function getRecentHistory(
  db: AppDB,
  playlistId: string,
  limit = 30,
): Promise<WatchHistoryRecord[]> {
  const results: WatchHistoryRecord[] = [];
  const range = IDBKeyRange.bound([playlistId], [playlistId, []]);
  let cursor = await db
    .transaction("watchHistory")
    .store.index("byPlaylistRecency")
    .openCursor(range, "prev");
  while (cursor && results.length < limit) {
    results.push(cursor.value);
    cursor = await cursor.continue();
  }
  return results;
}

export async function clearHistory(
  db: AppDB,
  playlistId: string,
): Promise<void> {
  const tx = db.transaction("watchHistory", "readwrite");
  const range = IDBKeyRange.bound([playlistId], [playlistId, []]);
  let cursor = await tx.store.index("byPlaylistRecency").openCursor(range);
  while (cursor) {
    await cursor.delete();
    cursor = await cursor.continue();
  }
  await tx.done;
}

/** Resume position for a vod/series item, or undefined if below threshold. */
export async function getResumePositionMs(
  db: AppDB,
  playlistId: string,
  type: HistoryKind,
  streamId: string,
): Promise<number | undefined> {
  if (type === "live") return undefined;
  const entry = await getHistoryEntry(db, playlistId, type, streamId);
  if (!entry || entry.lastTimeMs < 5000) return undefined;
  return entry.lastTimeMs;
}
