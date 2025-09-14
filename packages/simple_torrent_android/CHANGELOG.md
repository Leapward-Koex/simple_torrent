# Changelog

All notable changes to the simple_torrent_android package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-09-14

### Added
- Initial release of the Android implementation for simple_torrent
- Native Android implementation using libtorrent-rasterbar
- Support for ARM64 (arm64-v8a), ARMv7 (armeabi-v7a), and x86_64 architectures
- Kotlin-based plugin implementation with method and event channels
- Pre-built libtorrent and Boost static libraries for Android
- CMake-based native code build system
- NDK integration for cross-compilation support

### Features
- **Architecture Support**: ARM64, ARMv7, and x86_64 device compatibility
- **Native Performance**: Direct libtorrent integration for optimal speed
- **Method Channels**: Flutter-to-native communication for all torrent operations
- **Event Streams**: Real-time progress updates and metadata streaming
- **Background Processing**: Non-blocking torrent operations to prevent ANR
- **Memory Management**: Efficient native memory handling and cleanup

### Platform Requirements
- Android API level 21 (Android 5.0) or later
- NDK r25c or later for building from source
- Gradle 8.0 or later

### Build Scripts
- Automated build scripts for all supported architectures
- Universal build option for multi-architecture APKs
- Cross-compilation toolchains and configuration
