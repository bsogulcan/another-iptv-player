Sync Server
===========

A small, self-hosted sync backend for Another IPTV Player. It stores per-user
state — favorites, watch progress, hidden categories, and anything else a
client wants to keep in sync — so the same account stays consistent across
devices/platforms.

Not required to use the app: every client works fully offline with local
storage. This service is opt-in, for people who run their own server and
want state to follow them across devices.

No telemetry, no third-party services: everything lives in one SQLite file
under `/data`.


Running it
----------

```sh
cp .env.example .env
# edit .env: at minimum set TOKEN_PEPPER (openssl rand -hex 32)
docker compose up -d --build
```

The server listens on `:8787` (`PORT` in `.env`). Data persists in the
`sync-data` Docker volume (`DATA_DIR=/data`).

Without Docker: `npm install && npm run build && npm start` (Node >= 20).
`npm run dev` runs it with live reload.


Concepts
--------

* **Account** — a username/password created via `/api/auth/register`. Meant
  for you (and anyone you're hosting this for); disable further registration
  with `ALLOW_REGISTRATION=false` once accounts exist.
* **Device token** — a bearer token bound to one account *and* one device,
  obtained via `/api/auth/token`. Each login issues a new token so every
  device/app install can be revoked independently (`/api/auth/devices`)
  without logging out the others.
* **Sync item** — the unit of sync. Every piece of client state (a favorite,
  a watch-progress entry, a hidden category, ...) is one row identified by
  `(kind, key)`, carrying a JSON `payload`, an `updatedAt` timestamp, and a
  `deleted` tombstone flag. The server does not know or care what a `kind`
  means — clients can introduce new kinds without server changes.

Conflict resolution is last-write-wins by `updatedAt`: the client sets this
to when the user actually made the change (not when it happened to sync), so
the server keeps the true latest edit even if devices sync out of order.


API
---

All `/api/sync/*` routes require `Authorization: Bearer <deviceToken>`.
All bodies/responses are JSON.

### `POST /api/auth/register`
```json
{ "username": "alice", "password": "at-least-8-chars" }
```
`201` on success, `409` if the username is taken, `403` if registration is
disabled.

### `POST /api/auth/token`
```json
{ "username": "alice", "password": "...", "deviceName": "android-pixel" }
```
→ `{ "token": "...", "deviceId": 1, "deviceName": "android-pixel" }`

### `GET /api/auth/devices`
→ `{ "devices": [{ "id", "deviceName", "createdAt", "lastSeenAt", "revoked", "current" }] }`

### `DELETE /api/auth/devices/:id`
Revokes a device token (`204`). The token stops working immediately.

### `POST /api/sync/push`
```json
{
  "items": [
    {
      "kind": "favorite",
      "key": "5f2a...:movie:42",
      "payload": {},
      "updatedAt": 1735000000000,
      "deleted": false
    }
  ]
}
```
Upserts each item. Returns per-item status:
```json
{ "results": [{ "kind": "favorite", "key": "5f2a...:movie:42", "status": "applied" }] }
```
`status` is `"applied"` or `"stale"` (the server already had a newer
`updatedAt` for that item — the push was ignored; pull to get the current
value). Max `MAX_SYNC_ITEMS_PER_PUSH` items per call (default 500).

### `GET /api/sync/pull?since=<cursor>&limit=<n>`
Returns everything changed after `cursor` (an opaque integer from a previous
response; use `since=0` or omit for the very first sync on a new device).
```json
{
  "items": [
    { "kind": "favorite", "key": "...", "payload": {}, "updatedAt": 1735000000000, "deleted": false }
  ],
  "cursor": 42,
  "hasMore": false
}
```
If `hasMore` is `true`, pull again with `since=cursor` until it's `false`.
Deleted items are included as tombstones (`deleted: true`) so other devices
know to remove them locally; applying a tombstone against state that never
had the item is a harmless no-op, which is also how a brand-new device can
bootstrap with `since=0`.


Client integration contract
----------------------------

This repo does not yet wire any client app up to this service — see the
kinds below as the intended contract for whoever integrates a given
platform next.

* **`sourceKey`** — clients should scope items to a specific playlist/source
  by prefixing the `key` with a stable, non-secret identifier for that
  source (e.g. a SHA-256 of `type:host:username`, *not* the raw
  credentials — this server should never see playlist passwords). This
  keeps favorites/progress from colliding across a user's different
  playlists and avoids leaking credentials to the sync server.

* **`favorite`** — `key = "<sourceKey>:<contentType>:<contentId>"`,
  `payload = {}`. Existence (`deleted: false`) means favorited;
  `deleted: true` removes it.

* **`progress`** — `key = "<sourceKey>:<contentType>:<contentId>[:<episodeId>]"`,
  `payload = { "positionSeconds": number, "durationSeconds": number }`.

* **`hidden_category`** — `key = "<sourceKey>:<categoryType>:<categoryId>"`,
  `payload = {}`.

Suggested client sync loop: on relevant local changes, buffer them and
`POST /api/sync/push` (debounced or on app background); on app start / resume,
`GET /api/sync/pull?since=<lastCursor>` and apply items to local storage,
then persist the returned `cursor` for next time.


Configuration
-------------

See `.env.example` for all environment variables (`PORT`, `DATA_DIR`,
`TOKEN_PEPPER`, `ALLOW_REGISTRATION`, `CORS_ORIGIN`,
`MAX_SYNC_ITEMS_PER_PUSH`).

`TOKEN_PEPPER` is required outside development — it's the HMAC key used to
hash device tokens at rest, so a database leak alone doesn't hand out valid
tokens. Changing it invalidates every issued token (users just re-login).


Security notes
---------------

* Passwords are hashed with bcrypt; device tokens are random 256-bit values,
  stored only as a keyed hash.
* `/api/auth/*` is rate-limited (20 requests / 15 min / IP) to slow down
  credential stuffing.
* This service has no built-in TLS — put it behind a reverse proxy
  (Caddy, Traefik, nginx) with HTTPS if exposing it outside your LAN/VPN.
* Intended for personal/family self-hosting, not as a multi-tenant public
  service.
