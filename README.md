# Another IPTV Player

![GitHub release (latest by date)](https://img.shields.io/github/v/release/bsogulcan/another-iptv-player?label=Latest%20Release)
![License](https://img.shields.io/github/license/bsogulcan/another-iptv-player?color=brightgreen&label=License)

A free and open-source IPTV player for Xtream Codes and M3U/M3U8 playlists, covering live
TV, movies, and series. The clients collect **no analytics or telemetry**.

This repository is **not** an IPTV provider — it does not host, sell, or distribute any
channels, streams, or subscriptions. A compatible IPTV service of your own is required.

The project is being rewritten as native applications per platform. The original Flutter
app is retained but **deprecated** under [`apps/flutter`](apps/flutter); active development
happens in the native apps.

## Repository layout

A monorepo: each platform is a self-contained application under `apps/`, with
cross-platform engineering resources under `shared/`.

| Path | Description | Status |
|------|-------------|--------|
| [`apps/ios`](apps/ios) | Native iOS app (Swift/SwiftUI, libmpv) | Active |
| [`apps/macos`](apps/macos) | Native macOS app (Swift/SwiftUI, libmpv) | Active |
| [`apps/tvos`](apps/tvos) | Native tvOS app (Swift/SwiftUI, libmpv) | Active |
| [`apps/android`](apps/android) | Native Android app (Kotlin, libmpv) | Active |
| [`apps/windows`](apps/windows) | Native Windows app | Planned |
| [`apps/flutter`](apps/flutter) | Cross-platform Flutter app (Android, iOS, web, desktop) | Deprecated |
| [`shared/docs`](shared/docs) | Architecture and API contracts (Xtream / M3U / XMLTV) | — |
| [`shared/fixtures`](shared/fixtures) | Shared test data (playlists, EPG, mock responses) | — |
| [`shared/design`](shared/design) | Icons, branding, store assets | — |
| [`docs`](docs) | Project website (Next.js) | — |

## Building

Each application is built with its own native toolchain:

| App | Toolchain | Build |
|-----|-----------|-------|
| `apps/ios` | Xcode | open `another-iptv-player.xcworkspace` |
| `apps/macos` | Xcode + XcodeGen | `xcodegen generate`, then open the project |
| `apps/tvos` | Xcode + XcodeGen | `xcodegen generate`, then open the project |
| `apps/android` | Gradle / Android Studio | `./gradlew assembleDebug` |
| `apps/flutter` | Flutter | `flutter pub get && flutter run` |

The Apple apps link libmpv from each app's `Vendor/` directory via build-phase scripts; no
system install is required.

## Features

- **Sources** — Xtream Codes API and M3U/M3U8 playlists (remote URL or local file);
  multiple playlists with add/edit/switch.
- **Content** — live TV, movies, and series with seasons/episodes; rich detail views
  (plot, cast, genre, ratings, trailers); global search; recently added.
- **Playback (mpv)** — HDR tone-mapping, Picture-in-Picture, background audio, offline
  downloads, continue watching, auto play next, gesture controls, aspect-ratio modes.
- **Tracks** — video/audio/subtitle selection with per-item memory.
- **Subtitles** — customization (font, size, color, position), timing offset, external `.srt`.
- **Organization** — favorites, watch history with resume, parental controls, hide
  categories, subscription/content stats.
- **App** — 10+ languages, no ads, no tracking.

## Getting started

1. Download the latest build for your platform from [Releases](https://github.com/bsogulcan/another-iptv-player/releases).
2. Install and launch the app.
3. Add your IPTV provider credentials (server URL, username, password) or an M3U playlist.

## Documentation

- Engineering docs (architecture, API contracts): [`shared/docs`](shared/docs)
- Project website and user guides: https://www.another-iptv-player.com

## Roadmap

- EPG (Electronic Program Guide) support
- TV interface support

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Acknowledgements

- Name inspired by [Another Redis Desktop Manager](https://github.com/qishibo/AnotherRedisDesktopManager).
- The Flutter app uses [media_kit](https://github.com/media-kit/media-kit) for playback.
- Xtream Codes API behavior documented by [JUL1EN094](https://github.com/JUL1EN094)
  ([discussion](https://github.com/AndreyPavlenko/Fermata/discussions/434)).
- Thanks to [ls-hidden](https://github.com/ls-hidden) and [mode0192](https://github.com/mode0192)
  for issues, pull requests, and testing.

## License

See [LICENSE](LICENSE). Use only with a legal IPTV service you are authorized to access.

Support development: [Buy Me a Coffee](https://www.buymeacoffee.com/bsogulcan).
