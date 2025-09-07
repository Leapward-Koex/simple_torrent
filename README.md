# Simple Torrent

A high-performance Flutter plugin for torrent downloading and management, built on top of libtorrent-rasterbar.

## Features

- ✅ **High Performance**: Built with libtorrent-rasterbar for optimal performance
- ✅ **Cross-Platform**: Supports Android, iOS, macOS, and Windows
- ✅ **Real-time Updates**: Stream-based progress monitoring and metadata updates
- ✅ **Thread-Safe**: Non-blocking operations prevent ANR issues
- ✅ **Comprehensive API**: Full torrent lifecycle management
- ✅ **Configurable**: Runtime configuration updates for bandwidth limits, DHT, etc.

## Getting Started

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

## Platform Setup

### macOS Setup

For macOS applications using this plugin, **only user-selected directories are supported** due to sandboxing requirements. You must implement a directory picker to allow users to choose where torrents will be downloaded.

#### Required Entitlements

Add the following entitlements to your macOS app's entitlements files:

**macos/Runner/DebugProfile.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.cs.allow-jit</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
</dict>
</plist>
```

**macos/Runner/Release.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
</dict>
</plist>
```

#### Key Entitlements Explained

- **com.apple.security.network.client**: Allows outbound network connections for torrent downloading
- **com.apple.security.files.user-selected.read-write**: Allows access to directories chosen by the user via file picker

#### Required Implementation Pattern

**You must use a file picker for directory selection**. Hardcoded paths will not work due to macOS sandboxing. Here's the required approach:

**Implement Directory Picker**: Use `file_picker` package to let users select download directories:
   ```dart
   import 'package:file_picker/file_picker.dart';
   
   Future<String?> selectDownloadDirectory() async {
     return await FilePicker.platform.getDirectoryPath();
   }
   ```

#### Troubleshooting

- **Downloads fail with permission errors**: Ensure you're using user-selected directories only, not hardcoded paths
- **"Operation not permitted" errors**: The directory was not selected by the user - implement proper directory picker
- **Peer connections fail**: Verify both network entitlements are included
- **Build errors**: Check that entitlements files are properly formatted XML and included in your Xcode project

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
            subtitle: Text('${(stats.progress * 100).toStringAsFixed(1)}% - ${stats.state.name}'),
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
- **Platform-specific toolchains** (see individual platform sections below)

### Quick Start

Each platform has automated build scripts available in the `build_scripts/` directory:

- **Android**: `build_android_universal.sh` or `build_android_universal.ps1`
- **iOS**: `build_ios_universal.sh`
- **macOS**: `build_macos_complete.sh`
- **Windows**: `build_windows_x64.ps1`

### Platform-Specific Instructions

## Android

### Prerequisites
- **Android NDK** (Currently 29.0.13113456) - Set `ANDROID_NDK` environment variable
- **CMake 3.18+**
- **Ninja build system**

### Quick Build (All Architectures)

**For macOS/Linux:**
```bash
cd build_scripts
./build_android_universal.sh
```

**For Windows:**
```powershell
cd build_scripts
.\build_android_universal.ps1
```

This builds for all Android architectures (arm64-v8a, armeabi-v7a, x86_64) and copies libraries to the correct locations.

### Individual Architecture Builds

**For macOS/Linux:**
```bash
./build_android_arm64-v8a.sh      # Most common (64-bit ARM)
./build_android_armabi-v7a.sh     # Legacy (32-bit ARM)  
./build_android_x86_64.sh         # Emulator (64-bit x86)
```

**For Windows:**
```powershell
.\build_android_arm64-v8a.ps1      # Most common (64-bit ARM)
.\build_android_armabi-v7a.ps1     # Legacy (32-bit ARM)  
.\build_android_x86_64.ps1         # Emulator (64-bit x86)
```

### Manual Configuration (Advanced)

If you need to modify the build process, you can configure `user-config.jam` for your target architecture:

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

## iOS

### Prerequisites
- **Xcode** with Command Line Tools
- **CMake** (via Homebrew: `brew install cmake`)
- **macOS** (iOS development requires macOS)

### Quick Build (Universal Libraries)

```bash
cd build_scripts
./build_ios_universal.sh
```

