# simple_torrent_android

Android implementation of the simple_torrent plugin.

This package contains the Android-specific implementation and all required Android libtorrent binaries.

## Usage

This package is automatically included when you add `simple_torrent` to your Flutter project and your project targets Android.

## Platform Requirements

- Android API level 21 (Android 5.0) or later
- NDK r25c or later
- Gradle 8.0 or later

## Libraries Included

- libtorrent-rasterbar (shared libraries)
- Boost libraries (shared libraries)
- Platform-specific binaries for arm64-v8a, armeabi-v7a, and x86_64 architectures

## Build Scripts

This package includes build scripts for compiling the native libraries:
- `build_android_arm64-v8a.*` - Build for ARM64 devices
- `build_android_armabi-v7a.*` - Build for ARM32 devices  
- `build_android_x86_64.*` - Build for x86_64 devices (emulators)
- `build_android_universal.*` - Build for all architectures
