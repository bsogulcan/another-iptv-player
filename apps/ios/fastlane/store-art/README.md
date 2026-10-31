# App Store art

Builds the localized App Store screenshots (iPhone 6.9", iPad 13", iPhone Duo), the
product page header and the search image from real simulator captures of the demo
catalog (`-UITests 1`). Last used for 3.1.0.

| Set | Slots |
|---|---|
| iPhone 6.9" (1320×2868) | 1–7 portrait (1–2, 3–4, 5–6 are panoramic pairs), 8 landscape player |
| iPad 13" (2064×2752) | 1–7 portrait, 8 landscape player, 9 landscape Live TV |
| iPhone Duo (2007×2853) | 1–7 inner display, 8–10 inner display in landscape |
| Header (3840×1646), search (3840×2560) | uploaded by hand |

Landscape screens are drawn as horizontal devices on portrait canvases: the store
shows a landscape image inside a portrait set turned sideways. In Arabic the
panoramic pairs run right to left. Headlines for every language are in `copy.json`.

## 1. Capture

The capture tests are not part of the UI test target. Append one to
`another-iptv-playerUITests/ScreensUITests.swift`, run it, then `git checkout` that file.

```sh
cd apps/ios
cat fastlane/store-art/capture/StoreShotsUITests.swift >> another-iptv-playerUITests/ScreensUITests.swift
xcrun simctl status_bar <udid> override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode notSupported --batteryState charged --batteryLevel 100
fastlane/store-art/capture/watch.sh <udid> fastlane/store-art/captures/portrait/iphone [display-uuid] &
TEST_RUNNER_STORE_OUT=$PWD/fastlane/store-art/captures/portrait/iphone \
  xcodebuild test -workspace another-iptv-player.xcworkspace -scheme another-iptv-player \
  -destination id=<udid> -only-testing:another-iptv-playerUITests/StoreShotsUITests
kill %1; git checkout -- another-iptv-playerUITests/ScreensUITests.swift
```

The test writes a `req-<name>` file at each step and waits; `watch.sh` answers it with
`simctl io screenshot`. Screenshots are taken from the host because XCTest returns
black images on iPhone Duo. `TEST_RUNNER_STORE_LANGS=en,tr` limits the languages.

| Test | Device | Output folder |
|---|---|---|
| `StoreShotsUITests` | iPhone 18 Pro Max, iPad Pro 13" (M5), iPhone Duo | `captures/portrait/<device>` |
| `LandShotsUITests` | iPhone, iPad (rotates by itself) | `captures/landscape/<device>` |
| `DuoLandUITests` | iPhone Duo, opened and turned to landscape by hand in Device Hub | `captures/landscape/duo` |
| `SearchShotsUITests` | iPhone Duo, retakes the search screen with the keyboard closed | `captures/portrait/duo` |

iPhone Duo: pass the inner display's UUID to `watch.sh`
(`xcrun simctl io <udid> enumerate`, the 2007×2853 port). It changes on every boot.

## 2. Render and publish

```sh
cd apps/ios/fastlane/store-art
python3 -I panorama.py   # portrait slots 1-7
python3 -I extras.py     # landscape slots, header, search
python3 -I publish.py    # copies into ../screenshots and ../store-assets, rebuilds the gallery
```

Pass store locales (`en-US tr`) to render only those. en-GB is a copy of en-US.
Rendering uses headless Google Chrome.

## 3. Upload

```sh
cd apps/ios
APP_STORE_CONNECT_API_KEY_PATH=... APP_STORE_CONNECT_API_KEY_ID=... APP_STORE_CONNECT_API_ISSUER_ID=... \
DELIVER_APP_VERSION=<version> DELIVER_OVERWRITE_SCREENSHOTS=true \
bundle exec fastlane ios screenshots_upload
```

This deletes every screenshot set in every locale before uploading (slow: the whole
run took about 1.5 hours with Apple's processing). Screenshots are locked while the
version is in review. The header and search images go in by hand from
`fastlane/store-assets/<locale>/product-page/`.
