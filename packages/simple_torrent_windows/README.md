# simple_torrent_windows

Endorsed Windows implementation of
[`simple_torrent`](https://pub.dev/packages/simple_torrent).

Consumers should depend on `simple_torrent`; Flutter selects this package
automatically. It supports Windows 10 or newer on x64. The package ships one
release `simple_torrent_native.dll` and import library behind a stable C ABI, so
the same artifact works in Flutter Debug and Release applications. Native build
tools and host-installed OpenSSL are not consumer requirements.

The shared `setTransfersSuspended` and `areTransfersSuspended` methods are
implemented by pausing the native libtorrent session, so applications can apply
their own metered-network policy without iterating individual torrents.

Maintainers build or verify the pinned artifact from the repository root:

```powershell
./tool/native.ps1 build windows
./tool/native.ps1 verify windows
```

## License

BSD 3-Clause. See [LICENSE](LICENSE). Bundled dependency terms are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
