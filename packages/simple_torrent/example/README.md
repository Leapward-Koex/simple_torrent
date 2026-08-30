# simple_torrent example

This is the single cross-platform example for the endorsed package graph. It
starts with the public WIRED sample magnet and an app-private download directory,
so automated runs never open a picker or permission dialog. The **Choose** button
is an optional human workflow.

```powershell
cd packages\simple_torrent\example
flutter run -d windows
```

## Agent-driven navigation

The widgets expose stable `ValueKey<String>` identifiers and matching semantics.
Agents should use Flutter widget/integration tests—not screen coordinates or a
computer-use tool.

| Action/output | Key |
| --- | --- |
| Magnet input | `magnet-field` |
| Download path | `download-path-field` |
| Optional picker | `pick-directory-button` |
| Start | `start-magnet-button` |
| Suspend/resume every transfer | `suspendTransfersButton`, `resumeTransfersButton` |
| Refresh | `refresh-button` |
| Persistent global suspension | `transfersSuspendedStatus` |
| Persistent init/action/state/progress/metadata/error | `*-status` |
| Torrent container | `torrent-<id>` |
| Lifecycle actions | `torrent-<id>-pause`, `-resume`, `-cancel`, `-finalise` |

All UI state lives in `ExampleController`, backed by injectable torrent and
directory services. The deterministic navigation suite covers initialization,
input validation, directory selection, start, metadata/progress rendering,
refresh, pause, resume, cancel, finalise, and errors:

```powershell
flutter test test/widget_test.dart
```

The deterministic native integration test uses two generated torrents and
throttled HTTP webseeds bound to IPv4 loopback. It needs no tracker, peer, DNS,
metered-network toggle, picker, or external payload:

```powershell
.\tool\test-suspension.ps1 windows -BuildMode debug
.\tool\test-suspension.ps1 android -BuildMode release
```

It proves that an active transfer becomes quiescent, starts remain accepted
while globally suspended, global resume does not override an individual torrent
pause, both payloads resume and verify, and finalisation retains the files.
Diagnostics are written under `build/test-suspension/`.

Flutter intentionally cannot drive non-web apps in Release mode because they
have no VM service. A requested `release` run first builds the actual Release
executable/APK, then runs the same native integration assertions in Profile
mode. `result.json` reports `releaseArtifactBuilt` and `testExecutionMode`
separately.

The complete live release test is terminal-driven and kept out of normal test
runs. From the repository root use:

```powershell
.\tool\test-sample.ps1 windows
.\tool\test-sample.ps1 android -BuildMode release
```

It validates the exact v1 hash and name, metadata, a verified piece, pause and
resume, 100% seeding state, every payload file and aggregate size, then finalises
while retaining files. It also cycles session-wide suspension without making a
timing assertion against the public internet. A successful run removes only its isolated temporary
directory. Set `SIMPLE_TORRENT_KEEP_ON_FAILURE=true` to preserve that directory
on failure. Diagnostics and a machine-readable result are written under
`build/test-sample/`, including when device or toolchain preflight fails. An
available Android x86_64 target is preferred automatically, and an explicit
device override must match the requested platform.
