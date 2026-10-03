# iOS browse native-feel — handoff of the work cut for cost

**Closeout — 2026-10-03:** Continuation changes remain uncommitted. The current [358-finding verification](ios-browse-native-verification.md) records **255 resolved, 49 partly resolved, 53 left by binding decision, 1 unresolved**. Section 16 and its closeout below supersede historical progress statements. This is not a claim that all requested work or physical validation is complete.

**Original handoff state.** The work is committed as `c525141` ("feat(ios): make browsing feel native and fluid") on `fix/ios-ksplayer-crash-guards`, not pushed. What changed and why: `ios-browse-native-fix-report.md` (Turkish). Every audit finding with the finder's and the verifier's text: `ios-browse-native-findings.md` (line numbers there refer to the code *before* `c525141`).

**Not part of this work. Leave these as they are:** the tip-jar feature (`apps/ios/Tips.storekit`, `Models/TipStore.swift`, `Views/Components/TipJarView.swift`, the `TipJarRow()` lines in the two settings views, the `TipStore` line in `another_iptv_playerApp.swift`, the `tip.*` / `settings.about.tip.*` keys in the ten `Localizable.strings`, the `Tips.storekit` entry in `project.pbxproj`), the uncommitted change in `Views/PlayerView.swift`, the scheme, `fastlane/Fastfile`, and the two staged `ios-player-airplay-*.md` files.

## Project rules

- `apps/ios`, SwiftUI, Swift 5 mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency: everything is main-actor isolated unless marked `nonisolated`. Code that runs in `Task.detached`, GRDB read/write closures or other background contexts must be `nonisolated`.
- iOS 18 deployment target, Xcode 26 SDK. iOS 26-only API behind `#available(iOS 26, *)`.
- Strings go through `L("key")`. A new key needs all ten languages (en, tr, ar, de, es, fr, hi, pt, ru, zh) in `Localization/*.lproj/Localizable.strings`. Append new keys; do not reorder or touch existing ones.
- Comments in English, no `print()` (use `Log`).
- Do not change player code: `Views/PlayerView.swift`, `PlayerCore/**`, `Views/Player*.swift`, `Views/MiniPlayerSupport.swift`, `Views/HistorySeriesPlayerShell.swift`, the `*PlayerShell` structs.
- Keep the performance patterns:
  - Equatable shelf rows and content views keep every input in their hand-written `==`.
  - Filtering and sorting stay off the main actor.
  - Each screen has one keyed `.task(id:)` with an applied key.
  - Play queues are prebuilt.
  - No catalog-sized work on the main actor or in initialisers.
- Shared components live in `Views/Components/Browse/` (shelf header, press styles, title styles, progress bar, context-menu buttons, empty and error views, `NetworkErrorText`, `Indexed`, `FilterChip`, zoom-transition helpers, card hover) and `Models/XtreamFavoriteStore.swift`. Use them; do not fork them.
- Build and test:
  ```
  xcodebuild -project apps/ios/another-iptv-player.xcodeproj -scheme another-iptv-player \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
    -skip-testing:another-iptv-playerUITests/ScreenshotsUITests
  ```
  - At `c525141`: 1345 unit tests (one known issue in `CastPipelineHarness`) and 37 UI tests, all green.
  - UI tests launch with `-UITests 1` (demo data).
  - `MockFixture` also offers `-UITestsFixture rich` (seasons and episodes, guide data, history, favourites) and `-UITestsStartPlaylist m3u` (an M3U playlist).
  - `-UITestsCatalogScale <n>` gives a large synthetic catalog.
- The decisions taken for the owner are binding (last section). "Leave alone" items stay out.

## 1. Review the code that went in without an independent review (highest value)

Every other area had an adversarial review of its diff. These did not, because that review round was stopped for cost. See each diff with `git show c525141 -- <file>`.

| Area | Files | Look especially at |
|---|---|---|
| Background work | `EPG/EPGStore.swift`, `EPG/EPGRefreshCoordinator.swift`, `EPG/EPGDownloader.swift`, `EPG/EPGXMLTVParser.swift`, `EPG/EPGConstants.swift`, `EPG/XtreamEPGModels.swift`, `EPG/PanelTimeZoneResolver.swift`, `Networking/XtreamAPIClient.swift`, `Networking/M3UService.swift`, `Networking/M3UParser.swift`, `Models/M3UImporter.swift`, `Models/DownloadManager.swift`, `Models/DownloadStorage.swift`, `UIUtils/NetworkStatus.swift` | guide refresh now `@concurrent` (must stay off main, no data race on the store); `isGuideEnabled` / `setGuideEnabled` and the line-reservation rule (A26, A31); retry cooldown `shouldRefresh`; foreground and reconnect refreshes; async file deletion order in `DownloadManager`; `pendingEnqueueIds`; M3U parser dropping unparseable URLs |
| Dashboards and app shell | `Views/DashboardView.swift`, `Views/M3UDashboardView.swift`, `another_iptv_playerApp.swift` (`AppRootView`), `Views/PlayerOverlayController.swift`, `Localization/LocalizationManager.swift`, `Views/EPG/EPGLineReservation.swift` | `PlayerOverlayHost` extraction (PlayerView must not remount), `replaceContent`, `detailRequest` / `onPlayerDetailRequest`, refresh-error alerts, `AppLocale.current` and the cached `L()` (language switch without relaunch, fallback for missing keys), `PosterMetrics` from window size, the guarded review prompt |
| TV guide | `Views/EPG/EPGGuideView.swift`, `EPGGuideViewModel.swift`, `EPGGuideRowViews.swift`, `EPGComponents.swift`, `ChannelEPGDetailView.swift`, `EPGProgrammeDetailSheet.swift` | rows built off main, hidden categories, M3U tap plays, day rollover, `EPGNowNextSlot`, channel cells turned into Buttons with a context menu inside the two-axis scroll view |
| Shared kit | `Views/Components/Browse/*.swift`, `Models/XtreamFavoriteStore.swift` | `CardPressStyle` in scroll views (a fling must not flash cards), `minimumHitHeight`, optimistic favourites and serialized writes, `NetworkErrorText` mapping |
| Playlist list and forms | `ContentView.swift`, `Views/AddPlaylistView.swift`, `Views/AddM3UPlaylistView.swift`, `Views/Components/LoadingProcessView.swift`, `Networking/XtreamLinkDetector.swift` | + menu, cancellable import, discard confirmation, row deletion with cascade, `displaySource` |
| Demo data (tests only) | `Database/MockFixture*.swift` | rich and M3U profiles, browse-state reset on every `-UITests` launch |
| The whole polish pass (no review at all) | kit adoption across `VODView`, `SeriesView`, `LiveStreamsView`, `M3UChannelsView`, `M3UFavoritesView`, `MovieDetailView`, `DetailComponents`, `DownloadButton`, `FavoritesView`, `WatchHistoryListView`, `ContinueWatchingRow`, `DownloadsView`, `CategoryPickerSheet`, `CatalogLoadErrorView`, `RatingLabel`, `SearchView`, both settings views, `ContentView`, `AddPlaylistView`, both dashboards and the EPG views | context menus and `.cardPress` on every card, zoom transition (`posterZoomSource` / `posterZoomDestination`, namespace per row or grid), `onPlayerDetailRequest` pushes, `EPGNowNextSlot` + `\.epgLineReserved` + `\.epgGuideEnabled`, haptics only on user actions, the environment key `\.playerOverlayController` instead of the observed object |

Report each real defect with a concrete failure scenario, fix it, and keep the tests green.

## 2. Defects found by completed reviews and not fixed (15, all minor)

Line numbers are from review time and may have moved a little.

1. **vod** (`another-iptv-player/Views/VODView.swift`, lines 777-814 at review time)
   - Problem: The shelf's prefetch stop is not guaranteed to use the same arguments as its start. `setPrefetching` rebuilds the URL list from the row's current `items` and `containerWidth` when it is called. A row stays mounted (ForEach id is `category.id`) while those inputs change, so `onAppear` (start) and `onDisappear` (stop) can see different heads.
   - Failure scenario: On Movies home, four shelves are visible and each `onAppear` has queued its first ~8 posters. The user types "ma" in the root field. The matching categories keep their rows, now holding 1-3 hits each, and no `onAppear` fires, so the hits are never warmed. When those rows scroll away, `stop()` is built from the hits, so the ~8 prefetches originally queued per row are never cancelled. The same mismatch happens when a pull-to-refresh changes the first films of a visible category, when `applyVODMetadata` replaces a head film's icon, and on iPad when the measured shelf width (first measurement or rotation) changes `headCount` between appear and disappear. Each case leaks at most `headCount` (up to 24) requests per row, but the brief's "same arguments as start" rule is not kept.
   - Suggested fix: Compute the head URLs once per body (`let head: [URL] = ...`) and also react to changes while the row is mounted: `.onChange(of: head) { old, new in stop(old); start(new) }` next to the existing `onAppear`/`onDisappear`. This keeps the row stateless and Equatable. Alternatively, key a `.task(id: head)` that starts on entry and stops in a cancellation handler.

2. **vod** (`another-iptv-player/Views/VODView.swift`, lines 150, 271 at review time)
   - Problem: While the movies load, the Recently Added slot is reserved above the category shelves (`reservesRecent = isStreamsLoading`). It is then removed whenever the catalog has no numeric `added` values, which moves every shelf after first paint. The scroll-perf-3 verifier recommended dropping this placeholder for exactly that reason; the movies-browse-detail-10 verifier recommended keeping it.
   - Failure scenario: Open the demo playlist or any panel whose movies lack `added`. The demo fixture in `MockFixture.insertMovies` has no `added`, and App Review and the UI tests use it. In load phase 1 a 'Recently Added' header with grey tiles is drawn above the category shelves. In phase 2 `recentVODCandidates` is empty, so the whole block (about 226 pt on iPhone, about 420 pt on iPad) is removed and every shelf jumps up. This happens on every cold launch or playlist open of such a catalog. On a large catalog without `added`, the placeholder stays up for the whole stream read and then collapses.
   - Suggested fix: Reserve the slot only when this playlist is known to have recents. For example, remember per playlist whether the last load produced candidates (a UserDefaults flag read once per body, like `EPGStore.isLineReserved`) and use it in phase 1. Otherwise drop the reservation and accept a single insertion. Whichever rule is chosen, make the Series lane use the same one so the two tabs match.

3. **series** (`Views/SeriesView.swift`, lines 698-733 at review time)
   - Problem: SeriesCategoryShelfRow does not stop exactly what it started. Both `.onAppear` (start) and `.onDisappear` (stop) recompute `headCoverURLs` from whatever `items` holds at that moment. A row whose items change while it stays mounted gets no new `.onAppear`, so the two calls disagree. Brief H8 asks for the stop to use the same arguments as the start.
   - Failure scenario: On the Series home the 'Drama' shelf is on screen, so onAppear started prefetching up to 24 covers of the full list. The user types 'lights': the same row (same category id, items still non-empty) now holds 1 hit, and its horizontal ScrollView stays mounted. The user flings past it, and onDisappear stops only the hit's cover; the 20+ full-list prefetches are never stopped. Clearing the search puts the full list back with no new prefetch start. A pull-to-refresh that changes the head of a visible shelf does the same thing. Impact is small: leftover prefetches run to the end, which is how base behaved.
   - Suggested fix: Record the URLs actually passed to `start` (for example `@State private var prefetchedHead: [URL] = []`, set in onAppear) and pass exactly those to `stop`. Or restart on `.onChange(of: <items token>)`: stop the old head, then start the new one.

4. **seriesdetail** (`Views/SeriesView.swift`, lines 1853 at review time)
   - Problem: The player seed sets its artwork with `seed.imageURL = episode.cover ?? series.cover`, which counts an empty cover string as a real cover. Before this change, the page fell back on URL validity: `ep.cover.flatMap { URL(string: $0) } ?? currentSeries.cover.flatMap { URL(string: $0) }`. Empty strings do reach `DBEpisode.cover`: `decodeFlexibleStringIfPresent` keeps "", and `movieImage ?? cover` does not move past "".
   - Failure scenario: The panel answers get_series_info with `"movie_image": ""` for an episode, so the stored episode has cover = "". The user plays it from the list or with Resume. The seed carries imageURL "", and HistorySeriesPlayerShell turns that into artworkURL = nil (URL(string: "") is nil). The player, the mini card and Now Playing / the lock screen show no artwork, where they used to show the series poster. PlayerView then saves imageURL nil into the history row (PlayerView.swift:1581), so the Continue Watching and History cards for that episode show the placeholder icon. A Resume from the page also overwrites a history row that the old flow had saved with the series poster.
   - Suggested fix: Treat a blank cover as missing before falling back, for example `seed.imageURL = episode.cover.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? series.cover`, or keep whichever of the two parses as a URL. Add a case with cover "" next to `seedFallsBackToTheSeriesCover`.

