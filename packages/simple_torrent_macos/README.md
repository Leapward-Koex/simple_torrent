# simple_torrent_macos

Endorsed macOS implementation of
[`simple_torrent`](https://pub.dev/packages/simple_torrent).

Consumers should depend on `simple_torrent`; Flutter selects this package
automatically. It supports macOS 12 or newer on Apple Silicon and Intel Macs.
The package ships a static `arm64`/`x86_64` XCFramework containing the pinned
native dependencies.
The XCFramework also embeds a pinned Mozilla CA extract, materialized into the
app's private Application Support directory for OpenSSL certificate checks.

Swift Package Manager is the primary integration. A CocoaPods fallback is also
included, and neither integration uses Homebrew or developer-specific paths.
Enable Flutter's SwiftPM integration once on the macOS build host with
`flutter config --enable-swift-package-manager`. If it is disabled, Flutter
uses the included podspec fallback.

The adapter implements the session-wide `setTransfersSuspended` policy and
the `areTransfersSuspended` query. Suspending transfers pauses network traffic
without changing each torrent's explicit lifecycle state, so connectivity and
metered-network policies can be applied and later reversed as one operation.

Maintainers generate and verify artifacts on macOS from the repository root:

```sh
./tool/native.sh build macos
./tool/native.sh verify macos
flutter config --enable-swift-package-manager
cd packages/simple_torrent/example
flutter build macos
cd ../../simple_torrent_macos
dart pub publish --dry-run
```

Do not publish if the dry-run archive does not contain
`macos/Frameworks/SimpleTorrentNative.xcframework`; generated Apple artifacts
must be staged and verified on macOS first.

## License

BSD 3-Clause. See [LICENSE](LICENSE). Bundled dependency terms are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
