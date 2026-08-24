// Typed localStorage wrapper for the sync feature's own settings, kept
// separate from data/settings.ts so the sync module stays self-contained.

const PREFIX = "aiptv.sync.";

export type SyncIntervalMinutes = 0 | 15 | 30 | 60; // 0 = manual only

export interface SyncConfigShape {
  serverUrl: string | null;
  deviceToken: string | null;
  deviceId: number | null;
  accountUsername: string | null;
  autoSyncEnabled: boolean;
  intervalMinutes: SyncIntervalMinutes;
  cursor: number;
  lastSyncedAt: number | null;
  lastSyncError: string | null;
}

const DEFAULTS: SyncConfigShape = {
  serverUrl: null,
  deviceToken: null,
  deviceId: null,
  accountUsername: null,
  autoSyncEnabled: true,
  intervalMinutes: 30,
  cursor: 0,
  lastSyncedAt: null,
  lastSyncError: null,
};

function read<K extends keyof SyncConfigShape>(key: K): SyncConfigShape[K] {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    if (raw === null) return DEFAULTS[key];
    return JSON.parse(raw) as SyncConfigShape[K];
  } catch {
    return DEFAULTS[key];
  }
}

function write<K extends keyof SyncConfigShape>(
  key: K,
  value: SyncConfigShape[K],
): void {
  try {
    if (value === null) {
      localStorage.removeItem(PREFIX + key);
    } else {
      localStorage.setItem(PREFIX + key, JSON.stringify(value));
    }
  } catch (err) {
    console.warn(`[sync/config] failed to persist ${key}`, err);
  }
}

export const syncConfig = {
  get serverUrl() {
    return read("serverUrl");
  },
  set serverUrl(value: string | null) {
    write("serverUrl", value);
  },
  get deviceToken() {
    return read("deviceToken");
  },
  set deviceToken(value: string | null) {
    write("deviceToken", value);
  },
  get deviceId() {
    return read("deviceId");
  },
  set deviceId(value: number | null) {
    write("deviceId", value);
  },
  get accountUsername() {
    return read("accountUsername");
  },
  set accountUsername(value: string | null) {
    write("accountUsername", value);
  },
  get autoSyncEnabled() {
    return read("autoSyncEnabled");
  },
  set autoSyncEnabled(value: boolean) {
    write("autoSyncEnabled", value);
  },
  get intervalMinutes() {
    return read("intervalMinutes");
  },
  set intervalMinutes(value: SyncIntervalMinutes) {
    write("intervalMinutes", value);
  },
  get cursor() {
    return read("cursor");
  },
  set cursor(value: number) {
    write("cursor", value);
  },
  get lastSyncedAt() {
    return read("lastSyncedAt");
  },
  set lastSyncedAt(value: number | null) {
    write("lastSyncedAt", value);
  },
  get lastSyncError() {
    return read("lastSyncError");
  },
  set lastSyncError(value: string | null) {
    write("lastSyncError", value);
  },
};

/** Whether enough is configured to actually talk to a sync server. */
export function isSyncConfigured(): boolean {
  return syncConfig.serverUrl !== null && syncConfig.deviceToken !== null;
}

/** Forces the next sync to replay from the beginning (e.g. after adding a
 * playlist that might have items pushed from another device before this
 * one ever synced). */
export function resetSyncCursor(): void {
  syncConfig.cursor = 0;
}

/** Clears all local sync state (sign out). Does not touch synced data already applied locally. */
export function clearSyncConfig(): void {
  syncConfig.serverUrl = null;
  syncConfig.deviceToken = null;
  syncConfig.deviceId = null;
  syncConfig.accountUsername = null;
  syncConfig.cursor = 0;
  syncConfig.lastSyncedAt = null;
  syncConfig.lastSyncError = null;
}