5. **seriesdetail** (`Views/SeriesView.swift`, lines 1332-1346 at review time)
   - Problem: SeasonEpisodesObserver reads every episode row of the season, plus the history rows of those episodes through an IN list with one bound id per episode, synchronously on the main thread. This happens when the panel first mounts and again on every season change. api-w0.md restricts `immediate` to single-row or small requests and rules out long lists. The rows go through keyed Codable decoding, which the catalog code avoids because it is slow (the 'Bulk row decoding' comment in PlaylistContentStore). The verifier rated this read negligible only for a normal-sized season.
   - Failure scenario: A daily series whose panel files 400+ episodes under one season (common in the TR and IN catalogs this app is localised for). The page is pushed. A frame or two later the selection task finishes, EpisodesPanel mounts, and its onAppear decodes about 400 DBEpisode rows and runs the IN query on the main thread while the push animation is still running, so frames drop. Every chip tap on that series repeats the read on the main thread.
   - Suggested fix: The observer already keeps the previous season's rows until the new value arrives, so a season switch shows no spinner and no collapse even without `.immediate`. Use `.immediate` only where it pays off: the first load, or seasons whose `DBSeason.episodeCount` (already on the row the page holds) is below a small bound, say about 100. Use the default async scheduling otherwise. As an alternative, measure the cost on a device with a long season before shipping.

6. **seriesdetail** (`Views/SeriesView.swift`, lines 1329-1330, 1343 at review time)
   - Problem: The guard on the applied season is set before the observation is known to work. `.catch { _ in Just(SeasonEpisodes()) }` replaces a failed observation with an empty value and ends the stream, but `self.seasonId` stays set. Every later `load` for the same season then returns early. Before the change, each onAppear re-subscribed, so the panel recovered on the next visit.
   - Failure scenario: The season observation fails once, for example a read error while the database is being reset or closed. The panel shows 'No episodes in this season' with the real rows still in the database. The user leaves the tab and comes back: onAppear calls load(seasonId:), which returns early, and the panel stays wrong. Only switching to another season and back fixes it.
   - Suggested fix: Clear the guard when the observation fails. For example, set `self?.seasonId = nil` from the error path (with a weak capture in the catch, or by handling the completion in `sink(receiveCompletion:)`), so the next onAppear subscribes again.

7. **m3u** (`Views/M3UFavoritesView.swift`, lines 91-111 at review time)
   - Problem: An empty scan is taken as 'no favourites' even when the catalog it scanned is still loading. M3UChannelsView keeps its toolbar, including the Favorites star, live while it shows the loading spinner. So Favorites can be opened before `store.channels` is filled. The scan then filters an empty array, sets `favoriteChannels = []` and `appliedKey`, and the 'No favourites yet' state stays up until the revision bump. This is the false empty state m3u-browse-12 (3) was meant to remove.
   - Failure scenario: Large M3U playlist with 3 favourites. While Channels shows 'Loading channels...', tap the star. favoriteIds is already filled by the dashboard's track(), store.channels is []. The screen shows 'No favourites yet' for the whole catalog load (seconds on a 300k list), then switches to the grid.
   - Suggested fix: In recompute(), when `store.activePlaylistId != playlist.id || (store.isLoading && store.channels.isEmpty)`, leave favoriteChannels nil and appliedKey unset (Color.clear or a ProgressView), and let the revision bump run the real scan.

8. **m3u** (`Views/M3UChannelsView.swift`, lines 78, 254-261 at review time)
   - Problem: The empty-playlist state can now be pulled to refresh, but the refresh tears it down. reloadIfActive sets `isLoading = true` whenever channels are empty. The first branch (`store.isLoading && store.channels.isEmpty`) then swaps the pullable ScrollView, refresh control included, for the full-page loading state in the middle of the refresh.
   - Failure scenario: An M3U playlist that came back empty. Pull down: the refresh control spins (download, parse and import for a URL list; immediately for a file list). Then the whole page jumps to 'Loading channels...', and then back to 'No channel found' (or to the shelves). The refresh control vanishes abruptly instead of settling.
   - Suggested fix: Track the pull locally (for example `@State isRefreshing`, set around refreshFromPull) and keep the empty state while it is set. Alternatively, show the full-page spinner only until this playlist's first load has answered, not for later reloads.

9. **m3u** (`Views/M3UChannelsView.swift`, lines 395-411 at review time)
   - Problem: M3UGroupSearch.run checks Task.isCancelled once per group only. The corrected fix for data-main-thread-8 asks for a check every few thousand rows. A playlist without group-title puts every channel into one ungrouped bucket, which the findings call a realistic case. For such a playlist a superseded search runs the whole `channels.filter` to the end.
   - Failure scenario: Ungrouped playlist with 150k channels. Type 'spo' and keep typing 'rt' after the 250 ms debounce. The first scan was cancelled but still matches all 150k names before returning. It competes with the scan for 'sport', so the new hits arrive later.
   - Suggested fix: Replace the filter for non-matching groups with an indexed loop that checks `Task.isCancelled` every ~2048 channels and breaks. The caller already discards a cancelled result.

10. **m3u** (`Views/M3UChannelsView.swift`, lines 443-477 at review time)
   - Problem: This lane adds a new key `m3u.history.remove` ('Remove from History') and its own delete code. In the same wave the secondary lane adds `history.item.remove` (same label) and `DBWatchHistory.remove(id:from:)` (same delete) in ContinueWatchingRow.swift.
   - Failure scenario: At merge the ten Localizable.strings files would get two keys for one label, translated twice and able to drift apart. Two copies of the per-row delete would exist, one logging under 'M3UHistory' and one under 'WatchHistory'.
   - Suggested fix: At merge, have M3UUnavailableHistoryAlert use `history.item.remove` and `DBWatchHistory.remove(id:from:)` from the secondary lane, and drop `m3u.history.remove` from the strings to add.

11. **settings** (`Views/M3UPlaylistSettingsView.swift`, lines 403-413 (finishSync), with EPGSettingsSections.swift:114-116 at review time)
   - Problem: finishSync reads the stored row first and only assigns it to `current` after `fetchStats()` and `M3UContentStore.reloadIfActive(...)`. The reload regroups the whole channel list off the main actor, so on a large playlist it can take on the order of a second. The adult-filter switch and the guide URL Save stay enabled while a re-import runs. A write that lands in that window updates `current`, and the older row then overwrites it. The report says a database re-read cannot deliver an older row after a newer write; this path does exactly that.
   - Failure scenario: M3U playlist with tens of thousands of channels. The user taps 'Re-download from URL'. While the spinner is still showing (importer done, reloadIfActive running), they flip 'Filter Adult Content' on. saveFilterSetting stores the flag and sets current = saved (on), then finishSync resumes and sets current = stored, a row read before that save (off). The switch now shows off while the database and the store have it on. The same thing happens with the TV Guide URL: the user saves a new URL in that window, `playlist = updated` runs, then finishSync puts the stale row back. The section's onChange sees `draftTrimmed == old` (the URL just saved) and rewrites the field to the old URL. Save goes disabled, so the screen says the new URL was never saved although it is stored. This lasts until the form appears again.
   - Suggested fix: Do not hold a row across the awaits. Either re-read the row right before the `withAnimation { current = ... }` assignment (after fetchStats and reloadIfActive), or copy only the columns the importer owns (name, serverURL, m3uEpgURL) from the re-read row onto `current`, so a newer filter or override already in `current` is kept.

12. **secondary** (`Views/DownloadsView.swift`, lines 366-373 at review time)
   - Problem: The new 0.4 s linear animation on the progress bar also runs when the value falls back to 0. `fraction` is `manager.progress[item.id]?.fraction ?? 0`, and DownloadManager removes the progress entry before the row leaves the Downloading section: `cancel(id:)` removes it synchronously and deletes the row in a later Task; `markCompleted`, `markFailed` and `requeueAfterError` remove it right after their write returns, which normally reaches the main actor before the observation's re-fetch does. Before this change the bar snapped to 0 for a frame and the row vanished without animation, so nothing was seen. Now the bar glides backwards and the row, which leaves with the new list animation, fades out showing a draining bar and '0 %'.
   - Failure scenario: A film is at 100 % and finishes (or the user picks Cancel at 60 %). The progress entry is removed while the stored row is still `downloading`, so the body runs with fraction 0. The bar animates from 1.0 (or 0.6) towards 0 and the caption reads '0 %'. A moment later the row moves to Movies (or is deleted) with the `.animation(.default, value: items)` transition, so the outgoing cell is visibly emptying while it fades. On completion this depends on timing (continuation before observation delivery, the usual order); on cancel it happens every time.
   - Suggested fix: Do not animate when there is no live progress entry, e.g. `.animation(p == nil ? nil : .linear(duration: 0.4), value: fraction)`. Better, keep the last known fraction for the row (small row view with @State, or fall back to the stored downloadedBytes / totalBytes) so the bar and the percent text never drop to 0 on the way out.

13. **secondary** (`Views/DownloadsView.swift`, lines 224-228, 295-301 at review time)
   - Problem: Finished and failed rows are now default-style list Buttons. The comment at 303-304 says the row uses concrete colours throughout, but the thumbnail is a `CachedImage`, whose placeholder glyph is drawn with the hierarchical `.foregroundStyle(.quaternary)` (Views/CachedImage.swift:332). Inside a default-style button label a hierarchical style resolves against the accent tint; that is the same mechanism the comment itself describes for `.primary` / `.secondary`. I could not render it, so this is from code reading only.
   - Failure scenario: A completed or failed download has no artwork (imageURL nil, the image fails, or it is still loading). Its placeholder glyph is drawn as a faint accent-coloured symbol, while the same placeholder in a downloading or queued row (not a button) stays grey. The two kinds of row sit in the same list.
   - Suggested fix: Set a concrete foreground style at the label root, as the verifier's corrected fix said: `row(item).foregroundStyle(Color.primary)` inside the Button (the per-text Color.primary / Color.secondary can stay). The glyph's quaternary level then resolves against the label colour in both row kinds. Check once in light and dark.

14. **detail** (`another-iptv-player/Views/MovieDetailView.swift`, lines 59-65, 142-158 at review time)
   - Problem: `metadataState` returns `.loading` whenever the stored row says `metadataLoaded == false` and there is no error, whether or not a request is running. Only the `.task` starts a fetch, and it runs only on appear. If the row loses its metadata while the detail is on screen, the page shows the redacted plot skeleton and the 'loading movie info' VoiceOver label with nothing loading. It stays that way until the user leaves the screen and comes back.
   - Failure scenario: The user pulls to refresh on the Movies root, which runs `refreshFromNetwork(playlist:only: .vod)` for several seconds on a large panel. While it runs, the user taps a poster, and the detail fetches and shows plot and cast. The refresh then commits `replaceVODCatalog`, which runs DELETE and then INSERT for every vodStream row with `metadataLoaded = false`. The immediate `VODByIDRequest` emits the new row, so `metadataState` becomes `.loading`. The plot is replaced by a skeleton that never resolves, and no Try Again appears because `errorMessage` is nil. The same happens if the refresh removed the film: `movieRecord` becomes nil, `currentMovie` falls back to the list copy, which has `metadataLoaded == false`, and the page shows `.loading` for good. The old code showed the content without the metadata here, not a fake loading state.
   - Suggested fix: Make the loading state follow an actual request. Either keep an explicit fetch phase (`pending` until `.task` decides; `running` while `fetchMovieInfo` runs; `idle` otherwise) and draw the placeholder only for `pending` or `running`, or start a new fetch when `currentMovie.metadataLoaded` goes from true to false (`.onChange(of: currentMovie.metadataLoaded) { old, new in if old && !new { Task { await fetchMovieInfo() } } }`). Both keep the placeholder in the first frame.

