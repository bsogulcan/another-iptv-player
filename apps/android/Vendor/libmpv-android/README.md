# libmpv for Android (media-kit prebuilt)

Mirror of `ios/Vendor/libmpv/` — instead of xcframeworks we vendor
[`libmpv-android-video-build`](https://github.com/media-kit/libmpv-android-video-build)
release JARs, which each ship one `libmpv.so` + `libmediakitandroidhelper.so`
under `lib/<abi>/`. The Android Gradle Plugin extracts that tree from any JAR
placed under `app/libs/`, so we don't need a custom `jniLibs.srcDirs` rule.

## Bootstrap

```
cd android/Vendor/libmpv-android
make
```

That downloads each ABI's JAR (pinned by SHA256), verifies it, and stages it
into `android/app/libs/libmpv-<abi>.jar`. The CI workflow should run the same
command before `./gradlew assemble*`.

`make clean` removes both the cache and the staged JARs.

## Header files

`include/mpv/` holds the libmpv C client headers (`client.h`, `render.h`,
`render_gl.h`) used by `android/app/src/main/cpp/` when JNI-linking against
`libmpv.so`. These are pinned to the same version that produced the SOs above;
upgrading the SO version means refreshing the headers too.
