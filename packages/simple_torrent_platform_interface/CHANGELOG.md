# Changelog

All notable changes to the simple_torrent_platform_interface package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-09-14

### Added
- Initial release of the simple_torrent platform interface
- Core platform interface defining the contract for torrent operations
- `SimpleTorrentPlatform` abstract class with all torrent management methods
- Data classes: `TorrentStats`, `TorrentMetadata`, `TorrentInfo`, `TorrentConfig`
- `TorrentState` enum for torrent status tracking
- Stream-based APIs for real-time torrent progress and metadata updates
- Comprehensive torrent lifecycle management (start, pause, resume, cancel, finalize)
- Support for starting torrents from magnet links, .torrent files, and raw data
- Configuration management for bandwidth limits, DHT settings, and user agent
- Cross-platform compatibility foundation for Android, iOS, macOS, and Windows

### Features
- **Torrent Management**: Complete CRUD operations for torrent sessions
- **Real-time Updates**: Stream-based progress monitoring and metadata retrieval  
- **Multiple Start Methods**: Support for magnet links, file paths, and byte data
- **Configuration**: Runtime torrent engine configuration updates
- **Type Safety**: Strongly-typed data classes and enums
- **Error Handling**: Comprehensive error reporting and state management
