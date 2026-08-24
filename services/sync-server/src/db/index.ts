import fs from "node:fs";
import Database from "better-sqlite3";
import { config } from "../config";

fs.mkdirSync(config.dataDir, { recursive: true });

export const db = new Database(config.dbPath);
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

const MIGRATIONS: string[] = [
  `
  CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS device_tokens (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name  TEXT NOT NULL,
    token_hash   TEXT NOT NULL UNIQUE,
    created_at   INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    revoked_at   INTEGER
  );
  CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);

  -- Generic sync store: every syncable "thing" (favorite, watch progress,
  -- hidden category, ...) is one row identified by (user_id, kind, item_key).
  -- New kinds of client data can be added without server-side migrations.
  CREATE TABLE IF NOT EXISTS sync_items (
    seq         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL,
    item_key    TEXT NOT NULL,
    payload     TEXT NOT NULL DEFAULT '{}',
    updated_at  INTEGER NOT NULL,
    deleted     INTEGER NOT NULL DEFAULT 0,
    UNIQUE(user_id, kind, item_key)
  );
  CREATE INDEX IF NOT EXISTS idx_sync_items_user_seq ON sync_items(user_id, seq);
  `,
];

const CURRENT_VERSION = MIGRATIONS.length;

function getUserVersion(): number {
  const row = db.pragma("user_version", { simple: true }) as number;
  return row;
}

function migrate(): void {
  const applied = getUserVersion();
  for (let version = applied; version < CURRENT_VERSION; version++) {
    const migration = MIGRATIONS[version];
    db.exec(migration);
    db.pragma(`user_version = ${version + 1}`);
  }
}

// Runs synchronously as soon as this module is first required, so every
// other module can safely call db.prepare() at import time without racing
// schema creation.
migrate();
