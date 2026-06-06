# tvOS (Apple TV)

Native Swift/SwiftUI application for Apple TV (libmpv-based player).

## Status: source recovered, Xcode project missing

This app's source was recovered from a lost git stash (dangling commit `5d44f88`,
"On main: appletv") after it had been deleted. **42 Swift files** came back intact:

- `another-iptv-player/` - app source: `Views/Dashboard/*` (tvOS tab UI, shelves, poster
  cards, Top Shelf), `Models`, `Networking` (Xtream + M3U), `Services`, `MPVPlayer`,
  `Database` (GRDB), `Localization` (10 languages), `Assets.xcassets` (tvOS brand assets).
- `Vendor/libmpv/` - tvOS libmpv dylibs + cached tarballs.
- `another-iptv-player/scripts/` - `prepare_libmpv_link_paths.sh`, `embed_libmpv_frameworks.sh`.

### What is missing

The **`.xcodeproj` / `.xcworkspace` is not here** - at stash time the repo's `.gitignore`
excluded `*.xcodeproj`, so the project file was never tracked and could not be recovered.

To make this buildable again, recreate the Xcode project:

1. Create a new tvOS App target named `another-iptv-player`, pointing at the existing
   `another-iptv-player/` sources and `Info.plist`.
2. Wire up the libmpv link/embed build phases using the scripts under
   `another-iptv-player/scripts/` (they read `Vendor/libmpv/`).
3. Add Swift package dependencies as used by the source (e.g. GRDB; check imports).
4. Set the bridging header to `another-iptv-player/another-iptv-player-Bridging-Header.h`.

Kept fully independent from [`../ios`](../ios) and [`../macos`](../macos) (no shared code).
