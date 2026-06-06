# Pulls media-kit's prebuilt libmpv + helper for Android.
#
# Mirrors `ios/Vendor/libmpv/Makefile`: instead of xcframeworks we fetch
# per-ABI JARs that ship `lib/<abi>/libmpv.so` + `lib/<abi>/libmediakitandroidhelper.so`.
# We extract them straight into `app/src/main/jniLibs/<abi>/` so:
#   1) AGP picks them up and ships them in the APK with no extra config, and
#   2) the CMake JNI bridge can resolve `libmpv.so` via a normal IMPORTED target
#      that points at the same path NDK_LIBS would look at.
#
# Usage:
#   make            # download + verify + extract into jniLibs/
#   make clean      # remove caches + extracted libs
#
# Versions are pinned with SHA256 below so an upstream rebuild can never
# silently break the JNI ABI we link against.

MPV_ANDROID_VERSION = v1.1.11

# `default-<abi>.jar`: libmpv built with the default (video) feature set —
# matches the iOS `*-video-default.tar.gz` selection in ios/Vendor/libmpv/Makefile.
ABIS = arm64-v8a armeabi-v7a x86_64

SHA256_arm64-v8a    = 2a906875af68be8c98c4a83c236bc24053f46e0accf62b115993ef1d740e98cc
SHA256_armeabi-v7a  = a9926cb4f8f42032769d411390b812f08a10a8048c67518e1e325803468da047
SHA256_x86_64       = afe9aed06498a04b9b9655b0ad812dd29f864dcb6f735ab7df3900082bcb713d

CACHE_DIR   = .cache/jars
JNI_LIBS    = ../../app/src/main/jniLibs
BASE_URL    = https://github.com/media-kit/libmpv-android-video-build/releases/download/$(MPV_ANDROID_VERSION)

CACHED_JARS    = $(foreach abi,$(ABIS),$(CACHE_DIR)/default-$(abi)-$(MPV_ANDROID_VERSION).jar)
EXTRACT_STAMPS = $(foreach abi,$(ABIS),$(JNI_LIBS)/$(abi)/.libmpv-$(MPV_ANDROID_VERSION).stamp)

.PHONY: all clean
all: $(EXTRACT_STAMPS)

# Without this make treats the cache JARs as intermediates and deletes them
# after extraction, so the next `make` re-downloads everything.
.SECONDARY: $(CACHED_JARS)

# Atomic download + SHA verify; the `.tmp` rename guarantees a partial
# download never poisons the cache (same dance as the iOS Makefile).
$(CACHE_DIR)/default-%-$(MPV_ANDROID_VERSION).jar:
	@mkdir -p $(CACHE_DIR)
	@rm -f $@.tmp
	curl -L $(BASE_URL)/default-$*.jar -o $@.tmp
	shasum -a 256 -c <<< '$(SHA256_$*)  $@.tmp'
	mv $@.tmp $@
	@touch $@

# Stamp file pinned to the version: bumping MPV_ANDROID_VERSION invalidates
# the old stamp and forces a fresh extraction without leaving stale .so files
# around (`make clean` is no longer required when bumping versions).
$(JNI_LIBS)/%/.libmpv-$(MPV_ANDROID_VERSION).stamp: $(CACHE_DIR)/default-%-$(MPV_ANDROID_VERSION).jar
	@mkdir -p $(JNI_LIBS)/$*
	@rm -f $(JNI_LIBS)/$*/.libmpv-*.stamp $(JNI_LIBS)/$*/libmpv.so $(JNI_LIBS)/$*/libmediakitandroidhelper.so
	cd $(JNI_LIBS)/$* && unzip -j -o $(abspath $<) 'lib/$*/*.so'
	@touch $@

clean:
	rm -rf $(CACHE_DIR)
	rm -rf $(JNI_LIBS)
