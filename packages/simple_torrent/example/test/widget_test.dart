import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_torrent_example/simple_torrent_example_app.dart';
import 'package:simple_torrent_example/src/download_directory.dart';
import 'package:simple_torrent_example/src/example_controller.dart';
import 'package:simple_torrent_example/src/example_models.dart';
import 'package:simple_torrent_example/src/torrent_service.dart';

void main() {
  testWidgets('agents can navigate every torrent action by stable key', (
    tester,
  ) async {
    final service = FakeTorrentService();
    final controller = ExampleController(
      service: service,
      downloadDirectory: const FixedDownloadDirectory(
        'private/default',
        pickedPath: 'human/chosen',
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(SimpleTorrentExampleApp(controller: controller));
    await tester.pumpAndSettle();

    for (final key in [
      ExampleKeys.initializationStatus,
      ExampleKeys.transfersSuspendedStatus,
      ExampleKeys.actionStatus,
      ExampleKeys.stateStatus,
      ExampleKeys.progressStatus,
      ExampleKeys.metadataStatus,
      ExampleKeys.errorStatus,
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
    expect(
      find.bySemanticsLabel('Persistent machine-readable torrent status'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Refresh active torrents'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Choose an optional download directory'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Start the magnet torrent'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Suspend all torrent transfers'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Resume all torrent transfers'),
      findsOneWidget,
    );
    expect(find.text('Initialization: ready'), findsOneWidget);
    expect(find.text('Transfers: active'), findsOneWidget);
    expect(find.byKey(ExampleKeys.emptyState), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(ExampleKeys.magnetField))
          .controller!
          .text,
      wiredMagnet,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(ExampleKeys.downloadPathField))
          .controller!
          .text,
      'private/default',
    );

    await _tapKey(tester, ExampleKeys.refreshButton);
    expect(controller.actionStatus, 'Active torrent list refreshed.');

    await _tapKey(tester, ExampleKeys.suspendTransfersButton);
    expect(service.actions, contains('setTransfersSuspended:true'));
    expect(find.text('Transfers: suspended'), findsOneWidget);
    expect(controller.actionStatus, 'All transfers suspended.');

    await _tapKey(tester, ExampleKeys.resumeTransfersButton);
    expect(service.actions, contains('setTransfersSuspended:false'));
    expect(find.text('Transfers: active'), findsOneWidget);
    expect(controller.actionStatus, 'All transfers resumed.');
    expect(
      service.actions.where((action) => action.startsWith('resume:')),
      isEmpty,
    );

    await tester.tap(find.byKey(ExampleKeys.pickDirectoryButton));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(ExampleKeys.downloadPathField))
          .controller!
          .text,
      'human/chosen',
    );

    await tester.enterText(find.byKey(ExampleKeys.magnetField), 'not-a-magnet');
    await tester.tap(find.byKey(ExampleKeys.startMagnetButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a magnet URI'), findsOneWidget);

    await tester.enterText(find.byKey(ExampleKeys.magnetField), wiredMagnet);
    await tester.tap(find.byKey(ExampleKeys.startMagnetButton));
    await tester.pumpAndSettle();

    expect(find.byKey(ExampleKeys.torrentCard(1)), findsOneWidget);
    expect(find.text('Active torrents: 1'), findsOneWidget);
    service.emitMetadata(
      const ExampleMetadata(
        id: 1,
        name: wiredTorrentName,
        totalBytes: 123,
        pieceSize: 64,
        pieceCount: 2,
        v1InfoHash: wiredV1InfoHash,
        files: [ExampleTorrentFile(path: 'track.mp3', size: 123, offset: 0)],
      ),
    );
    service.emitProgress(
      const ExampleProgress(
        id: 1,
        downloadRate: 100,
        uploadRate: 5,
        pieces: 1,
        piecesTotal: 2,
        progress: 0.5,
        seeds: 2,
        peers: 3,
        state: 'downloading',
      ),
    );
    await tester.pump();
    expect(find.textContaining('1/2 verified pieces'), findsOneWidget);
    expect(find.textContaining('$wiredTorrentName; 1 files'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Torrent 1, $wiredTorrentName, state downloading'),
      findsOneWidget,
    );
    for (final label in [
      'Pause torrent 1',
      'Resume torrent 1',
      'Cancel torrent 1 and delete files',
      'Finalise torrent 1 and keep files',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }

    await _tapKey(tester, ExampleKeys.pauseButton(1));
    expect(service.actions, contains('pause:1'));
    expect(find.text('State: paused'), findsOneWidget);

    await _tapKey(tester, ExampleKeys.resumeButton(1));
    expect(service.actions, contains('resume:1'));
    expect(find.text('State: downloading'), findsOneWidget);

    await _tapKey(tester, ExampleKeys.finaliseButton(1));
    expect(service.actions, contains('finalise:1'));
    expect(find.byKey(ExampleKeys.emptyState), findsOneWidget);

    await tester.tap(find.byKey(ExampleKeys.startMagnetButton));
    await tester.pumpAndSettle();
    expect(find.byKey(ExampleKeys.torrentCard(2)), findsOneWidget);
    await _tapKey(tester, ExampleKeys.cancelButton(2));
    expect(service.actions, contains('cancel:2'));
    expect(find.byKey(ExampleKeys.emptyState), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('initialization errors remain visible and disable start', (
    tester,
  ) async {
    final service = FakeTorrentService(initializationError: StateError('boom'));
    final controller = ExampleController(
      service: service,
      downloadDirectory: const FixedDownloadDirectory('private/default'),
    );
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(SimpleTorrentExampleApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Initialization: failed'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byKey(ExampleKeys.errorStatus)).data,
      contains('Initialization failed'),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(ExampleKeys.startMagnetButton),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('native error details are fetched quickly and remain visible', (
    tester,
  ) async {
    final service = FakeTorrentService(
      nativeErrors: const {1: 'disk write failed'},
    );
    final controller = ExampleController(
      service: service,
      downloadDirectory: const FixedDownloadDirectory('private/default'),
    );
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(SimpleTorrentExampleApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ExampleKeys.startMagnetButton));
    await tester.pumpAndSettle();

    service.emitProgress(_progressFor(id: 1, state: 'error'));
    await tester.pumpAndSettle();

    expect(service.lastErrorCalls, 1);
    expect(controller.actionStatus, 'Torrent 1 failed.');
    expect(controller.lastError, contains('disk write failed'));
    expect(
      tester.widget<SelectableText>(find.byKey(ExampleKeys.errorStatus)).data,
      contains('disk write failed'),
    );

    service.emitProgress(_progressFor(id: 1, state: 'stopped'));
    await tester.pump();
    expect(controller.lastError, contains('disk write failed'));
    expect(service.lastErrorCalls, 1);
  });

  test(
    'late native diagnostics are ignored after controller disposal',
    () async {
      final pending = Completer<String>();
      final service = FakeTorrentService(lastErrorCompleter: pending);
      final controller = ExampleController(
        service: service,
        downloadDirectory: const FixedDownloadDirectory('private/default'),
      );
      await controller.initialize();
      await controller.startMagnet();
      service.emitProgress(_progressFor(id: 1, state: 'error'));

      expect(controller.lastError, contains('loading native diagnostics'));
      expect(service.lastErrorCalls, 1);
      controller.dispose();
      pending.complete('late detail that must not be applied');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.lastError, isNot(contains('late detail')));
      await service.dispose();
    },
  );
}

ExampleProgress _progressFor({required int id, required String state}) =>
    ExampleProgress(
      id: id,
      downloadRate: 0,
      uploadRate: 0,
      pieces: 0,
      piecesTotal: 1,
      progress: 0,
      seeds: 0,
      peers: 0,
      state: state,
    );

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class FakeTorrentService implements ExampleTorrentService {
  FakeTorrentService({
    this.initializationError,
    this.nativeErrors = const {},
    this.lastErrorCompleter,
  });

  final Object? initializationError;
  final Map<int, String> nativeErrors;
  final Completer<String>? lastErrorCompleter;
  final actions = <String>[];
  final _torrents = <int, ExampleTorrent>{};
  final _latestProgress = <int, ExampleProgress>{};
  final _progress = StreamController<ExampleProgress>.broadcast(sync: true);
  final _metadata = StreamController<ExampleMetadata>.broadcast(sync: true);
  var _nextId = 1;
  var lastErrorCalls = 0;
  var _transfersSuspended = false;

  @override
  Future<void> initialize() async {
    if (initializationError case final error?) throw error;
  }

  @override
  Future<void> setTransfersSuspended(bool suspended) async {
    actions.add('setTransfersSuspended:$suspended');
    _transfersSuspended = suspended;
  }

  @override
  Future<bool> areTransfersSuspended() async => _transfersSuspended;

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) async {
    final id = _nextId++;
    _torrents[id] = ExampleTorrent(
      id: id,
      displayName: displayName ?? '',
      savePath: path,
      state: 'starting',
    );
    actions.add('start:$id');
    return id;
  }

  @override
  Future<void> pause(int id) async {
    actions.add('pause:$id');
    _emitState(id, 'paused');
  }

  @override
  Future<void> resume(int id) async {
    actions.add('resume:$id');
    _emitState(id, 'downloading');
  }

  @override
  Future<void> cancel(int id) async {
    actions.add('cancel:$id');
    _torrents.remove(id);
  }

  @override
  Future<void> finalise(int id) async {
    actions.add('finalise:$id');
    _torrents.remove(id);
  }

  @override
  Future<List<int>> getActiveTorrentIds() async => _torrents.keys.toList();

  @override
  Future<ExampleTorrent> getTorrentInfo(int id) async => _torrents[id]!;

  @override
  Future<String> getLastError(int id) {
    lastErrorCalls++;
    return lastErrorCompleter?.future ??
        Future<String>.value(nativeErrors[id] ?? '');
  }

  @override
  Stream<ExampleProgress> get progress => _progress.stream;

  @override
  Stream<ExampleMetadata> get metadata => _metadata.stream;

  void emitProgress(ExampleProgress value) {
    _latestProgress[value.id] = value;
    _progress.add(value);
    _setState(value.id, value.state);
  }

  void emitMetadata(ExampleMetadata value) => _metadata.add(value);

  void _setState(int id, String state) {
    final value = _torrents[id];
    if (value == null) return;
    _torrents[id] = value.copyWith(state: state);
  }

  void _emitState(int id, String state) {
    _setState(id, state);
    final value = _latestProgress[id];
    if (value != null) emitProgress(value.copyWith(state: state));
  }

  Future<void> dispose() async {
    await _progress.close();
    await _metadata.close();
  }
}
