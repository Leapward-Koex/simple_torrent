# Changelog

## 2.0.0 - 2026-08-30

- Centralized the production MethodChannel and EventChannel implementation.
- Standardized the `startFromData` and `startFromFile` wire methods and keys.
- Reduced `TorrentConfig` to settings implemented by every native manager, with
  non-null defaults and byte-per-second rate limits.
- Added typed `SimpleTorrentException` codes.
- Added v1/v2 info hashes and `TorrentFile` entries to metadata.
- Added the `setTransfersSuspended` and `areTransfersSuspended` runtime wire
  contract with source-compatible typed-unavailable defaults.
- Removed the invalid `completed` state in favor of `seeding`.

## 1.0.0 - 2025-09-14

- Initial platform interface release.
