import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { getDb, resetDbForTests } from "@/data/db";
import { savePlaylist } from "@/data/playlistRepo";
import { toggleFavorite, isFavorite } from "@/data/favoritesRepo";
import { saveProgress, getHistoryEntry, clearHistory } from "@/data/watchHistoryRepo";
import { PlaylistRecord } from "@/data/records";
import { syncConfig, clearSyncConfig } from "@/sync/config";
import { outboxSize, runSync } from "@/sync/syncEngine";
import { playlistSourceKey } from "@/sync/sourceKey";
import type { SyncPullItem, SyncPushItem } from "@/sync/types";

const PID = "playlist-1";

function playlist(id = PID): PlaylistRecord {
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

/** Minimal in-memory stand-in for the real sync-server, driven by fetch. */
class FakeServer {
  items = new Map<string, { kind: string; key: string; payload: unknown; updatedAt: number; deleted: boolean }>();
  seq = 0;

  handlePush(items: SyncPushItem[]) {
    const results = items.map((item) => {
      const existing = this.items.get(item.key);
      if (existing && existing.updatedAt > item.updatedAt) {
        return { kind: item.kind, key: item.key, status: "stale" as const };
      }
      this.seq += 1;
      this.items.set(item.key, { ...item, updatedAt: item.updatedAt });
      return { kind: item.kind, key: item.key, status: "applied" as const };
    });
    return { results };
  }

  handlePull(_since: number) {
    const items: SyncPullItem[] = Array.from(this.items.values()).map((v) => ({
      kind: v.kind as "favorite" | "progress",
      key: v.key,
      payload: v.payload,
      updatedAt: v.updatedAt,
      deleted: v.deleted,
    }));
    return { items, cursor: this.seq, hasMore: false };
  }
}

function installFakeFetch(server: FakeServer) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = new URL(url);
      if (u.pathname === "/api/auth/token") {
        return jsonResponse({ token: "tok", deviceId: 1, deviceName: "test" });
      }
      if (u.pathname === "/api/sync/push") {
        const body = JSON.parse(String(init?.body)) as { items: SyncPushItem[] };
        return jsonResponse(server.handlePush(body.items));
      }
      if (u.pathname === "/api/sync/pull") {
        const since = Number(u.searchParams.get("since") ?? "0");
        return jsonResponse(server.handlePull(since));
      }
      throw new Error(`unexpected fetch ${url}`);
    }),
  );
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

// vitest's "node" environment has no localStorage; the app only needs the
// getItem/setItem/removeItem subset, so a tiny in-memory stub covers it.
class MemoryStorage {
  private store = new Map<string, string>();
  getItem(key: string): string | null {
    return this.store.has(key) ? this.store.get(key)! : null;
  }
  setItem(key: string, value: string): void {
    this.store.set(key, value);
  }
  removeItem(key: string): void {
    this.store.delete(key);
  }
  clear(): void {
    this.store.clear();
  }
}

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  resetDbForTests();
  globalThis.localStorage = new MemoryStorage() as unknown as Storage;
  clearSyncConfig();
  vi.unstubAllGlobals();
});

describe("sourceKey", () => {
  it("is stable for the same server identity and differs otherwise", () => {
    const a = playlistSourceKey(playlist());
    const b = playlistSourceKey(playlist());
    expect(a).toBe(b);
    const c = playlistSourceKey({ ...playlist(), username: "other" });
    expect(c).not.toBe(a);
  });
});

describe("outbox", () => {
  it("only queues changes once sync is configured", async () => {
    const db = await getDb();
    await savePlaylist(db, playlist());

    await toggleFavorite(db, PID, "live", "1");
    expect(await outboxSize(db)).toBe(0);

    syncConfig.serverUrl = "http://sync.local";
    syncConfig.deviceToken = "tok";

    await toggleFavorite(db, PID, "live", "2");
    expect(await outboxSize(db)).toBe(1);
  });
});

describe("runSync", () => {
  it("pushes a favorite from one device and pulls it into another", async () => {
    const server = new FakeServer();
    installFakeFetch(server);

    // Device A
    globalThis.indexedDB = new IDBFactory();
    resetDbForTests();
    const dbA = await getDb();
    await savePlaylist(dbA, playlist());
    syncConfig.serverUrl = "http://sync.local";
    syncConfig.deviceToken = "tok-a";
    await toggleFavorite(dbA, PID, "vod", "42");
    expect(await outboxSize(dbA)).toBe(1);

    await runSync(dbA);
    expect(await outboxSize(dbA)).toBe(0);

    // Device B: different local playlist id, same server identity.
    globalThis.indexedDB = new IDBFactory();
    resetDbForTests();
    const dbB = await getDb();
    await savePlaylist(dbB, playlist("playlist-on-device-b"));
    clearSyncConfig();
    syncConfig.serverUrl = "http://sync.local";
    syncConfig.deviceToken = "tok-b";

    await runSync(dbB);
    expect(await isFavorite(dbB, "playlist-on-device-b", "vod", "42")).toBe(true);
  });

  it("syncs watch progress with display metadata and honors deletes", async () => {
    const server = new FakeServer();
    installFakeFetch(server);

    globalThis.indexedDB = new IDBFactory();
    resetDbForTests();
    const dbA = await getDb();
    await savePlaylist(dbA, playlist());
    syncConfig.serverUrl = "http://sync.local";
    syncConfig.deviceToken = "tok-a";

    await saveProgress(dbA, {
      playlistId: PID,
      type: "vod",
      streamId: "7",
      lastTimeMs: 60_000,
      durationMs: 120_000,
      lastWatchedAt: 100,
      title: "Movie 7",
    });
    await runSync(dbA);

    globalThis.indexedDB = new IDBFactory();
    resetDbForTests();
    const dbB = await getDb();
    await savePlaylist(dbB, playlist("playlist-b"));
    clearSyncConfig();
    syncConfig.serverUrl = "http://sync.local";
    syncConfig.deviceToken = "tok-b";
    await runSync(dbB);

    const entry = await getHistoryEntry(dbB, "playlist-b", "vod", "7");
    expect(entry?.title).toBe("Movie 7");
    expect(entry?.lastTimeMs).toBe(60_000);
    expect(entry?.durationMs).toBe(120_000);

    // Clearing history on device A should tombstone the item for device B.
    await clearHistory(dbA, PID);
    await runSync(dbA);
    await runSync(dbB);
    expect(await getHistoryEntry(dbB, "playlist-b", "vod", "7")).toBeUndefined();
  });
});
