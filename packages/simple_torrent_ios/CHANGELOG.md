# Changelog

All notable changes to the simple_torrent_ios package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-09-14

### Added
- Initial release of the iOS implementation for simple_torrent
- Native iOS implementation using libtorrent-rasterbar
- Support for both device and simulator architectures
- Swift/Objective-C plugin implementation with method and event channels
- Pre-built libtorrent and Boost static libraries for iOS
- CocoaPods integration for dependency management
- Xcode project configuration and build settings

### Features
- **Universal Libraries**: Device (ARM64) and simulator (x86_64, ARM64) support
- **Native Performance**: Direct libtorrent integration optimized for iOS
- **Method Channels**: Flutter-to-native communication for all torrent operations
- **Event Streams**: Real-time progress updates and metadata streaming
- **Background Support**: Efficient background processing capabilities
- **Memory Management**: ARC-compatible memory handling and cleanup

### Platform Requirements
- iOS 12.0 or later
- Xcode 12.0 or later
- CocoaPods 1.10.0 or later

### Build Scripts
- Automated build scripts for device and simulator architectures
- Universal binary creation for both platforms
- Cross-compilation support for iOS SDK variants
