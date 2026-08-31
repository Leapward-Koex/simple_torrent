// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:simple_torrent_example/simple_torrent_example_app.dart';
import 'package:simple_torrent_example/src/download_directory.dart';
import 'package:simple_torrent_example/src/example_controller.dart';
import 'package:simple_torrent_example/src/example_models.dart';
import 'package:simple_torrent_example/src/torrent_service.dart';

const _timeoutMinutes = int.fromEnvironment(
  'SIMPLE_TORRENT_TEST_TIMEOUT_MINUTES',
  defaultValue: 45,
);
const _keepOnFailure = bool.fromEnvironment(
  'SIMPLE_TORRENT_KEEP_ON_FAILURE',
  defaultValue: false,
);
const _expectedPlatform = String.fromEnvironment(
  'SIMPLE_TORRENT_EXPECTED_PLATFORM',
);
const _expectedPieceCount = 856;
const _resumedStates = {
  'starting',
  'downloadingMetadata',
  'downloading',
  'seeding',
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'downloads and verifies the complete WIRED torrent through keyed UI actions',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final root = await Directory.systemTemp.createTemp(
        'simple_torrent-wired-',
      );
      final service = const SimpleTorrentService();
      final controller = ExampleController(
        service: service,
        downloadDirectory: FixedDownloadDirectory(root.path),
      );
      var succeeded = false;
      var baselineCaptured = false;
      var preexistingIds = <int>{};
      int? torrentId;
      _event('started', {
        'root': root.path,
        'timeoutMinutes': _timeoutMinutes,
        'platform': Platform.operatingSystem,
      });

      try {
        expect(
          _expectedPlatform,
          anyOf('windows', 'android'),
          reason:
              'Run this release test through tool/test-sample.ps1 or '
              'tool/test-sample.sh so its target platform is explicit.',
        );
        expect(
          Platform.operatingSystem,
          _expectedPlatform,
          reason: 'The selected Flutter device does not match the requested platform.',
        );
        await tester.pumpWidget(
          SimpleTorrentExampleApp(controller: controller),
        );
        await _waitFor(
          tester,
          description: 'native initialization',
          timeout: const Duration(minutes: 2),
          condition: () => controller.isReady,
          error: () => controller.lastError,
        );
        expect(controller.downloadPath, root.path);
        expect(find.byKey(ExampleKeys.initializationStatus), findsOneWidget);
        preexistingIds = (await service.getActiveTorrentIds()).toSet();
        baselineCaptured = true;

        await tester.enterText(
          find.byKey(ExampleKeys.magnetField),
          wiredMagnet,
        );
        await _tap(tester, ExampleKeys.startMagnetButton);
        await _waitFor(
          tester,
          description: 'torrent start',
          timeout: const Duration(minutes: 2),
          condition: () {
            final selected = controller.selectedTorrentId;
            return selected != null &&
                !preexistingIds.contains(selected) &&
                controller.torrents.containsKey(selected);
          },
          error: () => controller.lastError,
        );
        torrentId = controller.selectedTorrentId;
        final id = torrentId!;
        _event('torrent_started', {'id': id});

        await _waitFor(
          tester,
          description: 'metadata',
          timeout: const Duration(minutes: 10),
          condition: () => controller.metadata[id]?.files.isNotEmpty ?? false,
          error: () => controller.lastError,
        );
        final metadata = controller.metadata[id]!;
        expect(metadata.name, wiredTorrentName);
        expect(metadata.v1InfoHash?.toLowerCase(), wiredV1InfoHash);
        expect(metadata.files, isNotEmpty);
        expect(metadata.totalBytes, greaterThan(0));
        expect(metadata.pieceSize, greaterThan(0));
        expect(metadata.pieceCount, _expectedPieceCount);
        expect(
          metadata.files.fold<int>(0, (total, file) => total + file.size),
          metadata.totalBytes,
        );
        _event('metadata_received', {
          'id': id,
          'name': metadata.name,
          'v1InfoHash': metadata.v1InfoHash,
          'v2InfoHash': metadata.v2InfoHash,
          'fileCount': metadata.files.length,
          'totalBytes': metadata.totalBytes,
          'pieceCount': metadata.pieceCount,
        });

        await _waitFor(
          tester,
          description: 'first verified piece',
          timeout: Duration(minutes: _timeoutMinutes),
          condition: () => (controller.progress[id]?.pieces ?? 0) > 0,
          error: () => controller.lastError,
        );
        final firstProgress = controller.progress[id]!;
        expect(firstProgress.piecesTotal, greaterThan(0));
        expect(firstProgress.piecesTotal, metadata.pieceCount);
        expect(firstProgress.piecesTotal, _expectedPieceCount);
        expect(
          firstProgress.pieces,
          lessThanOrEqualTo(firstProgress.piecesTotal),
        );
        expect(firstProgress.progress, greaterThan(0));
        expect(firstProgress.progress, lessThanOrEqualTo(1));
        _event('verified_piece_received', {
          'id': id,
          'pieces': firstProgress.pieces,
          'piecesTotal': firstProgress.piecesTotal,
          'progress': firstProgress.progress,
        });

        await _tap(tester, ExampleKeys.suspendTransfersButton);
        await _waitFor(
          tester,
          description: 'global transfer suspension',
          timeout: const Duration(seconds: 30),
          condition: () => controller.transfersSuspended && !controller.isBusy,
          error: () => controller.lastError,
        );
        expect(controller.progress[id]?.state, isNot('paused'));
        _event('transfers_suspended', {'id': id});

        await _tap(tester, ExampleKeys.resumeTransfersButton);
        await _waitFor(
          tester,
          description: 'global transfer resumption',
          timeout: const Duration(seconds: 30),
          condition: () => !controller.transfersSuspended && !controller.isBusy,
          error: () => controller.lastError,
        );
        _event('transfers_resumed', {'id': id});

        final pausedEvent = service.progress
            .firstWhere((value) => value.id == id && value.state == 'paused')
            .timeout(const Duration(seconds: 30));
        await _tap(tester, ExampleKeys.pauseButton(id));
        await pausedEvent;
        await _waitFor(
          tester,
          description: 'paused state',
          timeout: const Duration(seconds: 30),
          condition: () =>
              controller.progress[id]?.state == 'paused' && !controller.isBusy,
          error: () => controller.lastError,
        );
        expect(find.byKey(ExampleKeys.stateStatus), findsOneWidget);
        _event('paused', {'id': id});

        final resumedEvent = service.progress
            .firstWhere(
              (value) => value.id == id && _resumedStates.contains(value.state),
            )
            .timeout(const Duration(seconds: 30));
        await _tap(tester, ExampleKeys.resumeButton(id));
        await resumedEvent;
        await _waitFor(
          tester,
          description: 'resumed state',
          timeout: const Duration(seconds: 30),
          condition: () =>
              _resumedStates.contains(controller.progress[id]?.state) &&
              !controller.isBusy,
          error: () => controller.lastError,
        );
        _event('resumed', {'id': id});

        await _waitFor(
          tester,
          description: 'complete verified download',
          timeout: Duration(minutes: _timeoutMinutes),
          condition: () {
            final value = controller.progress[id];
            return value != null &&
                value.progress >= 1 &&
                value.piecesTotal > 0 &&
                value.pieces == value.piecesTotal &&
                value.state == 'seeding';
          },
          error: () => controller.lastError,
        );
        final complete = controller.progress[id]!;
        expect(complete.progress, greaterThanOrEqualTo(1));
        expect(complete.pieces, complete.piecesTotal);
        expect(complete.pieces, _expectedPieceCount);
        expect(complete.piecesTotal, _expectedPieceCount);
        expect(complete.state, 'seeding');
        _event('download_complete', {
          'id': id,
          'pieces': complete.pieces,
          'piecesTotal': complete.piecesTotal,
        });

        final verifiedFiles = await _verifyFiles(root, metadata);
        expect(verifiedFiles.totalBytes, metadata.totalBytes);
        expect(verifiedFiles.fileCount, metadata.files.length);
        _event('files_verified', {
          'fileCount': verifiedFiles.fileCount,
          'totalBytes': verifiedFiles.totalBytes,
        });

        await _tap(tester, ExampleKeys.finaliseButton(id));
        await _waitFor(
          tester,
          description: 'torrent finalisation',
          timeout: const Duration(minutes: 2),
          condition: () => !controller.torrents.containsKey(id),
          error: () => controller.lastError,
        );
        expect(await service.getActiveTorrentIds(), isNot(contains(id)));
        await _verifyFiles(root, metadata);
        _event('finalised_files_retained', {'id': id});
        succeeded = true;
      } catch (error, stackTrace) {
        _event('failed', {
          'error': '$error',
          'stackTrace': '$stackTrace',
          'root': root.path,
        });
        rethrow;
      } finally {
        if (!succeeded && baselineCaptured) {
          try {
            final activeIds = await service.getActiveTorrentIds();
            for (final id in activeIds.where(
              (candidate) => !preexistingIds.contains(candidate),
            )) {
              try {
                await service.finalise(id);
              } catch (error) {
                _event('cleanup_finalise_failed', {
                  'id': id,
                  'error': '$error',
                });
              }
            }
          } catch (error) {
            _event('cleanup_query_failed', {'error': '$error'});
          }
        }
        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());

        final keepFiles = !succeeded && _keepOnFailure;
        if (!keepFiles) {
          await _deleteWithRetry(root);
        }
        _event('result', {
          'passed': succeeded,
          'durationSeconds': DateTime.now()
              .toUtc()
              .difference(startedAt)
              .inSeconds,
          'root': root.path,
          'filesPreserved': keepFiles,
        });
      }
    },
    timeout: Timeout(Duration(minutes: _timeoutMinutes + 5)),
  );
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _waitFor(
  WidgetTester tester, {
  required String description,
  required Duration timeout,
  required bool Function() condition,
  required String Function() error,
}) async {
  final stopwatch = Stopwatch()..start();
  var nextDiagnostic = const Duration(seconds: 15);
  while (!condition()) {
    if (error().isNotEmpty) {
      fail('$description failed: ${error()}');
    }
    if (stopwatch.elapsed >= timeout) {
      fail('Timed out after ${timeout.inSeconds}s waiting for $description');
    }
    if (stopwatch.elapsed >= nextDiagnostic) {
      _event('waiting', {
        'for': description,
        'elapsedSeconds': stopwatch.elapsed.inSeconds,
      });
      nextDiagnostic += const Duration(seconds: 15);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  }
}

Future<({int fileCount, int totalBytes})> _verifyFiles(
  Directory root,
  ExampleMetadata metadata,
) async {
  final rootPath = p.normalize(p.absolute(root.path));
  var totalBytes = 0;
  for (final entry in metadata.files) {
    expect(entry.path, isNotEmpty);
    expect(p.isAbsolute(entry.path), isFalse);
    final filePath = p.normalize(p.join(rootPath, entry.path));
    expect(
      p.isWithin(rootPath, filePath),
      isTrue,
      reason: 'Metadata path escaped the isolated root: ${entry.path}',
    );
    final file = File(filePath);
    expect(await file.exists(), isTrue, reason: 'Missing payload: $filePath');
    final size = await file.length();
    expect(size, entry.size, reason: 'Unexpected payload size: $filePath');
    totalBytes += size;
  }
  return (fileCount: metadata.files.length, totalBytes: totalBytes);
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