15. **detail** (`another-iptv-player/Views/Components/DownloadButton.swift`, lines 165-169 at review time)
   - Problem: The compact 44 pt slot uses `.frame(minWidth: 44, minHeight: 44)` with the default centre alignment, so the visible chip (about 33 x 29 pt) sits in the middle of the slot. `EpisodeDetailRow` lays the chip out in `HStack(alignment: .top)`, so every episode's download chip drops about 7.5 pt below the episode title. It stays there until the series lane adds the `.padding(.top, -7)` described in the follow-ups. Only the width change (about 11 pt narrower text column) is unavoidable with a 44 pt slot. The vertical shift can be fixed inside this file.
   - Failure scenario: Merge this lane before the SeriesView follow-up and open any series season. Each episode row's download chip is no longer top-aligned with the episode title: it sits about 7.5 pt lower than before. This affects every row on the series page, which the brief's signature-stability rule says must behave as today wherever D8 does not require a change.
   - Suggested fix: Anchor the chip to the top of its slot, `.frame(minWidth: compact ? 44 : nil, minHeight: compact ? 44 : nil, alignment: .topTrailing)` (or `.top`), and keep `.contentShape(Rectangle())`. The tap target is still 44 x 44, the chip keeps its vertical position, and SeriesView only needs to take back the width (HStack spacing or a trailing inset). Update the follow-up note to match.

## 3. Gaps found at the end (small and concrete)

1. **Detail stars bypass the favourites store.** `Views/MovieDetailView.swift` (about line 448) and the series detail in `Views/SeriesView.swift` (about line 2383) insert `DBFavorite` rows themselves. Move both to `XtreamFavoriteStore.shared.setFavorite(...)` / `FavoriteWriter`: the writes become idempotent, and card menus and stars share one optimistic state. `LiveStreamsView.swift` around line 1676 is inside `LivePlayerShell` (player code): leave it.
2. **Downloads show raw system text.** `Models/DownloadManager.swift` stores `error.localizedDescription` (device language) in `errorMessage` (around lines 183, 225, 756, 790, 901). Map it through `NetworkErrorText.describe(_:)` (decision A11).
3. **Settings error texts embed `localizedDescription`.** `Views/PlaylistSettingsView.swift` around line 498, `Views/M3UPlaylistSettingsView.swift` around lines 341, 457, 470: use `NetworkErrorText` (A11).
4. **Dead code.** `PlaylistContentStore.applyVODMetadata(_:)` has no callers left. Remove it, and the comments that mention it.
5. **Favorites cards drift.** `FavoritesView` now draws its own cells instead of `VODStreamCard` / `SeriesCard` / `LiveStreamCard`, so card changes do not reach it. Re-use the shared cards, or extract one card used by both.
6. **Progress bar on the wrong edge.** On movie and series cards the watch-progress bar sits at the top of the poster (`topTrailing` ZStack). Use `CardProgressBar` as a bottom overlay, as Continue Watching does.
7. **Duplicate detail push.** Tapping the title in the player pushes the detail through the tab root (`onPlayerDetailRequest`). The "no second copy" check only knows details the root itself pushed, so a detail opened from a card can end up on the stack twice.
8. **TV guide texts.**
   - The catalog-failed state shows only a generic title, with no reason and no retry.
   - The all-categories-hidden state reuses the `m3u.empty.all_hidden.*` keys for Xtream playlists; give it neutral wording.
9. **M3U card menu still offers Download for film-like entries.** This deviates from decision A5, but it is the only download path for M3U films. Owner decision: leave it unless told otherwise.
10. **The overlay controller is still injected as an environment object.** Both dashboards and the Downloads sheet still pass `.environmentObject(playerOverlay)`, but no view reads `PlayerOverlayController` through `@EnvironmentObject` any more (checked with grep at `c525141`; browse screens use `\.playerOverlayController`). Remove the injections, then run the UI tests: a reader that was missed would crash at runtime.

## 4. Polish findings the lean pass did not cover

The polish pass ran as six implement-only agents with short checklists. It covered:
- the shared kit on every screen: shelf headers, `.cardPress` / `.dimPress`, title styles, context menus, empty and error states, `Indexed`;
- the poster → detail zoom transition;
- `EPGNowNextSlot`, and hiding guide entry points while the guide is off;
- haptics on favourites, season changes and guide day chips;
- labels on the detail stars and the icon buttons it touched;
- `AppLocale` formatting in the detail, downloads, settings and guide views;
- the guarded review prompt.

It did **not** go through the findings below one by one. Many are partly done by the waves before it. For each one:
1. Read the full text in `ios-browse-native-findings.md`.
2. Check the current code.
3. Implement what is missing, within the decisions.

Typical gaps:
- Dynamic Type: scaled caption blocks and fixed heights that hold text.
- VoiceOver: one element per card with a useful label, header traits, named actions.
- RTL: mirroring of chevrons and the guide.
- iPad: readable widths and regular-width layouts that are not "leave alone".
- iOS 26: scroll edge effects, toolbar grouping where decided.
- Design tokens: corner radius and spacing scale.

### Haptics and touch feedback (12)
- `haptics-touch-feedback-1` — Xtream channel, movie and series cards have no context menu: a long press is just a slow tap, and a live channel can only be favourited from inside the player *(owner decision flagged)*
- `haptics-touch-feedback-2` — Cards, shelf headers and detail buttons answer a press in three different ways and the artwork itself never reacts *(owner decision flagged)*
- `haptics-touch-feedback-3` — Episode rows are not buttons: the thumbnail and the row padding are dead, only the text column reacts, and nothing highlights
- `haptics-touch-feedback-4` — Live results in Search and every Downloads row use a plain button inside a List: no row highlight and only the icon and text are tappable
- `haptics-touch-feedback-5` — Continue Watching cards use onTapGesture: no pressed state, no button trait, and a single item cannot be removed from history *(owner decision flagged)*
- `haptics-touch-feedback-6` — The download button ignores taps in three of its five states; cancel and delete exist only behind an undiscoverable long press, and the compact variant is about 29 x 28 pt
- `haptics-touch-feedback-7` — Several primary touch targets are well under 44 pt: shelf headers, filter and day chips, season chips, Show more, the settings header refresh glyph
- `haptics-touch-feedback-8` — The M3U long-press menu is built when the card renders, not when it opens: the favourite label goes stale and every card body parses its stream URL
- `haptics-touch-feedback-9` — Outside the player the app is haptically silent: favourite toggles, custom chip selection, sync results and errors give no feedback *(owner decision flagged)*
- `haptics-touch-feedback-10` — TV Guide touch handling is hand-rolled: a channel tap gives no feedback, the schedule hides behind a silent 0.5 s hold, programme cells and schedule rows do not highlight *(owner decision flagged)*
- `haptics-touch-feedback-11` — Playlist rows: delete goes through onDelete plus a confirmation alert, Edit is only a leading swipe, and there is no long-press menu *(owner decision flagged)*
- `haptics-touch-feedback-12` — Account values in Settings cannot be copied: a long press on server URL, username or source URL does nothing

### Native-app reference comparisons (16)
- `native-reference-1` — Returning from a movie or series detail to a paginated grid re-runs the sort and resets the rendered window to the first 90 items, so the user loses their scroll position
- `native-reference-2` — Movie and series detail replace content they already have (poster, title, rating) with a full-screen spinner, and with a full-screen error when the info request fails
- `native-reference-3` — No Xtream card has a context menu: long-pressing a channel, poster, history card or search row does nothing (or just plays) *(owner decision flagged)*
- `native-reference-4` — The tab bar is hidden on twelve pushed browse screens but not on the detail screens behind them, so it leaves and returns as the user drills in; the iOS 26 minimise-on-scroll behaviour is not adopted *(owner decision flagged)*
- `native-reference-5` — Grid cells are centre-aligned, so posters and channel icons in one row sit at different heights whenever one title wraps to two lines
- `native-reference-6` — The Search tab uses hand-made filter chips, an empty 'type 2 characters' idle screen, no suggestions or recent searches, and a different matcher and sort order than every in-tab search *(owner decision flagged)*
- `native-reference-7` — Shelf headers render in the accent colour and differ from the Continue Watching header in size, colour and left edge
- `native-reference-8` — Horizontal shelves scroll freely and stop mid-poster; they do not snap to an item edge the way Apple's shelves do
- `native-reference-9` — Posters push their detail screen with the plain slide; the iOS 18 zoom transition that keeps the artwork on screen is not used *(owner decision flagged)*
- `native-reference-10` — Several tap targets are bare tap gestures: Continue Watching cards have no pressed state, and an episode's thumbnail is not tappable at all
- `native-reference-11` — The three home tabs each carry their own search field next to the Search tab; on iPad the bar shows two magnifier buttons side by side *(owner decision flagged)*
- `native-reference-12` — Adding a playlist opens a full-height sheet with two rows and then a second sheet after a fixed 0.2 s delay, where a pull-down menu on the + button is the system pattern
- `native-reference-13` — Browsing gives no haptic or symbol feedback: favorite toggles, scope and season chips and download actions change state silently
- `native-reference-14` — Filter entries in the sort/filter menus are Buttons with a hand-placed checkmark, and the menu closes after every toggle
- `native-reference-15` — Settings value rows are hand-built HStacks: values cannot be copied and do not reflow at large text sizes
- `native-reference-16` — No keyboard shortcuts or menu commands on iPad: the iPadOS 26 menu bar and the hold-Command overlay show only system defaults

### iPad adaptivity (13)
- `ipad-adaptivity-1` — Poster, shelf and grid sizes are computed once from UIScreen.main, so iPad Split View, Slide Over and resized iOS 26 windows keep full-screen iPad sizes (a single 200 pt poster column at 320-375 pt)
- `ipad-adaptivity-2` — Multi-window is enabled by the generated scene manifest, but catalog, EPG and orientation state are process singletons, so a second iPad window breaks the first *(owner decision flagged)*
- `ipad-adaptivity-3` — Pushed screens hide the tab bar on iPad too, where it sits in the navigation bar row: tab switching disappears on some screens and stays on others
- `ipad-adaptivity-4` — On iPad the top bar shows two identical magnifiers (Search tab and in-tab filter) and the three browse actions collapse into an untitled overflow menu
- `ipad-adaptivity-5` — The detail hero is a fixed 380 pt and the content below it has no maximum width: it fills an iPhone screen in landscape and stretches the Play button and plot across a 13-inch iPad
- `ipad-adaptivity-6` — An 11-inch iPad shows no more posters per screen than an iPhone, and the fixed-size cards float inside wider adaptive columns *(owner decision flagged)*
- `ipad-adaptivity-7` — Settings forms, result lists and a few controls stretch edge to edge on iPad instead of keeping a readable width
- `ipad-adaptivity-8` — No browse card, chip or custom button reacts to the pointer; the only two hoverEffect sites are in the player
- `ipad-adaptivity-9` — There are no keyboard shortcuts while browsing: no Cmd-F, Cmd-R or Cmd-1...5, although the player already handles hardware keys
- `ipad-adaptivity-10` — The sidebar offered by .sidebarAdaptable only repeats the five tabs (two for M3U) while Favorites, History, Downloads and the playlist switch stay behind toolbar buttons and Settings *(owner decision flagged)*
- `ipad-adaptivity-11` — The category jump picker opens as a centred modal sheet on iPad; its medium detent only applies in compact width *(owner decision flagged)*
- `ipad-adaptivity-12` — The TV guide always uses its compact metrics, so iPad gets the 104 pt channel column that truncates names; the regular variant in the code is never selected
- `ipad-adaptivity-13` — In iPhone landscape the horizontal shelves are probably clipped at the safe-area edges instead of running to the screen edges

