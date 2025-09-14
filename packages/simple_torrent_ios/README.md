# simple_torrent_ios

iOS implementation of the `simple_torrent` plugin.

## Overview

This package provides the iOS implementation for the `simple_torrent` federated plugin, enabling torrent handling functionality on iOS devices. It includes native iOS integration with libtorrent-rasterbar libraries compiled for iOS device and simulator architectures.

## Features

- Native iOS torrent library integration
- Support for iOS devices and simulators
- Efficient native memory management
- iOS-specific optimizations
- CocoaPods integration

## Platform Support

- iOS 12.0+
- iPhone and iPad devices
- iOS Simulator (Intel and Apple Silicon Macs)

## Dependencies

This package depends on:
- `simple_torrent_platform_interface` - Provides the common interface
- Flutter SDK

## Usage

This package is automatically included when you add `simple_torrent` to your Flutter project and run on iOS. You should not need to manually add this package to your dependencies.

## Native Libraries

Includes pre-compiled libtorrent-rasterbar and Boost libraries optimized for iOS:
- libtorrent 2.x
- Boost 1.84.0
- Built with Xcode and iOS SDK
- Universal binaries for device and simulator

## Architecture Support

- arm64 (iOS devices)
- arm64 (iOS Simulator on Apple Silicon)
- x86_64 (iOS Simulator on Intel)

For more information about the parent plugin, see the [simple_torrent](https://pub.dev/packages/simple_torrent) package.
