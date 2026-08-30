# Changelog

## 2.0.0 - 2026-08-30

- Raised the minimum supported operating system to Windows 10 x64.
- Replaced configuration-specific static linkage with a stable release DLL and
  import library used by Flutter Debug and Release applications.
- Adopted the shared v2 Dart channel implementation and manager-owned C ABI.
- Added atomic session-wide transfer suspension while preserving individual
  torrent pause state.
- Bundled static OpenSSL and removed package-local dependency checkouts.
- Replaced package-local build scripts with the root reproducible native builder.

## 1.0.0 - 2025-09-14

- Initial Windows implementation release.
