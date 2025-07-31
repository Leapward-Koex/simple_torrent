# Simple Torrent

A high-performance Flutter plugin for torrent downloading and management, built on top of libtorrent-rasterbar.

## Features

- ✅ **High Performance**: Built with libtorrent-rasterbar for optimal performance
- ✅ **Cross-Platform**: Supports Android and iOS
- ✅ **Real-time Updates**: Stream-based progress monitoring and metadata updates
- ✅ **Thread-Safe**: Non-blocking operations prevent ANR issues
- ✅ **Comprehensive API**: Full torrent lifecycle management
- ✅ **Configurable**: Runtime configuration updates for bandwidth limits, DHT, etc.
- ✅ **Modern Architecture**: Uses Kotlin coroutines and Dart streams

## Getting Started

### Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  simple_torrent:
    git:
      url: https://github.com/Leapward-Koex/simple_torrent.git
```

### Basic Usage

```dart
import 'package:simple_torrent/simple_torrent.dart';

void main() async {
  // Initialize the torrent manager
  await SimpleTorrent.init(config: const TorrentConfig(
    maxTorrents: 10,
    maxDownloadRate: 1024, // 1 MB/s
    maxUploadRate: 512,    // 512 KB/s
    enableDHT: true,
    userAgent: 'MyApp/1.0',
  ));

  // Start downloading a torrent
  final torrentId = await SimpleTorrent.start(
    magnet: 'magnet:?xt=urn:btih:...',
    path: '/storage/emulated/0/Download',
    displayName: 'My Torrent', // optional
  );

  print('Started torrent with ID: $torrentId');
}
```

## API Reference

### Configuration

```dart
// Initialize with custom configuration
await SimpleTorrent.init(config: TorrentConfig(
  maxTorrents: 20,          // Maximum concurrent torrents
  maxDownloadRate: 0,       // KB/s, 0 = unlimited
  maxUploadRate: 0,         // KB/s, 0 = unlimited  
  enableDHT: true,          // Enable DHT for peer discovery
  userAgent: 'MyApp/1.0',   // Custom user agent
));

// Update configuration at runtime
await SimpleTorrent.updateConfig(TorrentConfig(
  maxDownloadRate: 2048,    // Change to 2 MB/s
  maxUploadRate: 1024,      // Change to 1 MB/s
));
```

### Torrent Management

```dart
// Start a torrent
final id = await SimpleTorrent.start(
  magnet: 'magnet:?xt=urn:btih:...',
  path: '/path/to/download/folder',
  displayName: 'Optional display name',
);

// Control torrents
await SimpleTorrent.pause(id);
await SimpleTorrent.resume(id);
await SimpleTorrent.cancel(id);  // Cancels torrent and deletes files
await SimpleTorrent.finalise(id);  // Removes torrent but keeps files

// Get torrent information
final info = await SimpleTorrent.getTorrentInfo(id);
print('Name: ${info.displayName}');
print('State: ${info.state}');
print('Path: ${info.savePath}');

// Check torrent status
final exists = await SimpleTorrent.exists(id);
final state = await SimpleTorrent.getState(id);
final error = await SimpleTorrent.getLastError(id);

// Get all active torrents
final activeIds = await SimpleTorrent.getActiveTorrentIds();
```

### Real-time Monitoring

```dart
// Listen to progress updates for all torrents
SimpleTorrent.statsStream.listen((stats) {
  print('Torrent ${stats.id}: ${(stats.progress * 100).toStringAsFixed(1)}% complete');
  print('Download: ${stats.downloadRate} B/s');
  print('Upload: ${stats.uploadRate} B/s');
  print('Peers: ${stats.peers} (${stats.seeds} seeds)');
  print('State: ${stats.state}');
});

// Listen to metadata updates
SimpleTorrent.metadataStream.listen((metadata) {
  print('Metadata for ${metadata.id}:');
  print('Name: ${metadata.name}');
  print('Size: ${metadata.totalBytes} bytes');
  print('Files: ${metadata.fileCount}');
});

// Monitor a specific torrent
final specificStream = SimpleTorrent.statsFor(torrentId);
specificStream.listen((stats) {
  print('Progress: ${(stats.progress * 100).toStringAsFixed(1)}%');
});
```

### Helper Functions

```dart
// Start a torrent and get its stream
final (id, stream) = await SimpleTorrentHelpers.startAndWatch(
  magnet: 'magnet:?xt=urn:btih:...',
  path: '/download/path',
);

stream.listen((stats) {
  print('Progress: ${(stats.progress * 100).toStringAsFixed(1)}%');
});

// Bulk operations
await SimpleTorrentHelpers.pauseAll();
await SimpleTorrentHelpers.resumeAll();

// Get all torrent info objects
final allTorrents = await SimpleTorrentHelpers.getAllTorrents();
```

### Extension Methods

```dart
// TorrentInfo extensions
final torrent = await SimpleTorrent.getTorrentInfo(id);

