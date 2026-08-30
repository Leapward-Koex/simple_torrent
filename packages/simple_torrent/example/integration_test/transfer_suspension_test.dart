// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:simple_torrent/simple_torrent.dart';

import 'support/throttled_web_seed.dart';

const _timeoutMinutes = int.fromEnvironment(
  'SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES',
  defaultValue: 5,
);
const _keepOnFailure = bool.fromEnvironment(
  'SIMPLE_TORRENT_KEEP_ON_FAILURE',
  defaultValue: false,
);
const _expectedPlatform = String.fromEnvironment(
  'SIMPLE_TORRENT_EXPECTED_PLATFORM',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'globally suspends transfers while preserving per-torrent pause state',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final root = await Directory.systemTemp.createTemp(
        'simple-torrent-suspension-',
      );
      final webSeed = await ThrottledWebSeedServer.start();
      final seedA = webSeed.fixtures[0];
      final seedB = webSeed.fixtures[1];
      final latest = <int, TorrentStats>{};
      final statsSubscription = SimpleTorrent.statsStream.listen(
        (stats) => latest[stats.id] = stats,
      );
      var initialized = false;
      var passed = false;
      var baselineIds = <int>{};
      final createdIds = <int>[];
      _event('started', {
        'root': root.path,
        'platform': Platform.operatingSystem,
        'timeoutMinutes': _timeoutMinutes,
        'payloadBytesEach': seedA.payload.length,
        'filesEach': seedA.files.length,
        'fileBytes': ThrottledWebSeedServer.fileLength,
        'pieceLength': seedA.pieceLength,
        'piecesEach': 128,
        'throttleChunkBytes': seedA.chunkSize,
        'aggregateThrottleBytesPerSecond': 512 * 1024,
      });

      try {
        expect(_expectedPlatform, anyOf('windows', 'android'));
        expect(Platform.operatingSystem, _expectedPlatform);
        expect(seedA.payload.length, 8 * 1024 * 1024);
        expect(seedB.payload.length, 8 * 1024 * 1024);
        expect(seedA.files, hasLength(32));
        expect(seedB.files, hasLength(32));
        expect(
          seedA.files.every(
            (file) => file.payload.length == ThrottledWebSeedServer.fileLength,
          ),
          isTrue,
        );
        expect(
          seedB.files.every(
            (file) => file.payload.length == ThrottledWebSeedServer.fileLength,
          ),
          isTrue,
        );
        expect(seedA.payloadUri.path, endsWith('/'));
        expect(seedB.payloadUri.path, endsWith('/'));
        expect(seedA.pieceLength, 64 * 1024);
        expect(seedA.payload.length ~/ seedA.pieceLength, 128);
        expect(seedB.payload.length ~/ seedB.pieceLength, 128);
        expect(seedA.fileName, isNot(seedB.fileName));
        expect(seedA.payload.first, isNot(seedB.payload.first));
        await SimpleTorrent.init(
          config: const TorrentConfig(
            maxTorrents: 4,
            downloadRateLimit: 0,
            uploadRateLimit: 0,
            connectionsLimit: 4,
            enableDht: false,
            userAgent: 'simple_torrent_suspension_test/2.0.0',
          ),
        );
        initialized = true;
        await SimpleTorrent.setTransfersSuspended(false);
        expect(await SimpleTorrent.areTransfersSuspended(), isFalse);
        baselineIds = (await SimpleTorrent.getActiveTorrentIds()).toSet();

        final pathA = p.join(root.path, 'a');
        final pathB = p.join(root.path, 'b');
        await Directory(pathA).create(recursive: true);
        await Directory(pathB).create(recursive: true);
        final idA = await SimpleTorrent.startFromData(
          data: seedA.torrentData,
          downloadPath: pathA,
          displayName: 'Suspension fixture A',
        );
        createdIds.add(idA);
        _event('first_transfer_started', {'id': idA});

        await _waitFor(
          tester,
          description: 'first transfer to reach a verified mid-download piece',
          condition: () {
            final value = latest[idA];
            return value != null &&
                value.pieces > 0 &&
                value.piecesTotal > 3 &&
                value.pieces < value.piecesTotal - 1;
          },
        );
        final baseline = latest[idA]!;
        _event('baseline_progress', {
          'id': idA,
          'pieces': baseline.pieces,
          'piecesTotal': baseline.piecesTotal,
          'bytesServed': seedA.bytesServed,
        });

        final boundaryBytes = seedA.bytesServed;
        final boundaryRequests = seedA.requestCount;
        await seedA.holdNewResponsesAndWaitForIdle();
        _event('response_boundary_held', {
          'id': idA,
          'bytesServedBeforeDrain': boundaryBytes,
          'bytesServedAfterDrain': seedA.bytesServed,
          'requestCountBeforeDrain': boundaryRequests,
          'requestCountAfterDrain': seedA.requestCount,
        });
        try {
          await SimpleTorrent.setTransfersSuspended(true);
        } finally {
          // Releasing immediately ensures queued HTTP requests expose a broken
          // native session gate instead of being masked by the test fixture.
          seedA.releaseHeldResponses();
        }
        expect(await SimpleTorrent.areTransfersSuspended(), isTrue);
        expect(
          await SimpleTorrent.getState(idA),
          isNot(TorrentState.paused),
          reason: 'Global suspension must not become a per-torrent pause.',
        );
        final quietWindow = await _waitForSuspendedWindow(
          tester,
          latest,
          idA,
          seedA,
        );
        _event('transfers_suspended', {
          'id': idA,
          'bytesDelta': 0,
          'piecesDelta': 0,
          'stableSeconds': 3,
          'settledAfterMilliseconds': quietWindow.settledAfterMilliseconds,
          'bytesServed': quietWindow.bytesServed,
          'pieces': quietWindow.pieces,
          'getRequestCount': seedA.getRequestCount,
          'headRequestCount': seedA.headRequestCount,
        });

        await SimpleTorrent.setTransfersSuspended(true);
        expect(await SimpleTorrent.areTransfersSuspended(), isTrue);
        _event('repeated_suspend_is_idempotent', {});

        final bBytesBeforeStart = seedB.bytesServed;
        final bGetsBeforeStart = seedB.getRequestCount;
        final bHeadsBeforeStart = seedB.headRequestCount;
        final idB = await SimpleTorrent.startFromData(
          data: seedB.torrentData,
          downloadPath: pathB,
          displayName: 'Suspension fixture B',
        );
        expect(idB, greaterThan(0));
        createdIds.add(idB);
        expect(await SimpleTorrent.getActiveTorrentIds(), contains(idB));
        await _observeNoTransferActivity(
          tester,
          latest,
          idB,
          seedB,
          expectedBytes: bBytesBeforeStart,
          expectedGets: bGetsBeforeStart,
          expectedHeads: bHeadsBeforeStart,
        );
        _event('start_queued_while_suspended', {
          'id': idB,
          'observationSeconds': 3,
          'bytesDelta': seedB.bytesServed - bBytesBeforeStart,
          'getRequestDelta': seedB.getRequestCount - bGetsBeforeStart,
          'headRequestDelta': seedB.headRequestCount - bHeadsBeforeStart,
          'pieces': 0,
        });

        await SimpleTorrent.pause(idB);
        expect(await SimpleTorrent.getState(idB), TorrentState.paused);
        _event('second_transfer_individually_paused', {'id': idB});

        await SimpleTorrent.setTransfersSuspended(false);
        expect(await SimpleTorrent.areTransfersSuspended(), isFalse);
        await _waitFor(
          tester,
          description: 'first transfer to resume and seed',
          condition: () => _isComplete(latest[idA]),
        );
        expect(await SimpleTorrent.getState(idB), TorrentState.paused);
        expect(seedB.bytesServed, bBytesBeforeStart);
        expect(seedB.getRequestCount, bGetsBeforeStart);
        expect(seedB.headRequestCount, bHeadsBeforeStart);
        expect(latest[idB]?.pieces ?? 0, 0);
        _event('global_resume_preserved_individual_pause', {
          'resumedId': idA,
          'pausedId': idB,
          'pausedTransferBytesDelta': seedB.bytesServed - bBytesBeforeStart,
          'pausedTransferRequestDelta':
              seedB.requestCount - bGetsBeforeStart - bHeadsBeforeStart,
        });

        await SimpleTorrent.resume(idB);
        await _waitFor(
          tester,
          description: 'second transfer to resume and seed',
          condition: () => _isComplete(latest[idB]),
        );
        _event('second_transfer_completed', {
          'id': idB,
          'pieces': latest[idB]!.pieces,
          'piecesTotal': latest[idB]!.piecesTotal,
        });

        await _expectFixturePayload(pathA, seedA);
        await _expectFixturePayload(pathB, seedB);
        _event('files_verified', {
          'fileCount': seedA.files.length + seedB.files.length,
          'totalBytes': seedA.payload.length + seedB.payload.length,
        });

        await SimpleTorrent.finalise(idA);
        await SimpleTorrent.finalise(idB);
        final activeAfterFinalise = await SimpleTorrent.getActiveTorrentIds();
        expect(activeAfterFinalise, isNot(contains(idA)));
        expect(activeAfterFinalise, isNot(contains(idB)));
        await _expectFixturePayload(pathA, seedA);
        await _expectFixturePayload(pathB, seedB);
        _event('finalised_files_retained', {
          'ids': [idA, idB],
          'fileCount': seedA.files.length + seedB.files.length,
        });
        passed = true;
      } catch (error, stackTrace) {
        _event('failed', {
          'error': '$error',
          'stackTrace': '$stackTrace',
          'root': root.path,
        });
        rethrow;
      } finally {
        if (initialized) {
          try {
            await SimpleTorrent.setTransfersSuspended(false);
          } on Object catch (error) {
            _event('cleanup_resume_failed', {'error': '$error'});
          }
          try {
            final active = await SimpleTorrent.getActiveTorrentIds();
            for (final id in active.where(
              (id) => createdIds.contains(id) && !baselineIds.contains(id),
            )) {
              try {
                await SimpleTorrent.finalise(id);
              } on Object catch (error) {
                _event('cleanup_finalise_failed', {
                  'id': id,
                  'error': '$error',
                });
              }
            }
          } on Object catch (error) {
            _event('cleanup_query_failed', {'error': '$error'});
          }
        }
        await statsSubscription.cancel();
        await webSeed.close();
        final preserveFiles = !passed && _keepOnFailure;
        if (!preserveFiles) await _deleteWithRetry(root);
        _event('result', {
          'passed': passed,
          'durationSeconds': DateTime.now()
              .toUtc()
              .difference(startedAt)
              .inSeconds,
          'root': root.path,
          'filesPreserved': preserveFiles,
        });
      }
    },
    timeout: Timeout(Duration(minutes: _timeoutMinutes + 2)),
  );
}

