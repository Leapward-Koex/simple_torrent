# simple_torrent

A focused Flutter API for downloading torrents with bundled libtorrent native
implementations on Android, iOS, macOS, and Windows.

## Install

```yaml
dependencies:
  simple_torrent: ^2.0.0
```

Do not add an implementation package directly. This package endorses the
correct implementation through Flutter's `default_package` mechanism.

Requirements are Dart 3.13+, Flutter 3.47+, Android 24+, iOS 15+, macOS 12+,
or Windows 10+ x64.

## Initialize and start

```dart
import 'package:simple_torrent/simple_torrent.dart';

await SimpleTorrent.init(
  config: const TorrentConfig(
    maxTorrents: 5,
    downloadRateLimit: 0,
    uploadRateLimit: 0,
    connectionsLimit: 200,
    enableDht: true,
    userAgent: 'my_app/1.0',
  ),
);

final id = await SimpleTorrent.start(
  magnet: magnetUri,
  path: appPrivateDirectory,
  displayName: 'Optional display name',
);
```

Rate limits are bytes per second and `0` means unlimited. Configuration fields
are non-null and validated before crossing the platform channel. Call
`SimpleTorrent.updateConfig` to update them at runtime.

The other start forms are:

```dart
final dataId = await SimpleTorrent.startFromData(
  data: torrentBytes,
  downloadPath: appPrivateDirectory,
);

final fileId = await SimpleTorrent.startFromFile(
  torrentFilePath: torrentFilePath,
  downloadPath: appPrivateDirectory,
);
```

`startFromTorrentFile` remains as a source-compatible alias for the canonical
`startFromFile` name.

## Observe and control

```dart
final subscription = SimpleTorrent.statsFor(id).listen((stats) {
  print('${stats.state.name}: ${stats.progress * 100}%');
  print('${stats.pieces}/${stats.piecesTotal} verified pieces');
});

final metadataSubscription = SimpleTorrent.metadataStream
    .where((metadata) => metadata.id == id)
    .listen((metadata) {
      print('v1: ${metadata.v1InfoHash}; v2: ${metadata.v2InfoHash}');
      for (final file in metadata.files) {
        print('${file.path}: ${file.size} bytes at ${file.offset}');
      }
    });

await SimpleTorrent.pause(id);
await SimpleTorrent.resume(id);
await SimpleTorrent.finalise(id); // remove session state, keep files
```

Use `cancel` when the payload should be deleted. Query methods include
`getActiveTorrentIds`, `exists`, `getState`, `getTorrentInfo`, and
`getLastError`. `TorrentInfo` convenience extensions and
`SimpleTorrentHelpers` remain available.

## Suspend transfers for network policy

The parent application should detect metered, roaming, offline, or restricted
network conditions and pass the resulting policy to `simple_torrent` at
runtime:

```dart
await SimpleTorrent.setTransfersSuspended(isMetered || !isOnline);
final suspended = await SimpleTorrent.areTransfersSuspended();
```

Suspension is session-wide and idempotent. Existing transfers stop, and starts
remain accepted but queued until suspension is removed. Toggling it does not
change whether an individual torrent was manually paused, so removing the
session suspension cannot accidentally resume a torrent the user paused.

This state is deliberately separate from `TorrentConfig`: the application owns
OS network detection, user overrides, and policy composition. It is not
persisted across plugin recreation, so apply the current policy after
initialization and before starting torrents. Serialize policy updates in the
application so an older asynchronous connectivity decision cannot overtake a
newer one, and reapply the combined policy whenever the native manager is
recreated. One already-queued stats event or a bounded amount of in-flight data
may still arrive after suspension; no new transfer work begins while the
session remains suspended. `SimpleTorrentHelpers.pauseAll` and `resumeAll`
remain per-torrent convenience operations and are not aliases for session
suspension.

Catch `SimpleTorrentException` to inspect a typed `SimpleTorrentErrorCode`.
Torrent states are `starting`, `downloadingMetadata`, `downloading`, `seeding`,
`paused`, `error`, and `stopped`.

## Storage

Pass a directory your application can write. App-private application-support or
temporary storage works without a permission dialog on all supported platforms.
The bundled example uses that as its default and offers a directory picker only
as an optional human workflow.

## Example and release test

Run the example from `packages/simple_torrent/example`. It exposes stable keys
and semantics and can be driven entirely by Flutter tests. The full external
WIRED download is intentionally separate from unit tests:

```powershell
.\tool\test-sample.ps1 windows
.\tool\test-sample.ps1 android
```

For `-BuildMode release`, the runner builds the actual Release artifact and
then uses Profile mode for the driven assertions because Flutter provides no VM
service—and therefore no non-web driver—in Release mode. The JSON result keeps
those two validation phases explicit.

See the repository
[README](https://github.com/Leapward-Koex/simple_torrent#readme) for native
artifact builds and
[migration guide](https://github.com/Leapward-Koex/simple_torrent/blob/master/MIGRATION.md)
for v1-to-v2 changes.
