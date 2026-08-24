import { db } from "../db";

export interface SyncItemInput {
  kind: string;
  key: string;
  payload?: unknown;
  updatedAt: number;
  deleted: boolean;
}

export interface SyncItemRow {
  seq: number;
  kind: string;
  item_key: string;
  payload: string;
  updated_at: number;
  deleted: number;
}

export interface PushResult {
  key: string;
  kind: string;
  status: "applied" | "stale";
}

const getExisting = db.prepare<[number, string, string], SyncItemRow>(`
  SELECT seq, kind, item_key, payload, updated_at, deleted
  FROM sync_items WHERE user_id = ? AND kind = ? AND item_key = ?
`);

const maxSeq = db
  .prepare<[number], number | null>(`SELECT MAX(seq) FROM sync_items WHERE user_id = ?`)
  .pluck();

const upsert = db.prepare(`
  INSERT INTO sync_items (user_id, kind, item_key, payload, updated_at, deleted, seq)
  VALUES (@userId, @kind, @itemKey, @payload, @updatedAt, @deleted, @seq)
  ON CONFLICT(user_id, kind, item_key) DO UPDATE SET
    payload = excluded.payload,
    updated_at = excluded.updated_at,
    deleted = excluded.deleted,
    seq = excluded.seq
`);

// Last-write-wins per item, keyed by the client-supplied `updatedAt`
// timestamp (when the user actually made the change). If the server already
// has a newer version, the incoming write is dropped and reported back as
// "stale" so the caller knows to pull instead of assuming it applied.
//
// Every applied write (insert or update) gets a fresh, strictly increasing
// `seq` so delta pulls (`seq > cursor`) always see it — see the schema
// comment in db/index.ts for why this can't just be the row's rowid.
export function applyPush(userId: number, items: SyncItemInput[]): PushResult[] {
  const results: PushResult[] = [];
  const txn = db.transaction((batch: SyncItemInput[]) => {
    let nextSeq = (maxSeq.get(userId) ?? 0) + 1;
    for (const item of batch) {
      const existing = getExisting.get(userId, item.kind, item.key);
      if (existing && existing.updated_at > item.updatedAt) {
        results.push({ key: item.key, kind: item.kind, status: "stale" });
        continue;
      }
      upsert.run({
        userId,
        kind: item.kind,
        itemKey: item.key,
        payload: JSON.stringify(item.payload ?? {}),
        updatedAt: item.updatedAt,
        deleted: item.deleted ? 1 : 0,
        seq: nextSeq++,
      });
      results.push({ key: item.key, kind: item.kind, status: "applied" });
    }
  });
  txn(items);
  return results;
}

const pullSince = db.prepare<[number, number, number], SyncItemRow>(`
  SELECT seq, kind, item_key, payload, updated_at, deleted
  FROM sync_items WHERE user_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?
`);

// A "full" bootstrap sync (new device, or local data wiped) is just a delta
// pull with since=0: it also replays tombstones, which are harmless no-ops
// against empty local state and keep the client's apply logic identical for
// both cases.
export function pullDelta(userId: number, sinceSeq: number, limit: number) {
  return pullSince.all(userId, sinceSeq, limit);
}
