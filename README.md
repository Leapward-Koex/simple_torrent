# simple_torrent

`simple_torrent` is a federated Flutter BitTorrent plugin backed by libtorrent.
Version 2.0 keeps the small static Dart API while giving every platform its own
publishable package and bundled native implementation.

## Packages

| Package | Purpose |
| --- | --- |
| `simple_torrent` | App-facing API and platform endorsements |
| `simple_torrent_platform_interface` | Types, contract, and MethodChannel implementation |
| `simple_torrent_android` | Android 24+ implementation |
| `simple_torrent_ios` | iOS 15+ implementation |
| `simple_torrent_macos` | macOS 12+ implementation |
| `simple_torrent_windows` | Windows 10+ x64 implementation |

Applications depend only on `simple_torrent`; Flutter selects the endorsed
implementation. The repository root is a Dart Pub workspace, so development
uses one dependency resolution and one lockfile.

## Consumer quick start

```yaml
dependencies:
  simple_torrent: ^2.0.0
```

```dart
import 'package:simple_torrent/simple_torrent.dart';

await SimpleTorrent.init(
  config: const TorrentConfig(
    maxTorrents: 5,
    downloadRateLimit: 0, // bytes/second; zero is unlimited
    uploadRateLimit: 0,
    connectionsLimit: 200,
    enableDht: true,
    userAgent: 'my_app/1.0',
  ),
);

final id = await SimpleTorrent.start(
  magnet: 'magnet:?xt=urn:btih:...',
  path: appPrivateDownloadPath,
);

final progress = SimpleTorrent.statsFor(id);
final metadata = SimpleTorrent.metadataStream.where((item) => item.id == id);
```

Use `pause`, `resume`, `cancel`, and `finalise` for lifecycle control. `cancel`
removes payload files; `finalise` removes the torrent from the active set while
retaining them. Metadata includes v1/v2 info hashes and individual file paths,
sizes, and offsets. API failures are `SimpleTorrentException` values with a
typed `SimpleTorrentErrorCode`.

See [the package README](packages/simple_torrent/README.md) for API details and
[MIGRATION.md](MIGRATION.md) when upgrading from v1.

## Suspend transfers for network policy

The parent application detects metered, roaming, offline, or otherwise
restricted connectivity and applies its combined runtime policy explicitly:

```dart
await SimpleTorrent.init();
await SimpleTorrent.setTransfersSuspended(isMetered || !isOnline);
final suspended = await SimpleTorrent.areTransfersSuspended();
// Start torrents only after the initial policy has been applied.
```

Suspension is session-wide runtime state, not `TorrentConfig`, and the plugin
does not perform OS connectivity detection. Serialize asynchronous policy
updates so stale decisions cannot overtake newer ones, and reapply the current
policy after native-manager/plugin recreation before accepting starts. Starts
remain accepted and queued while suspended; one already-queued stats event or
a bounded amount of in-flight data may still arrive while suspension settles.
Global suspension never changes a torrent's individual pause state.
`SimpleTorrentHelpers.pauseAll` and `resumeAll` remain per-torrent convenience
operations, not aliases for the session policy.

## Reproducible native artifacts

No manually placed Boost or libtorrent checkout is required. The native tool
downloads pinned archives into ignored `.native-cache/`, builds under
`build/native/`, stages release artifacts into the implementation packages, and
writes a checksummed manifest.

```powershell
.\tool\native.ps1 build windows
.\tool\native.ps1 verify windows
.\tool\native.ps1 build android
.\tool\native.ps1 verify android
```

```bash
./tool/native.sh build ios
./tool/native.sh verify ios
./tool/native.sh build macos
./tool/native.sh verify macos
```

Useful options are repeatable `--arch`, `--offline`, and `purge-cache`:

```powershell
.\tool\native.ps1 build android --arch x86_64 --offline
.\tool\native.ps1 clean android
.\tool\native.ps1 purge-cache openssl
.\tool\native.ps1 purge-cache mozilla-ca-bundle
```

For Android, `--arch` defines the complete staged ABI set for that invocation.
The builder removes only the known `libsimple_torrent_native.so` file for each
unrequested supported ABI before staging and manifest generation, so a partial
build cannot relabel an older binary as current. Run `build android` without
`--arch` to restore the three-ABI release bundle.

