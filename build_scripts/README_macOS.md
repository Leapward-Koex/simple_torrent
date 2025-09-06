# macOS Build Instructions

This document explains how to build the simple_torrent plugin for macOS.

## Prerequisites

- Xcode with Command Line Tools installed
- CMake (via Homebrew: `brew install cmake`)
- Boost 1.88.0 source code at `/Users/scottmacky/Documents/boost_1_88_0`
- libtorrent source code (will be automatically cloned)

## Quick Start

To build all macOS libraries (arm64, x86_64, and universal):

```bash
cd build_scripts
./build_macos_complete.sh
```

This will:
1. Build Boost and libtorrent for arm64
2. Build Boost and libtorrent for x86_64  
3. Create universal (fat) binaries
4. Organize libraries in the correct structure for the Flutter plugin

## Individual Build Scripts

You can also run individual build steps:

### Build for Apple Silicon (arm64)
```bash
./build_macos_arm64.sh
```

### Build for Intel (x86_64)
```bash
./build_macos_x86_64.sh
```

### Create Universal Libraries
```bash
./build_macos_universal.sh
```

### Organize Libraries
```bash
./organize_macos_libs.sh
```

## Architecture

The macOS plugin implementation:

- **Swift Plugin**: `macos/Classes/SimpleTorrentPlugin.swift` - Main Flutter plugin interface
- **C++ Bridge**: Symlinked from iOS implementation for maximum code reuse
  - `macos/Classes/torrent_plugin_macos.hpp` → `ios/Classes/torrent_plugin_ios.hpp`
  - `macos/Classes/torrent_plugin_macos.mm` → `ios/Classes/torrent_plugin_ios.mm`
- **Pod Specification**: `macos/simple_torrent.podspec` - CocoaPods configuration
- **Native Libraries**: `shared/lib/macos/` - Compiled Boost and libtorrent libraries

## Library Structure

After building, libraries are organized as:

```
shared/lib/macos/
├── libtorrent-rasterbar.a
└── boost/
    ├── libboost_system.a
    ├── libboost_atomic.a
    ├── libboost_thread.a
    ├── libboost_chrono.a
    ├── libboost_regex.a
    ├── libboost_filesystem.a
    └── libboost_date_time.a
```

## Configuration

The macOS plugin is configured to:
- Target macOS 10.11+
- Use C++17 standard
- Link against static Boost and libtorrent libraries
- Support both arm64 and x86_64 architectures

## Troubleshooting

### Missing Boost Source
If you get errors about missing Boost source, update the `BoostSrc` path in the build scripts to point to your Boost installation.

### Library Not Found Errors
Run `./organize_macos_libs.sh` to ensure libraries are in the correct location for the Flutter plugin.

### Architecture Mismatches
Use the universal build (`./build_macos_universal.sh`) to support both Intel and Apple Silicon Macs.
