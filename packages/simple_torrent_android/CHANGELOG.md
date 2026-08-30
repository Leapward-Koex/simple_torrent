# Changelog

## 2.0.0 - 2026-08-30

- Raised the minimum supported Android version to API 24.
- Added bundled release artifacts for `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- Adopted the shared v2 Dart channel implementation and manager-owned C ABI.
- Added session-wide runtime transfer suspension without altering per-torrent
  pause state.
- Bundled static OpenSSL and the C++ runtime for self-contained deployment.
- Replaced package-local dependency checkouts and build scripts with the root
  reproducible native builder.

## 1.0.0 - 2025-09-14

- Initial Android implementation release.
