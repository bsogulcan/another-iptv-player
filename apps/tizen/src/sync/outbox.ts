import { AppDB } from "../data/db";
import { PlaylistRecord, FavoriteKind, HistoryKind } from "../data/records";
import { playlistSourceKey } from "./sourceKey";
import { isSyncConfigured } from "./config";
import { OutboxRecord, ProgressPayload } from "./types";

async function append(db: AppDB, record: OutboxRecord): Promise<void> {
  await db.add("syncOutbox", record);
}

export async function getOutboxBatch(
  db: AppDB,
  limit: number,
): Promise<OutboxRecord[]> {
  const all = await db.getAll("syncOutbox");
  return all.slice(0, limit);
}

export async function removeFromOutbox(
  db: AppDB,
  seqs: number[],
): Promise<void> {
  const tx = db.transaction("syncOutbox", "readwrite");
  for (const seq of seqs) void tx.store.delete(seq);
  await tx.done;
}

export async function outboxSize(db: AppDB): Promise<number> {
  return db.count("syncOutbox");
}

/** Best-effort: never throws, sync is opt-in and must not break local writes. */
export async function enqueueFavoriteChange(
  db: AppDB,
  playlist: PlaylistRecord,
  kind: FavoriteKind,
  itemId: string,
  favorited: boolean,
): Promise<void> {
  if (!isSyncConfigured()) return;
  try {
    const sourceKey = playlistSourceKey(playlist);
    await append(db, {
      kind: "favorite",
      key: `${sourceKey}:${kind}:${itemId}`,
      payload: {},
      updatedAt: Date.now(),
      deleted: !favorited,
    });
  } catch (err) {
    console.warn("[sync] failed to queue favorite change", err);
  }
}

export async function enqueueProgressChange(
  db: AppDB,
  playlist: PlaylistRecord,
  type: HistoryKind,
  streamId: string,
  updatedAt: number,
  payload: ProgressPayload,
): Promise<void> {
  if (!isSyncConfigured()) return;
  try {
    const sourceKey = playlistSourceKey(playlist);
    await append(db, {
      kind: "progress",
      key: `${sourceKey}:${type}:${streamId}`,
      payload,
      updatedAt,
      deleted: false,
    });
  } catch (err) {
    console.warn("[sync] failed to queue progress change", err);
  }
}

export async function enqueueProgressDelete(
  db: AppDB,
  playlist: PlaylistRecord,
  type: HistoryKind,
  streamId: string,
): Promise<void> {
  if (!isSyncConfigured()) return;
  try {
    const sourceKey = playlistSourceKey(playlist);
    await append(db, {
      kind: "progress",
      key: `${sourceKey}:${type}:${streamId}`,
      payload: {},
      updatedAt: Date.now(),
      deleted: true,
    });
  } catch (err) {
    console.warn("[sync] failed to queue progress delete", err);
  }
}
