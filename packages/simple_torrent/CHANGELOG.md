# Changelog

## 2.0.0 - 2026-08-30

- Moved the app-facing package under `packages/simple_torrent` and adopted a
  single Dart Pub workspace lockfile.
- Endorsed the Android, iOS, macOS, and Windows packages with
  `default_package`; consumers no longer use path dependencies.
- Preserved the static facade, lifecycle operations, helpers, extensions, and
  streams while removing unsupported configuration fields.
- Changed rate limits to bytes per second and added a real connections limit.
- Added typed `SimpleTorrentException` codes.
- Added v1/v2 info hashes and per-file metadata.
- Standardized `.torrent` data/file starts and normalized completion to the
  `seeding` state.
- Added runtime session-wide transfer suspension with an authoritative Boolean
  query, while preserving each torrent's individual pause state.
- Raised minimum versions to Dart 3.12 and Flutter 3.44 and removed Linux.

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
