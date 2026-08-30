# simple_torrent_android

Endorsed Android implementation of
[`simple_torrent`](https://pub.dev/packages/simple_torrent).

Consumers should depend on `simple_torrent`; Flutter selects this package
automatically. It supports Android API 24 or newer on `arm64-v8a`,
`armeabi-v7a`, and `x86_64`. Release artifacts bundle libtorrent, Boost, static
OpenSSL, and the C++ runtime, so consumers do not install an NDK or native
dependencies.

The adapter implements the session-wide `setTransfersSuspended` policy and
`areTransfersSuspended` query. Parent applications can atomically gate network
traffic for metered, roaming, offline, or background-restricted conditions
without changing any torrent's explicit pause state.

Maintainers build or verify the pinned artifacts from the repository root:

```powershell
./tool/native.ps1 build android
./tool/native.ps1 verify android
```

The build tooling pins Android NDK `29.0.13113456` and downloads all source
dependencies into the ignored repository cache.

Passing `--arch` makes the requested architectures the complete staged ABI set.
The tool removes only the known native library for each unrequested supported
ABI before it writes the manifest. Build without `--arch` to stage all three
release ABIs again.

The Android manifest entry retains its own dependency, recipe, and canonical
native-source fingerprint. Rebuilding another platform does not relabel the
Android binaries with newer inputs.

## License

BSD 3-Clause. See [LICENSE](LICENSE). Bundled dependency terms are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
