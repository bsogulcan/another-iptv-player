# Shared Docs

Platform-independent engineering documentation: architecture decisions, Xtream Codes / M3U /
XMLTV (EPG) API contracts, data models, and behavior specifications.

All native apps (apple, android, windows) should conform to these contracts.

## Sync service

`services/sync-server` is a self-hosted, Dockerized backend for syncing
favorites, watch progress, hidden categories, etc. across devices. It's
optional — every client works fully offline without it. See
`services/sync-server/README.md` for the API contract (auth, sync item
`kind`s, `sourceKey` scoping) that any client integration should follow.