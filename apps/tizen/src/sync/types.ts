// Wire types for the self-hosted sync-server API (see
// services/sync-server/README.md in the repo root for the full contract).

export type SyncKind = "favorite" | "progress";

export interface SyncPushItem {
  kind: SyncKind;
  key: string;
  payload: unknown;
  updatedAt: number;
  deleted: boolean;
}

// Intentionally empty: existence (deleted: false) is the whole signal.
export type FavoritePayload = Record<string, never>;

export interface ProgressPayload {
  positionSeconds: number;
  durationSeconds: number;
  // Advisory display metadata so a device that has never played this item
  // can still render it in "Continue Watching" without a catalog lookup.
  title?: string;
  secondaryTitle?: string;
  imageURL?: string;
  containerExtension?: string;
  // String on the wire (not number) so every platform's native id type
  // round-trips losslessly — Android's series id is a string.
  seriesId?: string;
}

export interface SyncPullItem {
  kind: SyncKind;
  key: string;
  payload: unknown;
  updatedAt: number;
  deleted: boolean;
}

export interface PullResponse {
  items: SyncPullItem[];
  cursor: number;
  hasMore: boolean;
}

export interface PushResultItem {
  kind: string;
  key: string;
  status: "applied" | "stale";
}

export interface PushResponse {
  results: PushResultItem[];
}

/** Row persisted in the IndexedDB outbox until a push confirms it left the device. */
export interface OutboxRecord {
  seq?: number; // auto-increment primary key
  kind: SyncKind;
  key: string;
  payload: unknown;
  updatedAt: number;
  deleted: boolean;
}
