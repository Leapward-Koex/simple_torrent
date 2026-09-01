# Third-party notices

The bundled `simple_torrent_native` release artifacts contain statically
linked code from the following projects. They are not fetched or built on an
application developer's machine.

<!-- BEGIN GENERATED NATIVE DEPENDENCIES -->

| Component | Pinned version | License (SPDX) |
| --- | --- | --- |
| libtorrent | 2.0.12 | BSD-3-Clause |
| Boost | 1.91.0 | BSL-1.0 |
| OpenSSL | 3.5.8 | Apache-2.0 |
| LLVM libc++ / libc++abi (Android only) | Android NDK 29.0.13113456 | Apache-2.0 WITH LLVM-exception |
| Mozilla CA certificate bundle | 2026-08-13 | MPL-2.0 |

<!-- END GENERATED NATIVE DEPENDENCIES -->

The downloaded source archives and Mozilla bundle have exact URLs and SHA-256
hashes in `native/dependencies.lock.json`. Android libc++ comes from the pinned
NDK installed by the Android SDK manager. License texts and source references
are in `native/licenses/`.

When required by the pinned Boost release, the builder applies the reviewed,
repository-tracked Android x86_64 long-double compatibility patch. Applied
patch paths and checksums are recorded in the authenticated source stamp and
artifact provenance, so a dependency version change cannot silently reuse a
patch for a different source release.

Release artifacts are built with C++17, DHT and extensions enabled, logging
and deprecated libtorrent APIs disabled, and OpenSSL linked statically.
Android uses API 24 and the static C++ runtime for `arm64-v8a`,
`armeabi-v7a`, and `x86_64`. Windows uses a release x64 DLL with a stable C
ABI. Apple outputs are static XCFrameworks for iOS device arm64, iOS simulator
arm64, and macOS arm64. Apple artifacts embed the pinned Mozilla
CA extract and materialize it into app-private Application Support before
creating the OpenSSL-backed session.

The Android libc++ terms are recorded in
`native/licenses/llvm-libcxx.txt`; the full Apache 2.0 text is also reproduced
in `native/licenses/openssl.txt`.

The generated `native/artifacts.manifest.json` records each artifact's
architecture, minimum platform, dependency versions, build type, source-date
epoch, file size, and SHA-256 checksum.
