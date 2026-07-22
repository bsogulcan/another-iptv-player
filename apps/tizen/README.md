# Another IPTV Player — Samsung Tizen TV

TypeScript + React port of Another IPTV Player for Samsung Smart TVs
(Tizen 4.0+, 2018 models and newer). Video plays through the native
[AVPlay](https://developer.samsung.com/smarttv/develop/api-references/samsung-product-api-references/avplay-api.html)
pipeline; the UI targets Chromium M56 (no CSS Grid, no flex `gap`,
legacy SystemJS bundle via `@vitejs/plugin-legacy`).

## Development

```sh
npm install
npm run dev        # desktop browser dev loop (HTML5 video fallback player)
npm test           # vitest unit suite (ported 1:1 from the iOS test oracles)
npm run build      # type-check + production build into dist/
```

Browser dev notes:

- Open http://localhost:5173 and resize to 1920×1080 for a faithful layout.
- Keyboard: arrows/Enter navigate, Esc acts as the TV Back button.
- The desktop player cannot play raw MPEG-TS; `.m3u8` goes through hls.js
  (dev-only dependency), mp4 plays natively. AVPlay behavior can only be
  verified on a real TV.

### Player spike (phase 1)

To test real Xtream URLs on the TV, copy `public/spike-sources.example.json`
to `public/spike-sources.json` (gitignored — never commit credentials) and
fill in your server/user/pass URLs, then package and deploy.

## Packaging & deploying to a TV

One-time setup:

1. Install the Tizen toolchain — either the
   [VS Code Tizen Extension](https://marketplace.visualstudio.com/items?itemName=tizen.vscode-tizen-csharp)
   ("Tizen: Install Tizen CLI" command; installs under
   `~/.tizen-extension-platform/`) or
   [Tizen Studio](https://developer.samsung.com/smarttv/develop/tools/tizen-studio.html).
   `scripts/tizen-env.sh` probes both layouts (override with `TIZEN_CLI`/`SDB`).
2. Create a **Samsung** certificate with profile name `aiptv` (or pass
   `TIZEN_PROFILE=<name>`): author + distributor with the TV's DUID. The
   VS Code panel needs a Chrome path for the Samsung Account login
   (`tizen cli-config "chrome.path=..."` if the panel's setter fails).
3. On the TV: open the Apps panel, type `1 2 3 4 5` on the remote, enable
   Developer Mode, enter your computer's IP, and reboot the TV.

Each deploy:

```sh
TV_IP=192.168.1.20 npm run deploy   # build → package wgt → sdb connect → install → run
```

Note: the wgt is renamed to `AnotherIPTVPlayer.wgt` before install — the
TV-side installer fails on filenames containing spaces.

Debugging on the TV: `sdb shell 0 debug <appId>` prints a Web Inspector URL.
Native AVPlay errors show up in `sdb dlog`.

## Samsung Apps store submission (checklist)

1. [Seller Office](https://seller.samsungapps.com/tv) account + app registration.
2. Bump `version` in `tizen/config.xml`, build a release wgt
   (`npm run package`), keep the same author certificate for updates.
3. Assets: 512×423 app icon (store), 1920×1080 screenshots (min 4),
   app description per locale.
4. Content rating questionnaire; note the app ships no content — users provide
   their own playlists (same policy stance as the iOS listing).
5. Remove Developer Mode leftovers before certification testing; diagnostics
   screens are dev-build-only and never ship in the release wgt.
6. Samsung certification typically checks: back-key behavior at app root
   (exit confirmation — implemented), network-loss handling, and remote-only
   operability (no pointer).

## Localization

`src/i18n/locales/*.json` are generated from the iOS `.strings` catalogs
(10 locales, ~355 keys) and committed. Regenerate after iOS string changes:

```sh
npm run i18n
```

## Layout

```
src/api/         Xtream client, M3U parser, URL builders (ported from iOS Networking/)
src/models/      wire models + pure logic (coercion, search, ordering, filters)
src/data/        IndexedDB (idb) stores, repos, importers, localStorage settings
src/player/      PlayerPort abstraction: AVPlayAdapter (TV) / Html5VideoAdapter (dev)
src/navigation/  spatial navigation (Norigin), key map, back-stack
src/ui/          screens + components (flexbox-only CSS, 1920×1080 fixed)
src/i18n/        t() runtime + generated locale catalogs
tests/           Vitest suites ported from apps/ios/another-iptv-playerTests
```

Shared test fixtures live in `../../shared/fixtures/` (also used by the iOS
suite as the single source of truth).