### Accessibility, Dynamic Type, RTL (14)
- `accessibility-dynamic-type-rtl-1` — Movie and series shelf titles are cut to one line on iPhone at the default text size (and clipped at accessibility sizes) because the fixed shelf height reserves only 32 pt for the caption
- `accessibility-dynamic-type-rtl-2` — Text under posters and on the rating badge is set in fixed 9-10 pt fonts that ignore Dynamic Type, the badge loses contrast on bright posters, and the Director/Cast labels use the tertiary label colour
- `accessibility-dynamic-type-rtl-3` — Card text columns are as narrow as 58 pt (channels) and 100 pt (posters) on iPhone and never widen with the text size; the EPG now-line under a channel has a fixed 22 pt height *(owner decision flagged)*
- `accessibility-dynamic-type-rtl-4` — VoiceOver reads movie and series cards as star glyph, rating, then title, never mentions watch progress, and reads the detail meta row as five separate fragments
- `accessibility-dynamic-type-rtl-5` — Six tappable surfaces are built with tap gestures instead of buttons, so VoiceOver does not announce them as actionable and Voice Control, Switch Control and Full Keyboard Access cannot target them
- `accessibility-dynamic-type-rtl-6` — Seven icon-only buttons have no label of their own: the Favorites link and the favourite toggles rely on the star symbol's system description, with no on/off state and not in the in-app language
- `accessibility-dynamic-type-rtl-7` — The selected search filter, season and guide day are shown by colour only, and the sort menus draw their own checkmarks, so the current selection is never announced
- `accessibility-dynamic-type-rtl-8` — Shelf titles and detail section titles are not marked as headings, so VoiceOver users cannot jump between categories and must swipe through every card of a shelf
- `accessibility-dynamic-type-rtl-9` — Opening and closing the in-window player posts no screen-change to VoiceOver, so focus is left on a card that has just been hidden and is not brought back afterwards
- `accessibility-dynamic-type-rtl-10` — Actions that exist only behind a long press (favourite an M3U channel, cancel or delete a download, open a channel's schedule) have no accessibility action
- `accessibility-dynamic-type-rtl-11` — Arabic chosen inside the app is applied only through the SwiftUI layoutDirection, and three strings plus one glyph ignore language and direction *(owner decision flagged)*
- `accessibility-dynamic-type-rtl-12` — The TV guide, the channel schedule and several list rows use fixed frames and one-line limits that do not reflow at large text sizes
- `accessibility-dynamic-type-rtl-13` — Posters and logos loaded through CachedImage are exposed to VoiceOver as unlabeled images and are inverted by Smart Invert
- `accessibility-dynamic-type-rtl-14` — Reduce Motion is honoured in the player but not in browsing: the detail hero keeps its parallax and zoom and the playlist-to-dashboard switch keeps its slide

### iOS 26 design (16)
- `ios26-design-1` — The floating tab bar is hidden on category, All and history grids but comes back on detail screens, so it slides in and out at every level of a drill-down. *(owner decision flagged)*
- `ios26-design-2` — Three or four icon-only toolbar buttons are fused into one glass group with forced semibold weight and an accent-tinted star, and on iPad they collapse into an overflow whose items have no titles. *(owner decision flagged)*
- `ios26-design-3` — Shelf headers render in the accent colour although the code asks for `.primary`, because the header NavigationLink keeps the default tinted button style. *(owner decision flagged)*
- `ios26-design-4` — After scrolling, the collapsed title and status bar sit on blurred but still readable poster captions and rows, and the only custom bar styling is a forced `.toolbarBackground(.visible)`.
- `ios26-design-5` — The detail hero shows a hard seam with a blurred colour band below it whenever the backdrop falls back to the blurred poster.
- `ios26-design-6` — The detail call-to-action and secondary buttons are hand-drawn (gradient, coloured glow, trailing chevron, material boxes with hairline strokes) instead of system button styles. *(owner decision flagged)*
- `ios26-design-7` — The Favorites type picker sits on a hand-made material band that paints a hard two-tone block over the navigation area.
- `ios26-design-8` — Global search filters are hand-made chips on an opaque strip with a Divider instead of system search scopes.
- `ios26-design-9` — Selecting the Search tab shows an empty placeholder page and needs a second tap on the morphed field before typing. *(owner decision flagged)*
- `ios26-design-10` — On iPad the top bar shows two magnifying-glass buttons side by side: the Search tab and the current tab's own filter field. *(owner decision flagged)*
- `ios26-design-11` — Season selector and TV Guide day selector are hand-drawn capsules with different metrics instead of a system toggle-button style.
- `ios26-design-12` — The sort/filter toolbar button uses a circle-outlined symbol, which draws a ring inside the round glass button on iOS 26.
- `ios26-design-13` — The two-option playlist type picker opens as a full-height sheet, and the category picker's opaque list background covers the system glass at medium height. *(owner decision flagged)*
- `ios26-design-14` — Category and All grids never show how many items they hold; iOS 26 has a system subtitle slot for that.
- `ios26-design-15` — Artwork corner radii are an unrelated set of values and look tight next to the iOS 26 bar and list shapes; search result thumbnails end up square. *(owner decision flagged)*
- `ios26-design-16` — `tabViewBottomAccessory` is the system home for a mini player on iOS 26, but it cannot replace the app's floating video card; keeping the card is an owner decision. *(owner decision flagged)*

### Design-system consistency (16)
- `design-system-consistency-1` — Grid rows are jagged: posters and channel tiles in the same row sit at different heights whenever one title wraps to two lines
- `design-system-consistency-2` — Shelf titles render accent blue by accident and the same role (shelf header) exists in three different typographies and two insets *(owner decision flagged)*
- `design-system-consistency-3` — Movie and series shelf titles are cut to one line on iPhone because the caption area is scaled with the poster instead of with the text
- `design-system-consistency-4` — Detail hero: the blurred fallback backdrop bleeds below the hero and leaves a hard seam above the Watch button
- `design-system-consistency-5` — Favorites puts the segmented control on a material slab that spills under the navigation bar
- `design-system-consistency-6` — Watch progress on poster cards is drawn across the top edge of the poster and five different progress bars exist
- `design-system-consistency-7` — Detail components ship hard-coded Turkish text: the trailer button always says "Fragman" and series runtimes end in "s" / "dk"
- `design-system-consistency-8` — Tapping a card feels different on every screen: four different press behaviours for the same kind of card
- `design-system-consistency-9` — Card captions are centred, 12 pt medium on every device, with fixed 9-10 pt sublabels; the channel tile mixes centred name and leading guide line *(owner decision flagged)*
- `design-system-consistency-10` — Horizontal margins come from three sources, so shelves, grids and titles do not share a leading edge *(owner decision flagged)*
- `design-system-consistency-11` — Continue Watching and History use two near-identical landscape cards that differ in every detail and ignore PosterMetrics
- `design-system-consistency-12` — Four hand-built chip styles and three count-badge styles for the same two roles *(owner decision flagged)*
- `design-system-consistency-13` — Colour and symbol use is not semantic: the star means three things in three colours, one toolbar icon is tinted, and filter icons are a circle inside the glass circle *(owner decision flagged)*
- `design-system-consistency-14` — Detail action buttons are custom drawn (gradient, glow, chevron, 16 / 12 pt radii) instead of system button styles *(owner decision flagged)*
- `design-system-consistency-15` — Nine corner radii with no scale, and list thumbnails letterbox posters in a square with two stacked clips
- `design-system-consistency-16` — Shelf, card and grid code exists in four copies; a small shared kit would enforce the above without a redesign

## 5. Per-finding verification (not done)

For every finding in `ios-browse-native-findings.md`, decide against the current code whether it is resolved, partly resolved, not resolved, or left by decision. Put the result in a table: id, status, evidence (file:line), what is still wrong. Then fix the small gaps.

Rules for the check:
- Work from the code, not from the report.
- Where the verifier's verdict is "partly", the corrected claim describes the real problem.

## 6. Measurements and device checks not done

- **Film detail push/pop timing.** Not measured after the change: the scratch measuring harness could not pop the new detail.
- **Instruments on a device** with a large catalog (100k+ items): cold launch, home and grid scrolling, tab switches, detail push/pop with the zoom transition, search typing.
- **Simulator numbers so far** (relative only):
  - launch: worst main-thread stall 113 → 23 ms;
  - search: results settle 1.16 → 0.32 s after the last key;
  - scrolling and tab switches: unchanged within noise;
  - category push: a bit slower (61 → 86 ms); pop: faster (93 → 74 ms).
- **Device tour.** The ten-point list in section 7 of `ios-browse-native-fix-report.md`.

## 7. Decisions taken for the owner (binding defaults used in this work)


The audit flagged many findings as needing the owner's decision. The owner asked for a native, fluid feel and is not available to answer each one, so these defaults apply: plain fixes are done, system conventions are adopted where the change is small and reversible, and product-level changes are left alone and reported. When a finding in your file says "DECISION" or "owner decides", look it up here first. If it is not covered, implement only the part the verifier calls a plain fix (or "no decision needed") and report the rest as skipped.

### Adopted
- A1. The tab bar stays visible on every pushed browse screen: `.toolbar(.hidden, for: .tabBar)` is removed from the browse grids, the history list and M3U favourites. The TV Guide keeps hiding it.
- A2. Shelf headers are label-coloured (never the accent colour), `.title3` bold, `chevron.forward` in `.secondary`, same leading inset as the shelf content. One shared `ShelfHeader` (kit) for every shelf including Continue Watching.
- A3. Poster titles (movies, series): two lines reserved, leading-aligned under the poster. Channel tiles: two lines reserved, centred; the now / next line under a channel tile is centred to match.
- A4. Grid columns are top-aligned (`GridItem(..., alignment: .top)`).
- A5. Context menus. Live channel card: Play, Add / Remove favourite, Schedule (only when the playlist has a guide). Movie and series card: Add / Remove favourite. History cards: Play, Remove from history. Favorites screen cells: Remove from favourites. Shelf header: Hide category. No Download, Share or Copy link in card menus, no custom preview (set the preview content shape only).
- A6. Press feedback: cards use the shared `.cardPress` button style; rows, chips and text buttons `.dimPress` (kit).
- A7. Search tab: system search scopes (`.searchScopes`) instead of the hand-made chips; one matcher and one ranking everywhere (`CatalogTextSearch`); the two-character minimum and the 250 ms debounce stay. No recent searches, no activation on tab selection.
- A8. Per-tab inline search fields stay. Tab roots use `.navigationBarDrawer(displayMode: .automatic)`; pushed lists keep their field as it is; the two Recently Added lists (20 items) lose theirs.
- A9. Sort / filter menus: `Toggle` rows for multi-select filters, `.menuActionDismissBehavior(.disabled)` on the filter section only, 'Clear filter' without the destructive role, the sort choice stays global. Exception: the two Recently Added lists (Movies, Series) always stay newest first and do not offer the sort picker (their filter section stays).
- A10. Empty and no-result states: `ContentUnavailableView` with `L()` strings (the in-app language), through the shared kit view. Never `ContentUnavailableView.search(text:)` (it follows the system language).
- A11. Errors shown to the user go through the shared `NetworkErrorText` helper (kit); no raw `localizedDescription` in red.
- A12. Destructive confirmations (Settings, playlist deletion): `confirmationDialog` attached to the row, destructive button reusing the action's title.
- A13. Xtream adult-content toggle: ask with a confirmation dialog before the re-download, then run it with the new value.
- A14. Detail screens never replace the page with a spinner or an error; loading and failure are local to the missing part. The favourite star toggles optimistically, with a symbol transition and a light haptic.
- A15. Detail action buttons keep their current look (gradient primary button) but lose the trailing chevron, gain a pressed state and a localised trailer label. No move to system button styles.
- A16. Download button: non-idle states open a `Menu` on tap; the compact variant has a fixed 44 pt slot.
- A17. Add playlist: a `Menu` on the + button and one sheet; `PlaylistTypeSelectionView` is no longer presented.
- A18. Language change: the root rebuild stays, but the app comes back on the Settings tab.
- A19. Thumbnail disk cache of 300 MB (image lane).
- A20. iPad: `PosterMetrics` follows the window size. (The single-window scene setting is applied by the orchestrator.)
- A21. Haptics (`sensoryFeedback`): light impact on favourite toggles, selection on scope / chip / season changes, success / error on sync results. Nothing on destructive alerts.
- A22. Zoom transition from a poster to its detail screen (movies and series; shelves and grids), in the polish wave, behind one constant so it can be switched off.
- A23. Channel logos keep a tile under the loaded logo (`showsTile`), in the placeholder's adaptive colour.
- A24. The favourite star keeps today's colours (yellow when on). Toolbar icons lose the forced font weight and the accent tint, and every icon-only button gets a label in the in-app language.
- A25. 'Hide category' means hidden everywhere: the TV guide does not list channels of hidden categories and playback started from the guide or a programme sheet does not queue them (Search and the M3U player already behave this way).
- A26. 'Show TV guide' off really switches the guide off for that playlist: no now / next lines, no Guide button, no minute timer. The stored guide data is kept, so switching it back on is instant. (The player's programme line reads the same snapshot and goes with it.)
- A27. One app locale: `AppLocale.current` = the in-app language with the device's region and preferences. Plural rules, dates, times, sizes, percentages and ratings are formatted with it; digits follow the device region, as the system does. The in-app language picker stays.
- A28. M3U history and Continue Watching cards whose channel is no longer in the playlist: an alert that offers 'Remove from History'. No automatic pruning on re-import.
- A29. In the M3U guide a channel tap plays the channel (as on Xtream) when the row resolves to a channel of the playlist, and the programme sheet offers 'Play channel'; the schedule stays reachable. When the row does not resolve, today's schedule fallback stays.
- A30. Series detail: playback started from the series page goes through `HistorySeriesPlayerShell` (as Continue Watching and Downloads do), so next / previous / auto-advance no longer depend on the page still being on screen. The page follows playback to another season only when it was showing the season that was playing.
- A31. A playlist whose guide refresh has completed and matched none of its channels does not reserve the now / next line under its channel cards.

### Leave alone (owner decisions; do not implement)
- L1. List-style channel rows, larger channel tiles, capped shelves with a See All tile, removing per-tab search, a Library tab, an in-dashboard playlist switcher, regrouping Settings into sub-pages, moving 'Back to Playlists'.
- L2. Continue Watching de-duplication, 'Up Next' semantics, 16:9 episode thumbnails, a season menu instead of chips (only hide the chip bar when there is a single season), a 'go to current episode' control.
- L3. Guide: hiding channels without guide data, a new channel column on iPhone.
- L4. Auto-open after import, optional playlist name, background catalog refresh and 'updated ...' subtitles, pause / resume for downloads, remembering the download warning.
- L5. Mini player: reserving scroll room, dock positions, a now-playing badge, a bottom accessory, VoiceOver order.
- L6. iPad poster density, a sidebar Library section, the category picker as a popover, keyboard shortcuts.
- L7. `tabBarMinimizeBehavior`, `tabViewSearchActivation`, removing `.toolbarBackground(.visible)`, the memory-cache size, monogram placeholders, system button styles for the detail actions, an app accent colour.
- L8. M3U: a Search tab, sort / filter and All Channels, poster-style cards for VOD groups, a grid for single-group playlists.
- L9. Anything that needs a change in the player files.
- L10. Download lifecycle (a download that finished while the app was not running, the order of the background completion handler), the M3U download-in-progress warning, the moment of the App Store review prompt (only its guards may be added), keeping fetched seasons across a catalog refresh, remembering the sort per category or per playlist, replacing the in-app language picker with the system setting, compile-time gating of the demo fixture, reselect-tab and status-bar-tap handling.

## 8. Codex continuation — 2026-10-02 (work in progress)

This section supersedes the open/closed status of the specific items below. It is **not** a completion claim for the 358-finding audit. Changes are uncommitted. The separate audio/AirPlay work advanced HEAD to `c38be16` during this session; those changes were not authored as part of this continuation.

### Completed-review notes (section 2)

| Item | Current state | Evidence / remaining limitation |
|---|---|---|
| 1 — movie shelf prefetch | Fixed | `VODCategoryShelfRow.movePrefetch` keeps the exact queued URLs and decode dimensions; updates stop/start only changed requests. |
| 2 — Recently Added placeholder | Fixed | Movies already used `RecentlyAddedReservation`; Series now uses and records the same per-playlist rule. Fixture reset clears both flags. |
| 3 — series shelf prefetch | Already fixed in baseline | `SeriesCategoryShelfRow.queuedPrefetch` and `SeriesBrowse.prefetchChange`; existing prefetch tests retained. |
| 4 — blank episode cover | Fixed | `SeriesDetailData.playbackSeed` falls back for nil, empty, whitespace and newline covers; parameterized regression test. |
| 5 — synchronous season reads | Fixed | `SeasonEpisodesObserver` uses asynchronous GRDB scheduling, retaining previous rows until delivery; test now checks that transition. |
| 6 — failed season observation | Fixed | Failure clears the subscription guard and logs the error; later appearance can subscribe again. |
| 7 — M3U favorites during catalog loading | Fixed for the reported scenario | `M3UFavoritesView.RecomputeKey` includes active playlist/loading state; no catalog scan is applied before it is ready. Initial loading of the separate favorites store itself is not redesigned. |
| 8 — empty M3U pull-to-refresh | Fixed | Local `isRefreshing` preserves the empty scroll view while refresh runs. |
| 9 — cancellation inside one huge group | Fixed | `M3UGroupSearch.run` checks cancellation every 2,048 channels. |
| 10 — duplicate history removal | Fixed in callers | Uses `history.item.remove` and `DBWatchHistory.remove`. Old unused translation keys retained under the rule forbidding edits to existing keys. |
| 11 — stale M3U settings row | Fixed | `finishSync` re-reads after stats/catalog awaits before assigning `current`. |
| 12 — download bar drains on removal | Fixed | `DownloadProgressFooter` retains the last live progress while the row leaves. Missing live progress disables interpolation; stored bytes are only the initial fallback. |
| 13 — download placeholder tint | Fixed | Explicit `Color.primary` at the download label root. |
| 14 — film metadata placeholder never ends | Fixed | Baseline had `FetchPhase` but never assigned it. The request now sets running/idle; an already-loaded row also sets idle. |
| 15 — compact download alignment | Already fixed in baseline | `DownloadButton.label` anchors the 44 pt slot at `.topTrailing`. |

### Concrete gaps (section 3)

1. Movie and series detail stars now read/write `XtreamFavoriteStore`; their single-row query remains a first-frame fallback. The protected live-player writer remains unchanged.
2. Download failures use `NetworkErrorText`; diagnostic log lines keep underlying errors.
3. Both settings screens and EPG settings use `NetworkErrorText`. Catalog store failures use it too, so guide retry text is localized.
4. Removed unused `applyVODMetadata` and the test of that removed API. Catalog/metadata separation remains.
5. Favorites uses `VODStreamCard`, `SeriesCard`, and `LiveStreamCard`; removed private duplicate cards.
6. Movie/series progress uses the shared bottom-overlay `CardProgressBar`.
7. `BrowseDetailPresence` tracks the visible detail with ownership tokens. Tab-root detail requests do not push that same item again. Ownership/type/playlist separation has a regression test; the complete player-to-card navigation flow still needs runtime verification.
8. Guide catalog failure offers a reason and retry. Hidden-category wording is neutral and added in all ten languages.
9. M3U Download menu retained by the existing binding decision.
10. Removed the three obsolete `.environmentObject(playerOverlay)` injections; the value environment injection remains. No `@EnvironmentObject PlayerOverlayController` readers were found.

### Additional polish corrections

- Shared poster shelf height reserves caption space scaled by Dynamic Type; skeletons and loaded shelves use the same modifier. Card category subtitles use `.caption2`.
- Zoom transitions respect Reduce Motion, as do playlist/dashboard animations. Detail hero parallax already respected it in the baseline.
- Programme cells in the two-axis guide now use real buttons with the shared dim press style; empty cells remain inert.
- Demo fixture reset also clears persisted Recently Added reservation flags.

### Verification and outstanding scope

- Initial compilation caught and corrected an overly broad edit to the M3U loading predicate; the protected player-shell predicate is restored.
- The full test attempt built successfully, but the unrelated `AudioOutputRecovery.stoppedEngineRestartsAfterConfigurationChange` test failed in `SelectedCastTracksTests.swift:526`. That run was interrupted; it is not a green full-suite result.
- Focused browse run: **201 unit tests in 15 suites passed**; **6/7 browse UI tests passed**. `test_search_listsPrefixMatchesFirst` typed into the Live tab’s `Search channel...` field rather than the global search field; the isolated rerun passed. The other global-search scope test passed. Log: `/private/tmp/iptv-browse-focused.log`. The final download-progress retention view was verified in the final build below.
- The six review areas have received targeted inspection, **not** a completed independent review of every changed line. The complete polish review, 358-row evidence table, repeated detail push/pop measurements, Instruments recording, and physical-device tour remain open. No device performance claims are made.
- No commit, push, player-code edit, scheme/Fastfile edit or tip-jar change was made by this continuation.

### Final verification of this batch

- Final build/test completed with exit code 0 on iPhone 17 Pro, iOS 26.0.
- `DownloadsSectionsTests`, `NetworkErrorTextTests`, and the isolated `BrowseBehaviourUITests/test_search_listsPrefixMatchesFirst`: **26 tests passed, 0 failures** (59 executions counting parameterized cases).
- Result: `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.02_23-19-03-+0300.xcresult`.
- Earlier focused run: 201 unit tests passed; six browse UI tests passed together, and the seventh passed in the isolated final run. The initial search UI failure is retained above rather than reported as a wholly green original run.
- `git diff --check` passed. Both new guide localization keys exist exactly once in each of the ten language files.
- The broad audit and physical-device work listed above remain unfinished; this batch closes the concrete code corrections, not the entire handoff.

## 9. Codex continuation — second review batch, 2026-10-02

This batch reviews the guide refresh path, M3U parsing/import, M3U favourites/grid invalidation, and the localisation cache. It does **not** close the six-area review, the 87 polish findings, or the 358-finding verification task. Changes remain uncommitted.

### New defects corrected

- **Guide validators belonged to the wrong source.** `EPGRefreshCoordinator.refresh` sent the stored ETag/Last-Modified to every candidate URL, including a changed override and fallback hosts. They now go only to the exact URL of a previously successful source. An unsolicited 304 without that source cannot record a successful refresh. Stubbed HTTP tests cover unchanged URLs, changed URLs, fallback URLs and unsolicited 304.
- **Guide cancellation was treated as failure.** Cancelled work could try more URLs and write an error/cooldown state. Cancellation is now normalised and propagated; staging is discarded without replacing the live guide. Tests cancel at parsing and verify no fallback request, no error overwrite, and preservation of the stored guide. The initial attempt timestamp can still be written before cancellation; no claim is made that every bookkeeping column is untouched.
- **Guide database failures were hidden as cancellation.** When a staging insert failed, the parser reported its aborted callback before the coordinator inspected the actual write error. The coordinator now rethrows the database error. A SQLite trigger injects a staging failure and verifies the previous guide survives.
- **M3U favourites leaked between playlist sessions.** Switching playlists now clears the previous IDs immediately. Generation-checked asynchronous observations reject stale deliveries. First-read state is explicit, so the favourites screen does not claim the list is empty before reading it. Failed observations expose a localised error and can be retried for the same playlist. Tests use isolated databases, including a temporary table rename to simulate observation failure and recovery.
- **Tapping an M3U favourite did not play.** The unlabelled trailing closure of `M3UGroupGridContent` bound to `onScheduleRequested`, leaving `onChannelSelected` nil. The call now names the playback argument. `M3UFavoritesBrowseUITests.test_favoriteChannelTapPresentsPlayer` exercises the rich M3U fixture and asserts the player appears.
- **M3U grids ignored changes in their middle.** Their equality check used only row count and endpoint IDs. Catalog grids now include the applied playlist/revision/query; favourites use an applied-result revision. This detects refreshed metadata and changed interior selections without comparing a catalog-sized array on the main actor. Regression tests keep the same endpoints and row count.
- **Cancelled M3U work kept consuming CPU.** Parser and import-row preparation now use `@concurrent` entry points that inherit caller cancellation instead of detached tasks. Parsing, continuation joining and channel hashing check cancellation periodically; import checks again before its transaction. Stable channel IDs and transaction semantics remain unchanged. Tests cover both asynchronous parser entry points and an import cancelled before publication.

The A31 empty-guide behaviour is intentionally retained: a successfully parsed feed matching no channels can publish an empty guide and remove the line reservation. This is different from a parse/write failure or cancellation.

### Incremental finding verification

Only the rows below have evidence from this batch; this is **not** the requested complete 358-row table. Paths are relative to `apps/ios/another-iptv-player/`.

| Finding | Status | Evidence | Remaining limitation |
|---|---|---|---|
| `gap-background-jobs-isolation-1` | Resolved | `EPG/EPGRefreshCoordinator.swift:39` (`@concurrent` refresh); `EPGRefreshCoordinatorTests.aRefreshStartedOnTheMainActorParsesAndWritesOffTheMainThread` | Device Instruments timing remains unmeasured. |
| `gap-background-jobs-isolation-4` | Resolved | `EPG/EPGStore.swift:716`, `EPGRefreshPolicyTests` | Cancellation is now separate from a failed refresh. |
| `gap-background-jobs-isolation-5` | Resolved | `Localization/LocalizationManager.swift:218`, cached bundles/strings/current language under a lock | No new device benchmark in this batch. |
| `gap-localization-runtime-1` | Resolved | `Localization/LocalizationManager.swift:118`, `LocalizationRuntimeTests` Russian/Arabic plural and cached-entry tests | Native system-owned UI language remains outside this claim. |
| `gap-localization-runtime-8` | Resolved | `Localization/LocalizationManager.swift:222`, `:245`, per-language cache with language invalidation | No new device benchmark in this batch. |
| `m3u-browse-1` | Resolved | `Views/M3UChannelsView.swift:895`, shared paginated grid, applied content identity; `M3UGridContentTests` | Large-catalog device scrolling still needs measurement. |
| `scroll-perf-7` | Resolved | `Views/M3UChannelsView.swift:959`, lazy `Indexed(items.prefix(visibleCount))`; applied-result equality | Physical-device hitch measurement remains. |
| `m3u-browse-12` | Partly resolved | `Models/M3UFavoriteStore.swift:24`; `Views/M3UFavoritesView.swift:43` | Favourite initial/error states checked here; re-audit all channel-load and pull-retry paths before closing the entire finding. |

### Next review target

`DownloadManager` deletion/queue ordering needs a deterministic interleaving test. `deleteRow` awaits file deletion before deleting the row, while `pumpQueue` can retain a previously fetched queued row across awaits and calls `startTask` even if its status update found no row. `deleteAll` cancels again after its delete, but individual deletion has no equivalent gate. A suitable fix must coordinate queued-row snapshots, in-flight enqueue, deletion and task startup; do not extend this into the excluded terminated-app/background-completion lifecycle work.

The remaining broad tasks still include shared-kit/forms/polish review, the full per-finding table, accessibility/RTL/iPad visual checks, detail push/pop measurement, and the physical-device tour. No physical-device results are claimed.

### Verification of the second batch

- Final build and selected test run passed on iPhone 17 Pro / iOS 26.0 Simulator: **201 tests, 0 failures, 0 skips** (200 unit tests plus the M3U favourite-to-player UI test; 208 executions including parameterised cases).
- The final selection included EPG coordinator/lifecycle/line reservation/refresh policy/XML parser/row builder, M3U parser/importer/favourites/grid/browse/content store, runtime localisation, mock fixtures, Xtream HTTP decoding, and `M3UFavoritesBrowseUITests`.
- Earlier isolated runs also passed: 57 guide/HTTP tests, 16 M3U/Xtream favourite-store tests, 57 parser/importer/guide tests and the M3U playback UI test. These overlap the final run and must not be added together as unique tests.
- Result: `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.02_23-42-21-+0300.xcresult`; log: `/private/tmp/iptv-browse-review-second-wave.log`.
- `git diff --check` passed. No new localisation keys were needed. This is a targeted run, not a claim that the full player/AirPlay test suite is green; the earlier full-run limitation in section 8 still applies.

## 10. Codex continuation — download mutation review, 2026-10-02

The deletion/start ordering issue identified in section 9 is addressed in this batch.

- Enqueue, individual deletion/cancellation, playlist cleanup, bulk deletion and queue startup now share a FIFO asynchronous gate. The gate spans file removal and database awaits. A new enqueue cannot publish its row or reuse its destination while an earlier delete is still removing the old files. Waiting suspends tasks without blocking the main actor; filesystem deletion remains off-main. Existing network transfers continue; new task starts can wait briefly behind a storage mutation, including one for another playlist.
- Queue startup now requires a successful transactional transition from the same queued row to `downloading`. A missing row, a row whose state/incarnation changed, or a failed database write cannot fall through into `startTask`.
- Concurrent pump requests still coalesce, but callers now wait for the active pass to finish. Follow-up pumping is scheduled after enqueue/deletion releases the gate, avoiding recursive acquisition.
- `DownloadManager` accepts an isolated database, ephemeral session and file-removal function for tests. The app's shared manager retains its background-session configuration and restore pass. Tests pause file removal explicitly and use a URL protocol that cannot reach the network.
- `DownloadMutationTests` covers re-enqueue while individual, playlist-wide and global deletion are suspended, plus a failed queue claim. `DownloadsSectionsTests` covers the associated screen's grouping.

This does not claim to fix the explicitly excluded terminated-app download/background-completion-handler behaviour. The broad remaining work from section 9 is still outstanding.

Additional corrections in this batch:

- The add/edit playlist forms' fallback error now uses `NetworkErrorText` instead of Foundation's device-language description. `PlaylistFormFailureTests` checks the shared localised fallback.
- `MovieDetailView.FetchPhase` is explicitly nonisolated because the nonisolated metadata-state helper compares it. The detail rating uses an actor-inheriting closure rather than passing an actor-isolated formatter method as a bare function value. This preserves the formatter's main-actor cache while removing two concurrency warnings in the touched browse code.

Regression proof: temporarily removing the mutation gate and the successful-claim guard caused both `DownloadMutationTests` methods to fail (the old row was overwritten during deletion, and a rejected queue claim started a task). The fixed implementation was restored immediately afterwards. The intentionally failing result is `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.02_23-50-04-+0300.xcresult`; it must not be mistaken for the final validation run.

Final validation of this batch: **56 tests passed, 0 failures, 0 skips** on iPhone 17 Pro / iOS 26.0 Simulator. Selection: DownloadMutationTests, DownloadsSectionsTests, PlaylistFormFailureTests, ContentRatingTests, DetailComponentsTests and NetworkErrorTextTests. Both rejection and a trigger that removes the row during the attempted update prevent task startup; GRDB rolls the failed transaction back and preserves the queued row. No new concurrency warnings appeared in the final build. `git diff --check` passed.

Result: `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.02_23-52-44-+0300.xcresult`; log: `/private/tmp/iptv-browse-third-wave.log`. Changes remain uncommitted.

## 11. Codex continuation — accessibility and large text, 2026-10-03

### Work completed in this turn

- Reviewed all 14 `accessibility-dynamic-type-rtl-*` findings against the current code, using their corrected claims. The table below distinguishes code corrections from device-only checks.
- Poster rating badges use scalable caption text, capped at `xxxLarge` for the small artwork overlay. The full rating remains in the spoken card label. Director/cast labels now use secondary rather than tertiary colour.
- Movie and series cards expose one title-first accessibility label (title, labelled rating, optional category) and a localised watch-progress value. Rating widgets and the detail metadata row have coherent labels rather than exposing isolated symbol/number fragments. No per-card database observation was added.
- Added heading traits to detail titles and plot sections; shelves and the season section already carried them.
- Added state labels and named actions to download controls, named schedule actions to guide channel buttons, and favourite/schedule accessibility actions to M3U cards. These reuse the existing action implementations and localisation keys.
- Converted the detail poster from a tap gesture to a labelled Button. Its fullscreen viewer's Close button now has a localised label and stable identifier.
- A simulator screenshot at the largest accessibility text size exposed an additional layout failure: the fixed hero overlaid the title on the status/navigation area and wrapped rating/year digits vertically. At accessibility sizes the title and metadata now sit below the artwork, in an intrinsically sized vertical layout. Normal-size presentation is retained. Ratings, years and runtimes stay intact instead of breaking into individual digits.

### Finding verification for this area

Paths below are relative to `apps/ios/another-iptv-player/`. “Resolved” refers to the corrected code claim, not completion of the physical-device tour.

| Finding suffix (`accessibility-dynamic-type-rtl-`) | Status | Evidence | Remaining check / decision |
|---|---|---|---|
| 1 | Resolved | `Views/Components/Browse/CardDecorations.swift`, `PosterShelfFrame`; all six shelf/skeleton call sites in VODView/SeriesView | Broad screenshot coverage across devices remains. |
| 2 | Resolved | `Views/RatingLabel.swift:103`; `Views/Components/DetailComponents.swift`, `DetailInfoTextBlock`; card category and history subtitles already use caption2 | Scrim colour remains unchanged, as instructed. |
| 3 | Partly resolved | `Views/EPG/EPGComponents.swift:60`, scaled now/next reservation | Channel/poster widths still do not grow with text size; wider card density is not introduced here. |
| 4 | Resolved | `Views/Components/Browse/BrowseAccessibility.swift`; VODStreamCard, SeriesCard, DetailHeroMetaRow | Automated UI checks verify movie title/rating/progress; actual VoiceOver pronunciation remains a device check. |
| 5 | Resolved | ContinueWatchingRow and episode/schedule/guide buttons; `Views/Components/DetailComponents.swift:172`, poster Button | Switch Control / Voice Control device tour remains. |
| 6 | Resolved | DownloadButton state label; FullscreenImageViewer Close label; existing dashboard/detail/guide/playlist toolbar labels | State-by-state VoiceOver checks remain. |
| 7 | Resolved | `Views/Components/Browse/FilterChip.swift` selected trait; system search scopes and Toggle filter rows in VOD/Series/Live | No new selection behaviour introduced. |
| 8 | Resolved | Shared ShelfHeader heading trait; detail title and plot heading traits; existing SeriesView season heading | Rotor navigation needs physical-device confirmation. |
| 9 | Not resolved | DashboardView/M3UDashboardView hide covered content but do not post a screen-change notification | The corrected finding requires a VoiceOver device observation before changing focus behaviour. No speculative focus notification added. |
| 10 | Partly resolved | DownloadButton accessibilityActions; M3UChannelCard accessibilityActions; EPGChannelColumnCell schedule action | Verify action discovery and M3U favourite label refresh/announcement with VoiceOver; M3U downloading remains menu-only. |
| 11 | Partly resolved | Detail trailer uses `L`, runtime uses app-locale formatting | English-device + in-app Arabic chrome, gestures and sheet direction still need a run. No global UIKit appearance override added. |
| 12 | Not resolved | EPGGuideMetrics still uses fixed dimensions; ChannelEPGDetailView still has a 52-point time column | Guide, schedule, search/picker rows and settings reflow remain to review/fix. The adjacent detail-hero defect was corrected separately. |
| 13 | Resolved | `Views/CachedImage.swift:220` decorative default and loaded-image Smart Invert exclusion; labelled poster Button | Smart Invert still needs a device run. |
| 14 | Resolved | BrowseTransitions Reduce Motion guard; DetailHero parallax guard; ContentView transition guard | Physical-device motion preference tour remains. |

This is a 14-row addition to the incremental verification, not a claim that the full 358-row table or all 87 polish findings are finished.

### Visual and test evidence

The first 23-test run passed but its largest-text screenshot revealed the hero layout defect above. After correcting the layout, a 24-test run passed (21 unit tests, two accessibility UI tests and the existing M3U favourite playback UI test). The second run's screenshots were exported and visually inspected: the title no longer overlaps the top chrome, and rating/year/runtime each occupy a readable row.

- Before layout correction: `/private/tmp/iptv-a11y-attachments/6E16BA18-BE66-4B4D-BEBD-94F64E614F93.png`.
- After layout correction: `/private/tmp/iptv-a11y-after-layout/F86ECC5F-C647-4D27-9D1A-E8A8D08EC7D4.png`.
- The fixture uses `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`; its effect was confirmed in the screenshot, not merely assumed from the launch argument.
- The UI tests assert the movie card's title-first label, labelled rating, 40-percent value, and navigability at normal and largest text sizes. The normal-size flow also tests opening/closing the fullscreen poster in the final validation run.

Next accessibility pass: start with finding 12 (guide metrics and schedule/search/picker reflow), then verify in-app Arabic and M3U custom-action label updates. Finding 9 remains conditional on a physical VoiceOver observation. This area's current code-status tally is 9 resolved, 3 partly resolved, 2 not resolved; all device-only qualifications in the table still apply.

Final validation: the expanded 31-test run passed 30 tests and exposed one real accessibility defect: the poster was not classified as a Button. Explicit button traits (and removal of its inherited image trait) corrected that. Both accessibility UI tests then passed again, including opening the poster, finding the localised Close button, closing the viewer, and navigating at the largest text size. The 21 unit tests and the other 8 navigation/M3U UI tests passed in the expanded run; these overlapping runs must not be summed as independent tests.

Final focused result: `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.03_00-11-29-+0300.xcresult`; log: `/private/tmp/iptv-browse-poster-a11y.log`. Expanded-run result: `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.03_00-06-14-+0300.xcresult`. `git diff --check` passed. No localisation keys or player files were changed in this batch. Changes remain uncommitted.

## 12. Codex continuation — guide and schedule text sizing (2026-10-03)

- `EPGGuideMetrics.guide` now scales row height, channel-column width, time-axis height and category-header height with caption Dynamic Type (bounded to 1–1.5×). Hour width, day width and precomputed programme X positions remain unchanged. Only the timeline grid caps font sizing at accessibility1; day controls and channel schedules retain the user's full text size.
- `ChannelEPGDetailView` replaces the fixed 52-point time column with a scaled minimum and intrinsic one-line time width. Accessibility sizes switch time/content and title/Now badge to vertical layouts; titles and descriptions allow three lines. The title uses vertical fixed sizing to prevent List compression from forcing it back to one line.
- Programme-cell times stay on one line with bounded shrinking, avoiding split AM/PM characters. Short timeline cells still truncate titles/times by design; full information remains available in the channel schedule/programme detail. The large-text guide toolbar title still truncates with four actions; this pass does not claim every large-text guide issue is closed.
- Added a metrics regression proving larger text preserves programme time coordinates in both width classes. Added a largest-text UI flow through M3U guide → channel Schedule → programme detail.

Validation: the final focused run passed **21 tests (20 unit + 1 UI), zero failures**, on iPhone 17 Pro / iOS 26.0. Result: `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.03_00-28-56-+0300.xcresult`; log `/private/tmp/iptv-guide-a11y-final.log`. The first run passed all 20 unit tests but selected a partly offscreen schedule cell in the UI test; the test now selects the programme button and checks the detail Close control. That run's screenshots also exposed the compressed title and broken time wrapping, corrected before the final run.

Final screenshots exported and visually inspected: `/private/tmp/guide-a11y-final-images/C2829497-D44A-4BA9-BD82-F5F0A5A7E2F3.png` (guide), `/private/tmp/guide-a11y-final-images/A8AF8429-7894-4B9B-B58D-F1F45F53F39C.png` (schedule). Schedule times are intact, content reflows vertically, and programme titles can wrap. These are simulator checks; no physical VoiceOver, iPad or RTL claim is made.

Accessibility finding 12 advances from **Not resolved** to **Partly resolved**. Search/category-picker rows, settings reflow and guide toolbar crowding remain. The incremental accessibility tally is now 9 resolved, 4 partly resolved, 1 not resolved, retaining the device-only qualifications from section 11. The full 358-row verification and remaining polish/review work are still outstanding. No protected player/tip/scheme/Fastfile work or localisation keys were changed in this batch. Changes remain uncommitted.

## 13. Codex continuation — search and category-picker text sizing (2026-10-03)

- `SearchView.ResultRow`: accessibility text sizes now allow three title/category lines and put category and rating on separate rows. Vertical fixed sizing prevents list compression. Thumbnails align with the top of the text; catalogue search, ranking and navigation logic are unchanged.
- `CategoryPickerSheet`: accessibility sizes allow three category-name lines and move the content count below the name instead of reserving trailing badge width. Normal sizes keep the system badge, including zero counts. The new count uses concrete `Color.secondary`, avoiding the pale accent-tinted text inherited inside a list button.
- Added two largest-text UI flows: search for a seeded movie and open its detail; filter the category picker, select Sci-Fi and confirm dismissal plus the destination shelf. These test navigability; screenshots were also exported and inspected for actual layout.

Validation: all 9 `GlobalSearchTests` methods passed (13 executions including parameter cases). Both new UI tests passed together after a simulator restart in `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.03_00-40-45-+0300.xcresult`. After the final count-colour correction, the category UI test passed again in `Test-another-iptv-player-2026.10.03_00-41-46-+0300.xcresult`. Do not sum overlapping runs. The first run had a test-only wrong capitalization of “Jump to category”, fixed; the second run passed category selection but lost its simulator/application connection during search. No full-suite claim is made.

Visual evidence: search title, category and rating are all readable at the largest text size (`/private/tmp/search-picker-a11y-images/4E21089A-2BD8-4C3E-AD8C-9CE3C3454A28.png`); the final picker count is grey and selection remains usable (`/private/tmp/picker-contrast-images/269B1F39-CC46-4A34-884E-1105BBD58709.png`). Tested fixtures have short category names: longer localized names, hidden-category actions, iPad and RTL still need coverage.

Finding 12 remains **Partly resolved**: settings reflow and guide toolbar crowding are still open, alongside the device checks and complete 358-finding verification. This batch changed only SearchView, CategoryPickerSheet, UserFlowsUITests and this log. No protected files or localisation keys were changed; no commit was created. `git diff --check` passed.

## 14. Codex continuation — settings accessibility verification (2026-10-03)

This batch adds verification, not an application layout change. Reviewed `PlaylistSettingsView`, `M3UPlaylistSettingsView`, `EPGSettingsSections` and `LanguagePickerSection`. The existing system `LabeledContent` stacks labels and values at accessibility sizes; the reviewed Toggle labels wrap their descriptions. No replacement layout was justified by the observed rows.

Added `SettingsAccessibilityUITests` with separate Xtream and M3U flows at the largest Dynamic Type size. Both launch rich fixtures, open Settings, open App Language and return, then scroll to the playlist Name row. Xtream additionally reveals and hides the fixture password, asserting that its accessibility value is populated only while revealed. Screenshots contain no revealed password. The tests do not change player preferences or language.

Final validation: **2 UI tests passed, zero failures**, iPhone 17 Pro / iOS 26.0. Result: `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.03_01-23-55-+0300.xcresult`; log `/private/tmp/iptv-settings-verified.log`. Prior test development runs failed because the first locator targeted the Language section heading and because a read-only selectable Name label was tested for hittability. The final check uses screen geometry for that informational label and smaller scroll gestures. One intervening Xcode run stopped producing output after the runner exited and was terminated; it is not counted as passed. The final run enabled a 180-second per-test timeout.

Images inspected: the initial settings controls and download/storage labels, long player-preference descriptions, and final Name rows in both playlist types. Final Name screenshots: `/private/tmp/settings-verified-images/8D058E61-179A-4F6E-A265-ECFEAAA3D7C5.png` (M3U), `/private/tmp/settings-verified-images/30F3A5AD-8750-4BB1-A3A0-BC4B7F0293D0.png` (Xtream). No clipping was found within these row layouts; ordinary scrolling beneath system chrome remains.

Scope limits: this does **not** close all settings reflow. Long source URLs, EPG editing/status/error states, lower statistics/about sections, longer localized labels, RTL and iPad remain unverified visually. Finding 12 stays partly resolved, as do the wider audit and device requirements. Only UI tests and this handoff were changed in this batch; production/protected files were untouched and no commit was made. `git diff --check` passed.

## 15. Codex continuation — guide toolbar at accessibility sizes (2026-10-03)

`EPGGuideView` now places its existing four actions in the system bottom toolbar at accessibility Dynamic Type sizes. The guide already hides the tab bar, so this makes room for the inline navigation title without removing actions or putting them behind an extra menu. Standard text sizes retain top-trailing placement. Category expansion, search presentation, jump-to-now, refresh behaviour and disabled states are unchanged; no new localisation keys were needed.

Added `GuideToolbarAccessibilityUITests` at default and largest text sizes. Both assert all four actions are hittable and in the expected screen region, collapse and expand categories, invoke Now, and open Search. Refresh is verified as an accessible control but is not invoked against the demo network source.

Validation: 20 `EPGGuideRowBuilderTests` passed in the initial run. Both toolbar UI tests passed in the final run, `/private/tmp/iptv-browse-review/Logs/Test/Test-another-iptv-player-2026.10.03_01-33-55-+0300.xcresult` (log `/private/tmp/iptv-guide-toolbar-final.log`). The initial largest-text test incorrectly required the bottom controls to be descendants of XCUIElementTypeToolbar; the final test finds the buttons and checks their actual vertical location. This is 22 distinct passing tests across overlapping runs, not a full-suite result.

Exported and inspected both final screenshots: `/private/tmp/guide-toolbar-final-images/6EE3265E-1CAC-4459-8CB1-F38CD9B40F7B.png` (default) and `/private/tmp/guide-toolbar-final-images/B043026A-2610-4787-BB4B-A0E239444D23.png` (largest). The largest-text title is now fully visible instead of “TV…”, with all four actions visible below the grid. The bottom bar consumes some vertical space, intentionally trading a small amount of visible programme area for readable navigation.

This closes the English iPhone guide toolbar crowding observed in section 12. Finding 12 remains partly resolved pending the settings cases listed in section 14, longer localised content, iPad/RTL and device checks. Only EPGGuideView, UserFlowsUITests and this log were changed in this batch; protected work remains untouched, no commit created. `git diff --check` passed.

## 16. Unattended completion pass — 2026-10-03 (closed with explicit remaining work)

The owner requested continued work through the entire remaining list while AFK. The 358-row working-tree verification is now in `ios-browse-native-verification.md`. It distinguishes corrected claims, implementation, binding scope decisions and missing runtime evidence. It supersedes optimistic completion language in the original fix report; partial/open findings are not counted as resolved.

Changes in this pass:

- M3U import marks the atomic save phase as committing, so Cancel/dismiss cannot interrupt the noncancellable database operation.
- Settings observes download database revisions and recomputes storage usage after background progress/completion changes.
- Compact Arabic guide actions move to the bottom bar, as they already do at accessibility text sizes. English-device + in-app Arabic guide/schedule UI flows passed on iPhone and iPad simulators. The final Release run also passed the compact RTL toolbar correction.
- Added privacy-safe signpost intervals for catalog load/unload, movie/series recomputation, search, guide loading/row building and now/next ticks. Async intervals measure elapsed time to result, not main-thread CPU time.
- Added a Release XCTest cached movie push/pop measurement. Initial samples: 4.55702618, 4.585630855, 4.549753067 seconds. These include XCUI tap dispatch, idling and assertions; they are NOT animation duration, hitch rate or physical-device performance. The initial Release attempt failed because testability was disabled; the successful run used `ENABLE_TESTABILITY=YES` without editing the scheme/project.
- Removed the dead `FASTLANE_SNAPSHOT` fixture branch; explicit `-UITests` gating remains available in optimized builds under L10.
- Rich/large fixture artwork uses a deterministic textured JPEG URLProtocol through the real Nuke loader, limited to four simultaneous renders; loading-thread callbacks are synchronous and cancellation is guarded. Demo/snapshot URLs remain unchanged. No network-latency simulation is claimed.
- Rich/large panel fixtures now return deterministic account data and HTTP 503 for unsupported endpoints through the real client decoder. This preserves missing-season/refresh failure coverage without example.com traffic; demo transport remains unchanged.
- Movie metadata updates fetch the current stored row before applying detail fields, preserving refreshed names/categories/transport fields and other playlists. Movie/series headers expose newly received metadata before a busy database writer commits; series episodes still await persisted rows.
- Continue Watching adopts the first, non-lazy stage of view-aligned snapping. Adoption on catalog-sized lazy shelves remains conditional on the specified device measurement.
- Favorites' type control is capped at 420 points on wider screens.
- Large fixture signature now includes artwork/profile version; scale 200 seeds 240,000 catalog items and up to 5,000 guide channels. Catalog data is reused, guide data rolls daily, and source freshness is restamped. The Release 240k-catalog test now passes category jump, detail push/pop and grid-position retention. Long-shelf horizontal retention is tracked separately below.

Scope correction: a download relaunch/completion-order prototype was implemented and tested early in this pass, then removed after rechecking the explicit L10 exclusion. `DownloadBackgroundEvents`, persisted task identities, orphan reconciliation and eager app initialization are NOT part of the final change. Earlier mutation-gate/localization fixes remain. Do not cite the prototype's tests as proof that L10 findings are resolved.

Validation so far:

- All-unit run: 1,391 test cases passed, 1 expected failure, 1 skip, zero unexpected failures (1,506 passing executions including dynamic parameters). This run preceded removal of the L10 prototype and the metadata/panel additions; final affected tests must be cited separately.
- Metadata/fixture/mutation regression run: 34 cases passed, 40 executions with dynamic parameters, zero failures/skips. Includes preserving refreshed movie fields/other playlists, missing rows, optimistic series header semantics, real Nuke JPEG decode, deterministic panel decoder/error, existing series persistence and download mutation regressions.
- Release cached-detail + RTL run: 2 passed. Result copied outside DerivedData because Xcode prunes earlier result bundles.
- Durable local results: `/private/tmp/browse-final-evidence/all-unit.xcresult`, `metadata-fixtures.xcresult`, `release-detail-rtl.xcresult`. Subsequent final UI results will use the same directory.

Physical-device limitation: the owner's paired iPhone 15 Plus has Developer Mode enabled but `devicectl` reports `passcodeRequired: true`. No physical-device app installation, VoiceOver tour or Instruments run was performed. Other people's paired devices are not used. The ten-point device tour in fix-report section 7 remains distinct from simulator coverage.

Further verification and corrections:

- Added stable category-header, search-results, guide-grid and episode-row identifiers without changing Equatable row inputs; existing card/favorite/season identifiers remain compatible.
- `ChannelEPGDetailView` now uses `LoadedRequest`: pending database delivery renders the background, and only a delivered empty schedule renders “no data”. Other async favorites/download/history lists already used this wrapper. Clearing root/global browse search now applies immediately; nonempty typing retains the existing debounce.
- Release UI matrix initially passed 17/19. The large-catalog test expected the wrong generated noun (“Lantern” instead of “Canyon” at category 215); corrected. The following guide test remained on Playlists instead of the seeded M3U dashboard after the disk-full episode; this is pending a clean rerun, not a claimed app fix.
- Temporary iOS 18 XCTest probe runs failed: pull-to-refresh got stuck waiting for quiescence with the expected error alert open, and the docked-player test could not verify the Series tab after tapping it. Neither is counted as passing compatibility coverage. The latter remains a player-owner follow-up under L5/L9; no player code was changed.
- Replaced the unreliable XCTest probe choreography with a **scratch-only controlled app driver** on iPhone 16 Pro / iOS 18.1. It used the real dashboard, catalog store and overlay controller, plus a transparent environment reader in place of the actual player engine. `AUDIT Complete` is present in `/private/tmp/browse-final-evidence/invalidation-driver.log`.
  1. With VOD and Series detail mounted, overlay present/minimize/expand/dismiss produced no `_playerOverlay changed` body event. Initial identity events are excluded.
  2. The environment reader updated for minimize/expand (`_mode changed`) and did not update for docked Settings → Search switches. This confirms the host-isolation mechanism, not video-engine performance.
  3. Refreshing Movies produced `_contentStore changed` in visited Live as well as Movies: shared-store publication still reaches visited inactive tabs. No claim of complete cross-tab observation isolation.
  4. Refreshing Live produced `_contentStore changed` without the old per-refresh `@self` churn. Initial mounting and subsequent navigation still legitimately produced `@self` events.
- Probe instrumentation/driver exist only under `/private/tmp/browse-invalidation-probe`; they were never added to repository/player sources. The temporary iOS 18 simulator and redundant build products were removed after evidence capture to recover disk space. The device-tour report must retain the separate docked-player UI failure above.

- iPad Pro 11-inch M4 / iOS 26 Release: Arabic guide/schedule and wide Favorites/detail navigation passed (2 tests). Portrait screenshots were inspected. The first landscape attachments used the application's crop while the simulator display was rotating and showed a black/cropped canvas. The strengthened test waits for window orientation and captures the full screen. Its rerun passed in `ipad-orientation.xcresult`; landscape Favorites and movie detail were visually inspected, with readable controls and no clipped content. Images are in `/private/tmp/browse-final-evidence/ipad-orientation-images`. The temporary iPad simulator was deleted after capture to recover disk space; evidence is retained.


Additional shared-kit review:

- Xtream favorites now restart a failed database observation when the same playlist is tracked again. Previously the playlist identity guard made a transient observation failure permanent until a playlist switch. A regression renames the favorites table, observes the failure, restores the table and verifies both the recovered IDs and a later external insertion. Existing serialized optimistic writes are retained.
- The full-screen artwork viewer now puts Close in a system toolbar, with the iOS 26 close role and an iOS 18 symbol fallback. Its cached placeholder, bounds-change refitting and cancellation stay intact. Pan/zoom presentation changes remain conditional on the corrected finding's physical-device gesture check; no unverified gesture replacement was made.

Final broad regression (before the two additions above): `final-regressions.xcresult` ran 1,405 cases: 1,400 passed, 3 failed, 1 expected failure, 1 skipped. Two UI failures were test locator errors (the category picker exposes Button, not StaticText); the third was `AudioOutputRecoveryTests/stoppedEngineRestartsAfterConfigurationChange`, outside browse ownership. A focused rerun (`scale-retention-retry.xcresult`) passed all four audio recovery tests and the large-catalog navigation test. Its remaining shelf test hit XCTest's invalid activation point on an offscreen lazy cell; the locator now excludes offscreen frames before querying hittability. The failed broad run is not relabelled green. The previously failing guide accessibility startup passed in the broad rerun.

The first viewer/shelf validation attempt produced no completed test result and was interrupted after collecting an Xcode process sample; no live test runner was visible at that point. This does not establish an application defect. The simulator was restarted; this attempt is not test evidence. Final viewer/favorites/shelf results follow below.

### Device-tour coverage (simulator evidence does not close physical checks)

| Original tour item | Evidence obtained | Still requires a physical-device run / protected-owner follow-up |
|---|---|---|
| 1. Large catalog, tab/grid/detail navigation | 240k catalog category jump and grid push/pop position; cached detail timing; iPad detail orientation captures | Physical frame/hitch trace and complete long-session memory profile |
| 2. Press/scroll/context-menu feel | Context-menu navigation regression and ButtonStyle/Reduce Motion source review | Fast-fling press cancellation, haptics and overlapping touch areas |
| 3. Refresh and errors | Store/import/download/guide regression tests; scratch runtime refresh observations | Gesture feel and offline/reconnect device tour |
| 4. Series and mini-player episode handoff | Season observer/data tests and failed-season header UI flow | Actual docked-player sequence; iOS 18 probe could not verify tab navigation |
| 5. Guide enable/disable and absent data | Line-reservation/guide/store tests and guide/schedule UI coverage | Full toggle/return flow on representative provider data |
| 6. Search and keyboard | GlobalSearch tests, largest-text search UI and immediate clearing | Turkish physical keyboard/input-method tour and scroll dismissal feel |
| 7. Settings and language | Adult-confirmation UI, both largest-text settings flows, locale/cache review | Real connectivity restoration and complete language-change/player teardown tour |
| 8. iPad | Arabic guide/schedule and portrait/landscape Favorites/movie detail, visually inspected | Window resizing, pointer, and real-device single-window tour |
| 9. Accessibility | Default/largest-text card/detail/guide/search/picker/settings tests | VoiceOver focus/actions, Smart Invert and physical accessibility matrix |
| 10. Arabic | In-app Arabic guide/schedule on English iPhone/iPad simulators | Complete app-wide RTL tour beyond the captured surfaces |

The 358-row table accounts for all findings, including the 87 polish findings. It is a finding-oriented source audit with focused regression tests, not a claim that every original line received an independent second reviewer. Earlier section 8–15 “next” lists describe their historical point in time; section 16 and the verification table are the current status.


`Shelf-viewer-favorites.xcresult`: all **15 XtreamFavoriteStore tests** and both **BrowseAccessibility UI tests** passed, including the new failed-observation recovery and opening/closing the poster with the system toolbar. The shelf-offset test exceeded its 4-minute allowance; the runner sample places it in `XCUIApplicationProcess.waitForQuiescence` before the first horizontal swipe. It is not a measured offset failure. After capturing the sample, the app/simulator was stopped so the run could finish. The retry requires the selected picker row itself to leave the hierarchy before swiping, and uses a newly created isolated iPhone simulator.

Seven iPhone performance blocks are now in `BrowsePerformanceUITests` in `another-iptv-playerUITests/UserFlowsUITests.swift`: process launch to first shelf, home flings, All Movies grid flings, warm content-tab switches, three-letter search, detail push/pop, and opening the large guide. They use real content IDs and the scale-200 fixture. Search deliberately has no CPU metric because XCUI typing adds automation traffic. The other interaction blocks record clock/CPU/memory and, on iOS 26, hitch metrics. Launches retain disk/database caches; none is claimed to measure a cache-cold installation. Final run pending below.


Further completed evidence:

- `isolated-performance.xcresult` passed **18/18** (15 favorite-store tests, 2 accessibility UI tests, 1 movie shelf-retention test). Its name is historical: the new standalone performance file was not included by the explicit UI-test project group. The seven performance methods were moved into the existing `UserFlowsUITests.swift`, preserving the protected project file. No performance result is claimed from this 18-test run.
- `ios18-shelf-retention.xcresult` passed **2/2**, Movies and Live TV, on iPhone 16 Pro / iOS 18.1. Horizontal first-visible-card identity survives jumping 40 categories away and back. Movies also passed on iOS 26; the newly added Live TV case is in the final iOS 26 retry.
- `seven-performance.xcresult` executed all seven methods: five passed, two failed. Home-scroll reset overshot the top and triggered refresh, then XCTest timed out waiting for idleness. The reset now relaunches outside the measured window. Search's list is intentionally kept mounted; its identifier now distinguishes idle/pending/current-results states, so the measurement waits for the actual completed scan and can verify clearing.
- The five completed three-sample means: responsive first frame **1.275 s**; launch-to-first-shelf including automation **6.606 s**; five grid flings **16.475 s**; three warm tab switches **5.368 s**; detail push/pop **4.619 s**; guide opening **2.474 s**. Interaction numbers include XCUI dispatch/idling. The exported simulator metrics contain clock/CPU/memory but no numeric hitch metric; absence is not zero hitches. Brief runner samples were taken to diagnose execution progress, so these are exploratory measurements, not a controlled performance baseline. Raw metrics: `/private/tmp/browse-final-evidence/seven-performance-metrics.json`; distilled values: `performance-summary.json`.

Physical-device update: the iPhone was unlocked on recheck. A scratch copy was successfully built and signed under **`dev.ogos.another-iptv-player.browse-audit`**, display name **Browse Audit**, with its own test-runner identity; the repository project/scheme and normal app identifier were not changed. Installation failed before any physical test ran: the device reported **22,164,922 bytes required, 7,309,456 purgeable bytes available, zero free space** while installing the runner. `physical-browse.xcresult` records this installation failure. The isolated app is not installed. No existing apps/user data were deleted, and no physical Instruments trace was collected. Device storage, plus the manual VoiceOver/haptic tour, now replaces the earlier lock-only limitation. Scratch driver/build instructions are retained under `/private/tmp/browse-device-audit`.


### Closeout — 2026-10-03

The user requested that this session be finished. No further product changes were introduced during closeout. The verification table was reconciled with the recorded shelf-retention and performance runs; all 358 findings have an explicit status.

The final three-test retry (home flings, search, Live shelf retention on iOS 26) cannot be verified: its process session is no longer available, and `/private/tmp/browse-performance-retry.log` and `/private/tmp/browse-final-evidence/performance-retry.xcresult` are absent. The entire temporary evidence directory and scratch scripts are absent at closeout. Earlier result paths above are historical references, not currently available deliverables; their recorded summaries are retained, not newly revalidated. No passing result is inferred for the last retry. Test sources remain in the repository for reproduction.

Remaining work is explicitly represented by the 49 partial and 1 unresolved rows: physical Instruments/hitch and VoiceOver/haptic/device-tour checks; search-cancel shelf restoration; broader memory/geometry and accessibility coverage; and other conditional implementation/validation items listed row by row. The 53 decision rows preserve the accepted exclusions rather than silently reopening protected player, download-lifecycle or product-design work. Physical test installation most recently failed due to full device storage, not a still-locked device.

Closeout checks: `git diff --check` passed; verification IDs, status totals and repository file links were checked. No commit or push was made. Existing unrelated player, tip, project, scheme and Fastfile changes were left in place.