bool _isComplete(TorrentStats? value) =>
    value != null &&
    value.progress >= 1 &&
    value.piecesTotal > 0 &&
    value.pieces == value.piecesTotal &&
    value.state == TorrentState.seeding;

Future<({int bytesServed, int pieces, int settledAfterMilliseconds})>
_waitForSuspendedWindow(
  WidgetTester tester,
  Map<int, TorrentStats> latest,
  int id,
  ThrottledTorrentFixture seed,
) async {
  final stopwatch = Stopwatch()..start();
  var previousPieces = latest[id]?.pieces ?? 0;
  var previousBytes = seed.bytesServed;
  var stableSince = stopwatch.elapsed;
  // Ten seconds are allowed for in-flight work to settle, followed by the
  // required three-second stable observation (plus scheduler tolerance).
  while (stopwatch.elapsed < const Duration(seconds: 14)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    final currentPieces = latest[id]?.pieces ?? previousPieces;
    final currentBytes = seed.bytesServed;
    if (currentPieces != previousPieces || currentBytes != previousBytes) {
      if (stopwatch.elapsed >= const Duration(seconds: 10)) {
        throw TimeoutException(
          'Transfer did not settle within 10 seconds of suspension.',
        );
      }
      previousPieces = currentPieces;
      previousBytes = currentBytes;
      stableSince = stopwatch.elapsed;
    } else if (stopwatch.elapsed - stableSince >= const Duration(seconds: 3)) {
      return (
        bytesServed: currentBytes,
        pieces: currentPieces,
        settledAfterMilliseconds: stableSince.inMilliseconds,
      );
    }
  }
  throw TimeoutException(
    'Transfer did not hold a three-second stable server-byte and '
    'verified-piece window.',
  );
}

