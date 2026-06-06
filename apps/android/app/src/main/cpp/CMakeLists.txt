# JNI bridge to media-kit's prebuilt libmpv.so.
#
# `libmpv.so` is staged into `app/src/main/jniLibs/<abi>/` by
# `android/Vendor/libmpv-android/Makefile`. We declare it as an IMPORTED
# shared library so CMake's link step can resolve `-lmpv` at our JNI .so's
# link time; without this the IMPORTED_LOCATION would be empty and the
# linker would fail with "cannot find -lmpv".

cmake_minimum_required(VERSION 3.22.1)
project(anotheriptv_mpv_jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(libmpv SHARED IMPORTED)
set_target_properties(libmpv PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libmpv.so
)

add_library(anotheriptv_mpv_jni SHARED
    mpv_jni.cpp
)

# 16 KB page alignment is required for Android 15+ devices (Play Store
# enforces this as of November 2025). NDK 27 defaults to it, NDK 26 doesn't,
# and AGP picks whichever NDK happens to be installed — so we pin the linker
# flag explicitly. media-kit's prebuilt libmpv.so already ships aligned.
target_link_options(anotheriptv_mpv_jni PRIVATE
    "-Wl,-z,max-page-size=16384"
)

# Same `mpv-headers` set the iOS bridging header uses; copied verbatim from
# ios/Vendor/mpv-headers/ into android/Vendor/libmpv-android/include/mpv/.
target_include_directories(anotheriptv_mpv_jni PRIVATE
    ${CMAKE_SOURCE_DIR}/../../../../Vendor/libmpv-android/include
)

target_link_libraries(anotheriptv_mpv_jni
    libmpv
    android
    log
)