await torrent.pause();           // Pause this torrent
await torrent.resume();          // Resume this torrent  
await torrent.cancel();          // Cancel this torrent (deletes files)
await torrent.finalise();          // Finish this torrent (keeps files)
final state = await torrent.getCurrentState(); // Get current state
final stream = torrent.statsStream;            // Get stats stream
```

## Data Types

### TorrentState

```dart
enum TorrentState {
  starting,            // Torrent is starting up
  downloadingMetadata, // Downloading torrent metadata
  downloading,         // Actively downloading
  seeding,            // Upload mode (finished downloading)
  paused,             // Paused by user
  error,              // Error occurred
  stopped,            // Stopped/cancelled
}
```

### TorrentStats

```dart
class TorrentStats {
  final int id;              // Torrent ID
  final int downloadRate;    // Download speed (bytes/s)
  final int uploadRate;      // Upload speed (bytes/s)
  final int pieces;          // Downloaded pieces
  final int piecesTotal;     // Total pieces
  final double progress;     // Progress (0.0-1.0)
  final int seeds;           // Number of seeds
  final int peers;           // Number of peers
  final String phase;        // Current phase
  final TorrentState? state; // Current state
}
```

### TorrentMetadata

```dart
class TorrentMetadata {
  final int id;            // Torrent ID
  final String name;       // Torrent name
  final int totalBytes;    // Total size in bytes
  final int pieceSize;     // Size per piece
  final int pieceCount;    // Total pieces
  final int fileCount;     // Number of files
  final int creationDate;  // Creation timestamp
  final bool isPrivate;    // Private torrent flag
  final bool isV2;         // BitTorrent v2 flag
}
```

### TorrentInfo

```dart
class TorrentInfo {
  final int id;                    // Torrent ID
  final String magnetUri;          // Original magnet link
  final String savePath;           // Download path
  final String displayName;        // Display name
  final TorrentState state;        // Current state
  final String lastError;          // Last error message
  final DateTime createdAt;        // Creation time
}
```

## Error Handling

```dart
try {
  final id = await SimpleTorrent.start(
    magnet: invalidMagnet,
    path: '/invalid/path',
  );
} catch (e) {
  print('Failed to start torrent: $e');
}

// Check for errors during operation
final error = await SimpleTorrent.getLastError(torrentId);
if (error.isNotEmpty) {
  print('Torrent error: $error');
}
```

## Complete Example

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:simple_torrent/simple_torrent.dart';

class TorrentDownloader extends StatefulWidget {
  @override
  _TorrentDownloaderState createState() => _TorrentDownloaderState();
}

class _TorrentDownloaderState extends State<TorrentDownloader> {
  Map<int, TorrentStats> _stats = {};
  StreamSubscription? _statsSubscription;

  @override
  void initState() {
    super.initState();
    _initTorrents();
  }

  Future<void> _initTorrents() async {
    // Initialize torrent manager
    await SimpleTorrent.init(config: TorrentConfig(
      maxTorrents: 5,
      maxDownloadRate: 1024, // 1 MB/s
      enableDHT: true,
    ));

    // Listen to all torrent updates
    _statsSubscription = SimpleTorrent.statsStream.listen((stats) {
      setState(() => _stats[stats.id] = stats);
    });
  }

  Future<void> _downloadTorrent(String magnet) async {
    try {
      final id = await SimpleTorrent.start(
        magnet: magnet,
        path: '/storage/emulated/0/Download',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Started download with ID: $id')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Torrent Downloader')),
      body: ListView.builder(
        itemCount: _stats.length,
        itemBuilder: (context, index) {
          final stats = _stats.values.elementAt(index);
          return ListTile(
            title: Text('Torrent ${stats.id}'),
            subtitle: Text('${(stats.progress * 100).toStringAsFixed(1)}% - ${stats.phase}'),
            trailing: Text('${_formatSpeed(stats.downloadRate)}'),
          );
        },
      ),
    );
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '${bytesPerSecond} B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }
}
```

---

## Development & Building

For developers who want to modify the native libtorrent integration or build from source:

### Prerequisites

- **libtorrent-rasterbar** (Currently 2.0.11)
- **Boost C++ Libraries** (Currently 1.88.0)  
- **Android NDK** (Currently 29.0.13113456)

### General Build Process

1. Setup prerequisites
2. Configure user-config.jam for your target architecture
3. Build Boost B2 for your toolset
4. Create Boost BCP tool for header extraction
5. Compile libtorrent and copy binaries
6. Generate required Boost headers using BCP

### Android Build Configuration

#### user-config.jam Setup

Create this file in your home directory for android-arm64-v8a:

```jam
using clang : android
    : "%ANDROID_NDK%/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android24-clang++.cmd"
    : <compileflags>"-fPIC"
      <linkflags>"-fPIC"
      <arch>arm           <address-model>64
      <abi>aapcs          <binary-format>elf
      <target-os>android
      <archiver>"%ANDROID_NDK%/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-ar.exe"
;
```

#### Build Boost

```bash
b2 -j%NUMBER_OF_PROCESSORS% ^
    toolset=clang-android ^
    target-os=android architecture=arm address-model=64 ^
    cxxstd=17 link=static runtime-link=static threading=multi ^
    --with-system --with-atomic ^
    --hash ^
    install --prefix="<output folder location>"
```

#### Build BCP Tool

```bash
b2 --with-bcp toolset=msvc address-model=64 architecture=x86 link=static runtime-link=static release
```

#### Build libtorrent

```bash
b2 -j%NUMBER_OF_PROCESSORS% ^
   toolset=clang-android ^
   target-os=android architecture=arm address-model=64 ^
   cxxstd=17 ^
   link=static             ^
   boost-link=static       ^
   runtime-link=static     ^
   crypto=built-in         ^
   variant=release         ^
   fpic=on                 ^
   --hash                  ^
   --prefix="<output folder location>" install
```

#### Extract Boost Headers

```bash
bcp --boost=<path to boost> --scan ^
    "<path to libtorrent>\include\libtorrent\session.hpp" ^
    "<path to libtorrent>\include\libtorrent\alert_types.hpp" ^
    "<path to libtorrent>\include\libtorrent\magnet_uri.hpp" ^
    "<output path, e.g. 'simple_torrent\android\src\main\cpp\third_party\boost'>"
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
