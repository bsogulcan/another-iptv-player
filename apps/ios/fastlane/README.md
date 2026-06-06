fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture App Store screenshots for iPhone 6.9" and iPad 13" via XCUITest

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload App Store metadata (text + URLs only, no binary, no screenshots)

### ios screenshots_upload

```sh
[bundle exec] fastlane ios screenshots_upload
```

Upload App Store screenshots only (no binary, no metadata)

### ios precheck_metadata

```sh
[bundle exec] fastlane ios precheck_metadata
```

Validate metadata against Apple's App Store Review Guidelines (precheck)

### ios verify_metadata

```sh
[bundle exec] fastlane ios verify_metadata
```

Local sanity check for metadata character limits (no network calls)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
