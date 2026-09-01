# Changelog

## [Unreleased]

- Added source-authenticated, cross-runner native bundle regeneration with a
  deterministic four-platform manifest assembler and generated dependency
  notice tables.
- Added a fixed bot pull request flow with Git LFS enforcement, allowlisted
  publication, squash auto-merge, and a stable aggregate smoke gate.
- Added Windows, Android, ARM64 macOS, and ARM64 iOS Simulator consumer smoke
  coverage, including deterministic loopback transfer suspension tests.

## [2.0.0] - 2026-08-30

- Converted the repository to a Dart Pub workspace with six independently
  publishable federated packages under `packages/` and one shared lockfile.
- Replaced duplicated platform-native trees with a manager-owned C ABI and
  pinned, checksummed libtorrent 2.0.12, Boost 1.91.0, and OpenSSL 3.5.8 builds.
- Added the table-driven `tool/native.ps1` and `tool/native.sh` maintainer flow,
  offline/cache controls, artifact verification, and manifest generation.
- Standardized the method-channel contract, configuration validation, typed
  errors, v1/v2 hashes, file metadata, and the terminal-driven sample test.
- Added explicit session-wide transfer suspension for parent-owned metered and
  connectivity policy, independently of per-torrent pause state.
- Removed the unsupported Linux implementation and legacy build layouts.

## [1.0.0] 

### Added
- Initial release of the simple_torrent plugin

### Features
- **Cross-Platform**: Supports Android, iOS, macOS, and Windows
- **High Performance**: Built on libtorrent-rasterbar for optimal speed
- **Real-time Updates**: Stream-based progress and metadata monitoring
- **Thread-Safe**: Non-blocking operations to prevent UI freezing
- **Configurable**: Runtime updates for bandwidth, DHT, user agent settings
- **Type-Safe**: Strongly-typed Dart API with comprehensive error handling

### Architecture
- **Federated Design**: Platform-specific packages for reduced bundle size
- **Clean API**: Simple, intuitive interface for all torrent operations
- **Modular**: Each platform implementation is independently maintained
- **Extensible**: Easy to add new platforms or extend functionality

### API
- `SimpleTorrent.init()` - Initialize torrent engine with configuration
- `SimpleTorrent.start()` - Start torrent from magnet link
- `SimpleTorrent.startFromTorrentFile()` - Start from .torrent file
- `SimpleTorrent.startFromData()` - Start from in-memory torrent data
- `SimpleTorrent.pause()` / `SimpleTorrent.resume()` - Control playback
- `SimpleTorrent.cancel()` / `SimpleTorrent.finalise()` - Lifecycle management
- `SimpleTorrent.statsStream` - Real-time progress updates
- `SimpleTorrent.metadataStream` - Torrent metadata updates

### Dependencies
- `simple_torrent_platform_interface` ^1.0.0
- `simple_torrent_android` ^1.0.0 (Android apps)
- `simple_torrent_ios` ^1.0.0 (iOS apps)
- `simple_torrent_macos` ^1.0.0 (macOS apps)
- `simple_torrent_windows` ^1.0.0 (Windows apps)
