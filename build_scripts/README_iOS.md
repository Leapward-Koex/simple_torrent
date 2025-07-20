# iOS Build Scripts for simple_torrent

This directory contains scripts to build libtorrent and Boost libraries for iOS.

## Quick Start

To build universal iOS libraries (recommended):

```bash
./build_ios_universal.sh
```

This will:
1. Build for iOS device (arm64)
2. Build for iOS simulator (arm64 + x86_64)
3. Create universal binaries using `lipo`
4. Copy headers and libraries to the correct locations for the Flutter plugin

## Individual Architecture Builds

If you need to build for specific architectures:

```bash
./build_iphoneos_arm64.sh           # iOS device (arm64)
./build_iphonesimulator_arm64.sh    # iOS simulator (arm64)
./build_iphonesimulator_x86_64.sh   # iOS simulator (x86_64)
```

## Cleaning

To clean build artifacts:

```bash
./clean_ios.sh
```

## Testing

To test script validity without building:

```bash
./test_ios_builds.sh
```

## Output Structure

The build scripts create the following structure:

```
shared/
├── lib/ios/
│   ├── libtorrent-rasterbar.a      # Universal binary
│   ├── libboost_system.a           # Universal binary
│   ├── libboost_atomic.a           # Universal binary
│   ├── libboost_thread.a           # Universal binary
│   ├── libboost_chrono.a           # Universal binary
│   ├── libboost_regex.a            # Universal binary
│   ├── libboost_filesystem.a       # Universal binary
│   └── libboost_date_time.a        # Universal binary
└── third_party/
    ├── boost/                      # Boost headers
    └── libtorrent/                 # libtorrent headers
```

## Requirements

- macOS with Xcode command line tools
- Boost source code in `/Users/scottmacky/Documents/boost_1_88_0`
- libtorrent source code in `/Users/scottmacky/Documents/libtorrent` (auto-cloned if missing)

## Configuration

The scripts are configured to:
- Build static libraries (better for iOS distribution)
- Use C++17 standard
- Include necessary Boost libraries for libtorrent
- Build with position-independent code (PIC)
- Use built-in crypto (no external dependencies)

## Troubleshooting

### Build fails with "xcrun: error"
- Make sure Xcode command line tools are installed: `xcode-select --install`
- Verify iOS SDK is available: `xcrun --sdk iphoneos --show-sdk-path`

### "b2 not found" error
- The script will automatically run `bootstrap.sh` in the Boost directory
- Make sure Boost source is in the expected location

### Missing dependencies
- Ensure you have the required Boost version (1.88.0)
- Check that libtorrent is available (auto-cloned from GitHub if missing)

### Universal binary creation fails
- Ensure all architecture-specific builds completed successfully
- Check that `.a` files exist in expected locations
- Use `lipo -info <library.a>` to verify individual libraries

## Integration with Flutter

The iOS podspec (`ios/simple_torrent.podspec`) is configured to:
- Find headers in `../shared/third_party/`
- Link against libraries in `../shared/lib/ios/`
- Include all necessary Boost and libtorrent dependencies

After building, your Flutter iOS app should be able to use the libtorrent functionality.
