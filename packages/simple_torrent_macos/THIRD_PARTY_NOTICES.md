# Third-party notices

The bundled `simple_torrent_native` release artifact contains statically
linked code from these projects:

| Component | Pinned version | License |
| --- | --- | --- |
| libtorrent | 2.0.12 | BSD 3-Clause |
| Boost | 1.91.0 | Boost Software License 1.0 |
| OpenSSL | 3.5.8 LTS | Apache License 2.0 |
| Mozilla CA certificate bundle (curl extract) | 2026-08-13 | MPL 2.0 |

License texts and the Mozilla bundle's source/license reference are distributed
in `third_party_licenses/`. Exact source URLs, SHA-256 source checksums, build flags, architectures, and artifact
checksums are maintained in the simple_torrent repository's
`native/dependencies.lock.json` and generated
`native/artifacts.manifest.json`.

OpenSSL is linked statically and the pinned Mozilla CA extract is embedded in
the XCFramework to support HTTPS web seeds and secure trackers without a host
OpenSSL installation. Each component remains subject to its own license; the
surrounding Flutter plugin is licensed under BSD 3-Clause.