This will:
1. Build for iOS device (arm64)
2. Build for iOS simulator (arm64 + x86_64)
3. Create universal binaries using `lipo`
4. Copy headers and libraries to the correct locations

### Individual Architecture Builds

```bash
./build_iphoneos_arm64.sh           # iOS device (arm64)
./build_iphonesimulator_arm64.sh    # iOS simulator (arm64)
./build_iphonesimulator_x86_64.sh   # iOS simulator (x86_64, legacy)
```

### Cleaning Build Artifacts

```bash
./clean_ios.sh
```

### Testing Build Scripts

```bash
./test_ios_builds.sh
```

## macOS

### Prerequisites
- **Xcode** with Command Line Tools
- **CMake** (via Homebrew: `brew install cmake`)
- **Boost 1.88.0** source code (will be downloaded automatically)

### Quick Build (Complete)

```bash
cd build_scripts
./build_macos_complete.sh
```

This will:
1. Build Boost and libtorrent for arm64 (Apple Silicon)
2. Build Boost and libtorrent for x86_64 (Intel)
3. Create universal (fat) binaries
4. Organize libraries in the correct structure

### Individual Build Steps

```bash
./build_macos_arm64.sh        # Apple Silicon only
./build_macos_x86_64.sh       # Intel only
./build_macos_universal.sh    # Create universal binaries
./organize_macos_libs.sh      # Organize final structure
```

## Windows

### Prerequisites
- **Visual Studio 2022** with C++ build tools
- **CMake 3.14+** (included with Visual Studio)
- **Boost 1.88.0** extracted to `c:\Dev\boost_1_88_0`
- **libtorrent** source code at `c:\Dev\libtorrent`

### Quick Build

```powershell
cd build_scripts
.\build_windows_x64.ps1 -Configuration Release
```

This will build libtorrent for Windows x64 and copy libraries to the correct location.

### Manual CMake Build (Advanced)

```powershell
# Create build directory
mkdir c:\Dev\libtorrent\build_windows_x64
cd c:\Dev\libtorrent\build_windows_x64

# Configure with CMake
cmake -G "Visual Studio 17 2022" -A x64 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CXX_STANDARD=17 ^
  -DBUILD_SHARED_LIBS=OFF ^
  -Ddeprecated-functions=OFF ^
  -Dencryption=ON ^
  -Ddht=ON ^
  -Dextensions=ON ^
  -Dlogging=ON ^
  -Dpython-bindings=OFF ^
  -Dtests=OFF ^
  -Dexamples=OFF ^
  -Dtools=OFF ^
  -DBoost_ROOT=c:\Dev\boost_1_88_0 ^
  -DBoost_USE_STATIC_LIBS=ON ^
  -DCMAKE_INSTALL_PREFIX=c:\Dev\simple_torrent\shared\lib\windows ^
  ..

# Build and install
cmake --build . --config Release --parallel
```

### Directory Structure

After building, the native libraries should be organized as follows:

```
shared/
├── lib/
│   ├── android/
│   │   ├── arm64-v8a/
│   │   ├── armeabi-v7a/
│   │   └── x86_64/
│   ├── ios/
│   │   ├── device/
│   │   ├── simulator/
│   │   └── universal/
│   ├── macos/
│   │   ├── arm64/
│   │   ├── x86_64/
│   │   └── universal/
│   └── windows/
│       └── lib/
├── third_party/
│   ├── boost/
│   └── libtorrent/
└── torrent_core/
```

### Troubleshooting

For detailed platform-specific troubleshooting, see:
- `build_scripts/README_Android.md`
- `build_scripts/README_iOS.md`
- `build_scripts/README_macOS.md`
- `build_scripts/README_Windows.md`

## Contributions Welcome

**Note**: Due to limited time and device availability, I cannot guarantee perfect support for all platforms and architectures.

**Contributions are welcomed** for:
- Bug fixes on untested platforms/architectures
- Build script improvements
- Documentation enhancements
- Performance optimizations
- Additional platform support (Linux, etc.)

If you encounter issues on specific platforms or have improvements, please:
1. Open an issue with detailed reproduction steps
2. Submit a pull request with fixes
3. Share build logs for debugging


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