The lock pins libtorrent 2.0.12, Boost 1.91.0, OpenSSL 3.5.8 LTS, and Android
NDK 29.0.13113456, plus a checksummed 2026-08-13 Mozilla CA extract for Apple.
OpenSSL is statically linked on every platform. Android also statically links
the NDK's LLVM libc++ runtime, Windows uses the static MSVC runtime, and Apple
links the operating system's libc++. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the generated artifact
manifest for exact versions, flags, checksums, and architectures.
`verify` checks manifest schema, builder/C-ABI version, dependency archives,
canonical patch identity, auxiliary inputs, and pinned toolchains against the
current lock before it authenticates any staged binary. Every platform record
also owns the exact build-provenance snapshot and a line-ending-normalized
fingerprint of the canonical native CMake, headers, sources, patches, and
builder inputs used for it. Building one platform never refreshes preserved
platform records; those platforms continue to fail verification until rebuilt
from the current inputs. Verification also independently inventories each
target's staging roots and requires exact path-set equality with its manifest;
missing files, unmanifested files, and links are rejected before checksums or
binary inspection.

## Verification

Ordinary checks do not download external torrent payloads:

```powershell
flutter pub get
$dartSources = rg --files packages tool -g '*.dart' -g '!**/build/**' -g '!**/.dart_tool/**'
dart format --output=none --set-exit-if-changed $dartSources
flutter analyze --no-pub $dartSources
Push-Location packages\simple_torrent
flutter test --no-pub
Pop-Location
dart run tool/test/native_builder_test.dart
dart run tool/test/lifecycle_serialization_test.dart
dart run tool/test/session_suspension_contract_test.dart
dart run tool/test/test_runner_contract_test.dart
```

Repeat analysis/tests in `simple_torrent_platform_interface` and the example;
analyze each platform registrar package. Publication checks use
`dart pub publish --dry-run` from each of the six package directories.

Session suspension has a deterministic device test backed by throttled
loopback-only webseeds. It does not change the host's metered-network settings:

```powershell
.\tool\test-suspension.ps1 windows -BuildMode debug
.\tool\test-suspension.ps1 android -BuildMode release
```

The shell equivalent is `./tool/test-suspension.sh android release`. Logs and a
JSON result are stored under `build/test-suspension/`. Flutter does not support
driving a non-web Release app because Release mode has no VM service. For a
requested `release` run, the script therefore builds the real Release
executable/APK first, then runs the assertions in supported Profile mode against
the same bundled release native library. The JSON records both
`buildMode: release` and `testExecutionMode: profile` so this is never
misreported as an AOT-driven test.

The release gate downloads and verifies the complete public WIRED sample using
Flutter's terminal integration-test tooling:

```powershell
.\tool\test-sample.ps1 windows
.\tool\test-sample.ps1 android -BuildMode release
```

The shell equivalent is `./tool/test-sample.sh android`. A connected Android
device is selected automatically; override it with
`SIMPLE_TORRENT_DEVICE_ID`. The default timeout is 45 minutes. Set
`SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES` to change it or
`SIMPLE_TORRENT_KEEP_ON_FAILURE=true` to retain the isolated payload directory.
Select `debug` or `release` with `-BuildMode` (PowerShell), an optional second
shell argument, or `SIMPLE_TORRENT_BUILD_MODE`. Release selection follows the
Release-build-plus-Profile-driver behavior described above.
Android auto-selection prefers an available x86_64 target, and overrides are
rejected when they do not match the requested platform. Every invocation,
including a preflight failure, stores logs plus a JSON result under
`build/test-sample/` and exits nonzero on failure.

The Windows and Android artifacts can be built and exercised in this
repository. Apple build commands, manifests, SwiftPM integration, and CocoaPods
fallback are validated structurally here; runtime Apple validation must be run
on macOS with Xcode. Do not publish either Apple implementation package from a
checkout that has not completed its matching `build` and `verify` commands:
the final publication dry-run must list the generated XCFramework and its
checksummed static libraries.

## License

The Dart/plugin code is BSD 3-Clause licensed. Bundled third-party components retain
their respective licenses; see `THIRD_PARTY_NOTICES.md`.
