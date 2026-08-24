import { AppDB } from "../data/db";
import { FavoriteKind, HistoryKind } from "../data/records";
import { favoriteId } from "../data/favoritesRepo";
import { historyId } from "../data/watchHistoryRepo";
import * as api from "./api";
import { isSyncConfigured, syncConfig } from "./config";
import { findPlaylistBySourceKey } from "./sourceKey";
import { getOutboxBatch, outboxSize, removeFromOutbox } from "./outbox";
import { ProgressPayload, SyncPullItem, SyncPushItem } from "./types";

const PUSH_BATCH_SIZE = 500;
const PUSH_DEBOUNCE_MS = 4000;

export type SyncStatus = "idle" | "syncing" | "error";

type Listener = (status: SyncStatus) => void;
const listeners = new Set<Listener>();
let currentStatus: SyncStatus = "idle";

function setStatus(status: SyncStatus): void {
  currentStatus = status;
  for (const listener of Array.from(listeners)) listener(status);
}

export function subscribeSyncStatus(listener: Listener): () => void {
  listeners.add(listener);
  listener(currentStatus);
  return () => listeners.delete(listener);
}

async function flushOutbox(db: AppDB): Promise<void> {
  for (;;) {
    const batch = await getOutboxBatch(db, PUSH_BATCH_SIZE);
    if (batch.length === 0) return;
    const items: SyncPushItem[] = batch.map((row) => ({
      kind: row.kind,
      key: row.key,
      payload: row.payload,
      updatedAt: row.updatedAt,
      deleted: row.deleted,
    }));
    // Both "applied" and "stale" mean the server accepted the request and
    // processed it (stale just means a newer write already won) — either
    // way this device's copy of that item is no longer pending.
    await api.push(items);
    await removeFromOutbox(
      db,
      batch.map((row) => row.seq as number),
    );
  }
}

async function applyPulledItem(db: AppDB, item: SyncPullItem): Promise<void> {
  const parts = item.key.split(":");
  const sourceKey = parts[0];
  const contentType = parts[1];
  const contentId = parts.slice(2).join(":");
  if (!sourceKey || !contentType || !contentId) return;

  const playlist = await findPlaylistBySourceKey(db, sourceKey);
  if (!playlist) return; // this device doesn't have that playlist configured

  if (item.kind === "favorite") {
    const kind = contentType as FavoriteKind;
    const id = favoriteId(playlist.id, kind, contentId);
    if (item.deleted) {
      await db.delete("favorites", id);
    } else {
      await db.put("favorites", {
        id,
        playlistId: playlist.id,
        kind,
        itemId: contentId,
        addedAt: item.updatedAt,
      });
    }
    return;
  }

  if (item.kind === "progress") {
    const type = contentType as HistoryKind;
    const id = historyId(playlist.id, type, contentId);
    if (item.deleted) {
      await db.delete("watchHistory", id);
      return;
    }
    const payload = (item.payload ?? {}) as Partial<ProgressPayload>;
    const positionSeconds = payload.positionSeconds ?? 0;
    const durationSeconds = payload.durationSeconds ?? 0;
    await db.put("watchHistory", {
      id,
      playlistId: playlist.id,
      type,
      streamId: contentId,
      lastTimeMs: Math.round(positionSeconds * 1000),
      durationMs: Math.round(durationSeconds * 1000),
      lastWatchedAt: item.updatedAt,
      title: payload.title ?? contentId,
      secondaryTitle: payload.secondaryTitle,
      imageURL: payload.imageURL,
      containerExtension: payload.containerExtension,
      seriesId: payload.seriesId,
    });
  }
}

async function pullAndApply(db: AppDB): Promise<void> {
  for (;;) {
    const res = await api.pull(syncConfig.cursor);
    for (const item of res.items) {
      await applyPulledItem(db, item);
    }
    syncConfig.cursor = res.cursor;
    if (!res.hasMore) return;
  }
}

let syncPromise: Promise<void> | null = null;

/** Push pending local changes, then pull and apply remote changes. Safe to call concurrently — callers share one in-flight run. */
export function runSync(db: AppDB): Promise<void> {
  if (!isSyncConfigured()) return Promise.resolve();
  if (syncPromise) return syncPromise;

  setStatus("syncing");
  syncPromise = (async () => {
    try {
      await flushOutbox(db);
      await pullAndApply(db);
      syncConfig.lastSyncedAt = Date.now();
      syncConfig.lastSyncError = null;
      setStatus("idle");
    } catch (err) {
      syncConfig.lastSyncError =
        err instanceof Error ? err.message : "Sync failed";
      setStatus("error");
    } finally {
      syncPromise = null;
    }
  })();
  return syncPromise;
}

let pushDebounceTimer: ReturnType<typeof setTimeout> | undefined;

/** Call after queuing a local change: pushes soon without waiting for the full periodic interval. */
export function schedulePush(db: AppDB): void {
  if (!isSyncConfigured()) return;
  clearTimeout(pushDebounceTimer);
  pushDebounceTimer = setTimeout(() => void runSync(db), PUSH_DEBOUNCE_MS);
}

let periodicTimer: ReturnType<typeof setInterval> | undefined;

export function stopPeriodicSync(): void {
  clearInterval(periodicTimer);
  periodicTimer = undefined;
}

export function startPeriodicSync(db: AppDB): void {
  stopPeriodicSync();
  if (!isSyncConfigured() || !syncConfig.autoSyncEnabled) return;
  if (syncConfig.intervalMinutes === 0) return;
  periodicTimer = setInterval(
    () => void runSync(db),
    syncConfig.intervalMinutes * 60_000,
  );
}

/** Called once at app boot. */
export function bootSync(db: AppDB): void {
  if (isSyncConfigured()) void runSync(db);
  startPeriodicSync(db);
}

export { outboxSize };
