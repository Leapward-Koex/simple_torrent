# simple_torrent_platform_interface

Shared Dart types and channel implementation for the
[`simple_torrent`](https://pub.dev/packages/simple_torrent) federated Flutter
plugin.

Application authors should depend on `simple_torrent`, not this package. Native
implementation packages register the shared `MethodChannelSimpleTorrent` class
so Android, iOS, macOS, and Windows use one Dart wire contract.

Platform implementations must extend `SimpleTorrentPlatform`, register through
`SimpleTorrentPlatform.instance`, and use the stable channel names exported by
`SimpleTorrentChannelNames`. The contract supports magnet links, in-memory
`.torrent` data, `.torrent` files, lifecycle/query methods, progress events, and
metadata events.

The public models include byte-per-second `TorrentConfig` limits, typed
`SimpleTorrentException` codes, v1/v2 info hashes, and complete `TorrentFile`
entries.

Session-wide network policy uses the `setTransfersSuspended` method with a
Boolean `suspended` argument and the Boolean `areTransfersSuspended` query.
Starts remain valid while suspended, and session suspension must not mutate
per-torrent pause state. These are runtime operations rather than
`TorrentConfig` fields. The base platform interface provides typed
`unavailable` defaults so implementations written before this addition remain
source compatible.

See the repository's native integration documentation before implementing an
additional platform.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
