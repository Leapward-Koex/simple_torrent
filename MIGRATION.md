# Migrating from simple_torrent 1.x to 2.0

Version 2.0 is a packaging and native-runtime reset. The static
`SimpleTorrent` facade, torrent lifecycle calls, helpers, extensions, and event
streams remain, while unsupported configuration and import shims are removed.

## Requirements and dependencies

- Upgrade to Dart 3.12+ and Flutter 3.44+.
- Depend only on `simple_torrent: ^2.0.0`.
- Remove direct or path dependencies on `simple_torrent_android`,
  `simple_torrent_ios`, `simple_torrent_macos`, `simple_torrent_windows`, and
  `simple_torrent_platform_interface`. Flutter resolves the endorsed package.
- Delete old package-local lockfiles in a repository workspace and run
  `flutter pub get` at the workspace root.
- Linux is not supported in 2.0.

The normal import remains:

```dart
import 'package:simple_torrent/simple_torrent.dart';
```

Remove imports of obsolete platform or compatibility shim libraries.

## Configuration

Replace the v1 configuration with the implemented, non-null settings:

| v1 | v2 | Note |
| --- | --- | --- |
| `maxTorrents` | `maxTorrents` | Non-null, validated |
| `maxDownloadRate` / `downloadLimit` | `downloadRateLimit` | Bytes/second; `0` unlimited |
| `maxUploadRate` / `uploadLimit` | `uploadRateLimit` | Bytes/second; `0` unlimited |
| `connections` | `connectionsLimit` | Non-null, validated |
| `enableDHT` | `enableDht` | Dart naming normalized |
| `userAgent` | `userAgent` | Non-empty, validated |
| `downloadPath` | removed | Supply a path to each start call |
| `autoManaged` | removed | Was not implemented |
| `sequentialDownload` | removed | Was not implemented |

Before:

```dart
const TorrentConfig(
  maxDownloadRate: 1024,
  downloadLimit: 1024,
  connections: 50,
  enableDHT: true,
  autoManaged: true,
);
```

After:

```dart
const TorrentConfig(
  maxTorrents: 5,
  downloadRateLimit: 1024 * 1024,
  uploadRateLimit: 0,
  connectionsLimit: 50,
  enableDht: true,
  userAgent: 'my_app/2.0',
);
```

## Torrent starts and state

Magnet starts keep `start(magnet:, path:, displayName:)`. In-memory starts keep
`startFromData(data:, downloadPath:, displayName:)`. Prefer the new canonical
file method:

```dart
await SimpleTorrent.startFromFile(
  torrentFilePath: torrentPath,
  downloadPath: destination,
);
```

`startFromTorrentFile` remains as an alias during the 2.x line. Internally all
platforms now use one consistent data/file wire contract.

Remove checks for the invalid `completed` state. A fully verified torrent enters
`TorrentState.seeding`. `TorrentMetadata` now supplies `v1InfoHash`,
`v2InfoHash`, and `files`; each `TorrentFile` has `path`, `size`, and `offset`.

## Errors and storage

Catch `SimpleTorrentException` and branch on its `SimpleTorrentErrorCode` instead
of parsing platform exception strings. Invalid configuration is rejected before
native work begins.

Use an app-private support or temporary directory for unattended operation.
Public Android Downloads paths may require scoped-storage interaction, and Apple
user-selected directories require a picker. The v2 example demonstrates an
app-private default with an optional picker.

## Native maintainers

Remove manually cloned Boost/libtorrent trees and old platform build scripts.
The only supported flow is the repository tool:

```powershell
.\tool\native.ps1 build windows
.\tool\native.ps1 build android
```

Sources are pinned, downloaded, and checksummed automatically. Existing 1.x
native binaries cannot be reused because 2.0 platform adapters consume the new
manager-based C ABI.
