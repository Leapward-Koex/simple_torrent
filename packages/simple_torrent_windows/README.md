# simple_torrent_windows

Windows implementation of the `simple_torrent` plugin.

## Overview

This package provides the Windows implementation for the `simple_torrent` federated plugin, enabling torrent handling functionality on Windows. It includes native Windows integration with libtorrent-rasterbar libraries compiled for x64 architecture.

## Features

- Native Windows torrent library integration
- x64 architecture support
- Efficient native memory management
- Windows-specific optimizations
- CMake integration

## Platform Support

- Windows 10+ (x64)
- Visual Studio 2019/2022 build tools
- CMake 3.18+

## Dependencies

This package depends on:
- `simple_torrent_platform_interface` - Provides the common interface
- Flutter SDK

## Usage

This package is automatically included when you add `simple_torrent` to your Flutter project and run on Windows. You should not need to manually add this package to your dependencies.

## Native Libraries

Includes pre-compiled libtorrent-rasterbar and Boost libraries optimized for Windows:
- libtorrent 2.x
- Boost 1.84.0
- Built with MSVC (Visual Studio)
- x64 dynamic libraries (.dll)

## Build Requirements

- Visual Studio 2019 or later with C++ development tools
- CMake 3.18 or later
- Windows 10 SDK

## Architecture Support

- x64 (64-bit Windows)

For more information about the parent plugin, see the [simple_torrent](https://pub.dev/packages/simple_torrent) package.
- `build_windows_x64.ps1` - Build for Windows x64
