# Changelog

All notable changes to the simple_torrent_macos package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-09-14

### Added
- Initial release of the macOS implementation for simple_torrent
- Native macOS implementation using libtorrent-rasterbar
- Support for both Intel (x86_64) and Apple Silicon (ARM64) architectures
- Swift/Objective-C plugin implementation with method and event channels
- Pre-built universal libtorrent and Boost static libraries for macOS
- CocoaPods integration for dependency management
- Xcode project configuration optimized for macOS

### Features
- **Universal Binaries**: Native support for both Intel and Apple Silicon Macs
- **Native Performance**: Direct libtorrent integration optimized for macOS
- **Method Channels**: Flutter-to-native communication for all torrent operations
- **Event Streams**: Real-time progress updates and metadata streaming
- **System Integration**: macOS-native file system and network handling
- **Memory Management**: ARC-compatible memory handling and cleanup

### Platform Requirements
- macOS 10.14 or later
- Xcode 12.0 or later
- CocoaPods 1.10.0 or later

### Build Scripts
- Automated build scripts for x86_64 and ARM64 architectures
- Universal binary creation combining both architectures
- Cross-compilation support for macOS SDK variants
