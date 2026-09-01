# Changelog

## Unreleased

- Generate, verify, and smoke-test the bundled XCFramework on ARM64 hosted
  macOS runners; Intel slices are no longer included.

## 2.0.0 - 2026-08-30

- Raised the minimum supported macOS version to 12.
- Switched native distribution to a static `arm64`/`x86_64` XCFramework.
- Added Swift Package Manager integration while retaining a CocoaPods fallback.
- Adopted the shared v2 Dart channel implementation and manager-owned C ABI.
- Added session-wide transfer suspension and suspension-state query handling.
- Removed package-local native source and dependency checkouts.

## 1.0.0 - 2025-09-14

- Initial macOS implementation release.
