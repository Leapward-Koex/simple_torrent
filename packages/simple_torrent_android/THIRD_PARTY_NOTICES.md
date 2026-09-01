# Third-party notices

The bundled `simple_torrent_native` release artifact contains statically
linked code from these projects:

<!-- BEGIN GENERATED NATIVE DEPENDENCIES -->

| Component | Pinned version | License (SPDX) |
| --- | --- | --- |
| libtorrent | 2.0.12 | BSD-3-Clause |
| Boost | 1.91.0 | BSL-1.0 |
| OpenSSL | 3.5.8 | Apache-2.0 |
| LLVM libc++ / libc++abi | Android NDK 29.0.13113456 | Apache-2.0 WITH LLVM-exception |

<!-- END GENERATED NATIVE DEPENDENCIES -->

Complete license texts are distributed in `third_party_licenses/`. Exact
downloaded-source URLs, SHA-256 source checksums, build flags, architectures,
and artifact checksums are maintained in the simple_torrent repository's
`native/dependencies.lock.json` and generated
`native/artifacts.manifest.json`. libc++ is supplied by the pinned Android NDK
toolchain recorded there.

When required by the pinned Boost release, the maintainer build applies the
reviewed Android x86_64 long-double compatibility patch documented in the root
third-party notices. Its path and checksum are recorded in artifact provenance.

OpenSSL is linked statically to support HTTPS web seeds and secure trackers
without requiring a host OpenSSL installation. Each component remains subject
to its own license; the surrounding Flutter plugin is licensed under BSD 3-Clause.

The LLVM exception is reproduced in
`third_party_licenses/llvm-libcxx.txt`; the full Apache 2.0 text is also
reproduced in `third_party_licenses/openssl.txt`.
