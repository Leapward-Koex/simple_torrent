# Changelog

All notable changes to the simple_torrent_windows package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-09-14

### Added
- Initial release of the Windows implementation for simple_torrent
- Native Windows implementation using libtorrent-rasterbar
- Support for x64 architecture
- C++ plugin implementation with method and event channels
- Pre-built libtorrent and Boost static libraries for Windows
- CMake-based build system for Visual Studio integration
- Windows-specific optimizations and configurations

### Features
- **x64 Architecture**: Native support for 64-bit Windows systems
- **Native Performance**: Direct libtorrent integration optimized for Windows
- **Method Channels**: Flutter-to-native communication for all torrent operations
- **Event Streams**: Real-time progress updates and metadata streaming
- **System Integration**: Windows-native file system and network handling
- **Visual Studio**: Full integration with Microsoft build tools

### Platform Requirements
- Windows 10 or later
- Visual Studio 2019 or later with C++ support
- CMake 3.15 or later

### Build Scripts
- Automated PowerShell build scripts for x64 architecture
- Visual Studio project generation and configuration
- Dependency management for Windows SDK and runtime libraries

### Fixed
- CMake target naming for federated plugin compatibility
- Include path resolution for plugin headers
- Library linking configuration for both Debug and Release builds
