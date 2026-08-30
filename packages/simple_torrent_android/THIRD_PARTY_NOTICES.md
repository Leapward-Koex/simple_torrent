# Third-party notices

The bundled `simple_torrent_native` release artifact contains statically
linked code from these projects:

| Component | Pinned version | License |
| --- | --- | --- |
| libtorrent | 2.0.12 | BSD 3-Clause |
| Boost | 1.91.0 | Boost Software License 1.0 |
| OpenSSL | 3.5.8 LTS | Apache License 2.0 |
| LLVM libc++ / libc++abi | Android NDK 29.0.13113456 toolchain | Apache License 2.0 with LLVM Exception |

Complete license texts are distributed in `third_party_licenses/`. Exact
downloaded-source URLs, SHA-256 source checksums, build flags, architectures,
and artifact checksums are maintained in the simple_torrent repository's
`native/dependencies.lock.json` and generated
`native/artifacts.manifest.json`. libc++ is supplied by the pinned Android NDK
toolchain recorded there.

The maintainer build applies the repository-tracked Boost 1.91.0 Android
x86_64 long-double detection patch documented in the root third-party notices.

OpenSSL is linked statically to support HTTPS web seeds and secure trackers
without requiring a host OpenSSL installation. Each component remains subject
to its own license; the surrounding Flutter plugin is licensed under BSD 3-Clause.

The LLVM exception is reproduced in
`third_party_licenses/llvm-libcxx.txt`; the full Apache 2.0 text is also
reproduced in `third_party_licenses/openssl.txt`.