Future<void> _observeNoTransferActivity(
  WidgetTester tester,
  Map<int, TorrentStats> latest,
  int id,
  ThrottledTorrentFixture seed, {
  required int expectedBytes,
  required int expectedGets,
  required int expectedHeads,
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
    expect(seed.bytesServed, expectedBytes);
    expect(seed.getRequestCount, expectedGets);
    expect(seed.headRequestCount, expectedHeads);
    expect(latest[id]?.pieces ?? 0, 0);
  }
}

Future<void> _waitFor(
  WidgetTester tester, {
  required String description,
  required bool Function() condition,
}) async {
  final timeout = Duration(minutes: _timeoutMinutes);
  final stopwatch = Stopwatch()..start();
  var nextDiagnostic = const Duration(seconds: 10);
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      fail('Timed out after ${timeout.inSeconds}s waiting for $description');
    }
    if (stopwatch.elapsed >= nextDiagnostic) {
      _event('waiting', {
        'for': description,
        'elapsedSeconds': stopwatch.elapsed.inSeconds,
      });
      nextDiagnostic += const Duration(seconds: 10);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

Future<void> _expectFixturePayload(
  String downloadPath,
  ThrottledTorrentFixture fixture,
) async {
  final torrentRoot = p.normalize(p.join(downloadPath, fixture.fileName));
  expect(
    p.isWithin(p.normalize(downloadPath), torrentRoot),
    isTrue,
    reason: 'Torrent root escaped the isolated download path: $torrentRoot',
  );
  final aggregate = BytesBuilder(copy: false);
  for (final expectedFile in fixture.files) {
    final filePath = p.normalize(
      p.join(torrentRoot, expectedFile.relativePath),
    );
    expect(
      p.isWithin(torrentRoot, filePath),
      isTrue,
      reason: 'Fixture file escaped its torrent root: $filePath',
    );
    final file = File(filePath);
    expect(
      await file.exists(),
      isTrue,
      reason: 'Missing payload: ${file.path}',
    );
    final actual = await file.readAsBytes();
    _expectBytes(actual, expectedFile.payload, file.path);
    aggregate.add(actual);
  }
  _expectBytes(
    aggregate.takeBytes(),
    fixture.payload,
    '$torrentRoot (aggregate)',
  );
}

void _expectBytes(List<int> actual, List<int> expected, String label) {
  expect(actual.length, expected.length, reason: 'Wrong size: $label');
  for (var index = 0; index < expected.length; index++) {
    if (actual[index] != expected[index]) {
      fail('Payload mismatch at byte $index: $label');
    }
  }
}

Future<void> _deleteWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 4) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
  }
}

void _event(String event, Map<String, Object?> fields) {
  print(
    'SIMPLE_TORRENT_TEST_EVENT=${jsonEncode({'event': event, 'timestamp': DateTime.now().toUtc().toIso8601String(), ...fields})}',
  );
}
