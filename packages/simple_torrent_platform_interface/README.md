# simple_torrent_platform_interface

Platform interface for the simple_torrent plugin.

This package defines the common interface that all platform implementations of the simple_torrent plugin must implement. It provides the abstract base classes, data models, and contracts that ensure consistent behavior across all supported platforms.

## Usage

This package is primarily intended for use by platform implementation packages and plugin authors. Regular users should depend on the main `simple_torrent` package instead.

### For Platform Implementers

To implement simple_torrent for a new platform:

1. Depend on this package in your pubspec.yaml
2. Extend `SimpleTorrentPlatform` and implement all abstract methods
3. Register your implementation with `SimpleTorrentPlatform.instance`

```dart
import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

class MyPlatformImplementation extends SimpleTorrentPlatform {
  @override
  Future<void> init({TorrentConfig? config}) {
    // Platform-specific implementation
  }
  
  // Implement all other abstract methods...
}

// Register the implementation
SimpleTorrentPlatform.instance = MyPlatformImplementation();
```

## Classes and APIs

### Core Classes

- **`SimpleTorrentPlatform`** - Abstract base class defining the platform interface
- **`TorrentStats`** - Real-time torrent statistics and progress data
- **`TorrentMetadata`** - Torrent file information and metadata
- **`TorrentInfo`** - Complete torrent session information
- **`TorrentConfig`** - Configuration options for the torrent engine

### Enums

- **`TorrentState`** - Enumeration of possible torrent states (downloading, seeding, paused, etc.)

### Key Methods

- Torrent lifecycle management (start, pause, resume, cancel, finalize)
- Multiple torrent start methods (magnet links, files, raw data)
- Real-time progress and metadata streaming
- Configuration management
- Session querying and state management

## Platform Support

This interface supports the following platforms through their respective implementation packages:

- Android (`simple_torrent_android`)
- iOS (`simple_torrent_ios`) 
- macOS (`simple_torrent_macos`)
- Windows (`simple_torrent_windows`)

## License

MIT License - see LICENSE file for details.
