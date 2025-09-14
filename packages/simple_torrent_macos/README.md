# simple_torrent_macos

macOS implementation of the `simple_torrent` plugin.

## Overview

This package provides the macOS implementation for the `simple_torrent` federated plugin, enabling torrent handling functionality on macOS. It includes native macOS integration with libtorrent-rasterbar libraries compiled for both Intel and Apple Silicon Macs.

## Features

- Native macOS torrent library integration
- Universal binary support (Intel and Apple Silicon)
- Efficient native memory management
- macOS-specific optimizations
- CocoaPods integration

## Platform Support

- macOS 10.14+
- Intel-based Macs
- Apple Silicon Macs (M1, M2, M3, etc.)

## Dependencies

This package depends on:
- `simple_torrent_platform_interface` - Provides the common interface
- Flutter SDK

## Usage

This package is automatically included when you add `simple_torrent` to your Flutter project and run on macOS. You should not need to manually add this package to your dependencies.

## Native Libraries

Includes pre-compiled libtorrent-rasterbar and Boost libraries optimized for macOS:
- libtorrent 2.x
- Boost 1.84.0
- Built with Xcode and macOS SDK
- Universal binaries supporting both architectures

## Architecture Support

- x86_64 (Intel Macs)
- arm64 (Apple Silicon Macs)

For more information about the parent plugin, see the [simple_torrent](https://pub.dev/packages/simple_torrent) package.
