import 'dart:async';

import 'package:flutter/foundation.dart';

import 'download_directory.dart';
import 'example_models.dart';
import 'torrent_service.dart';

class ExampleController extends ChangeNotifier {
  factory ExampleController({
    required ExampleTorrentService service,
    required ExampleDownloadDirectory downloadDirectory,
    String initialMagnet = wiredMagnet,
  }) => ExampleController._(service, downloadDirectory, initialMagnet);

  ExampleController._(this._service, this._downloadDirectory, this._magnet);

  final ExampleTorrentService _service;
  final ExampleDownloadDirectory _downloadDirectory;
  final Map<int, ExampleTorrent> _torrents = {};
  final Map<int, ExampleProgress> _progress = {};
  final Map<int, ExampleMetadata> _metadata = {};

  StreamSubscription<ExampleProgress>? _progressSubscription;
  StreamSubscription<ExampleMetadata>? _metadataSubscription;
  Future<void>? _initialization;
  bool _disposed = false;
  bool _busy = false;
  bool _transfersSuspended = false;
  int _nativeErrorGeneration = 0;
  int? _selectedTorrentId;
  String _magnet;
  String _downloadPath = '';
  String _actionStatus = 'No action has run.';
  String _lastError = '';
  ExampleInitializationState _initializationState =
      ExampleInitializationState.idle;

  ExampleInitializationState get initializationState => _initializationState;
  bool get isReady => _initializationState == ExampleInitializationState.ready;
  bool get isBusy => _busy;
  bool get transfersSuspended => _transfersSuspended;
  String get magnet => _magnet;
  String get downloadPath => _downloadPath;
  String get actionStatus => _actionStatus;
  String get lastError => _lastError;
  int? get selectedTorrentId => _selectedTorrentId;
  Map<int, ExampleTorrent> get torrents => immutableView(_torrents);
  Map<int, ExampleProgress> get progress => immutableView(_progress);
  Map<int, ExampleMetadata> get metadata => immutableView(_metadata);

  String get initializationStatus => switch (_initializationState) {
    ExampleInitializationState.idle => 'Initialization: idle',
    ExampleInitializationState.initializing => 'Initialization: initializing',
    ExampleInitializationState.ready => 'Initialization: ready',
    ExampleInitializationState.failed => 'Initialization: failed',
  };

  String get transferSuspensionStatus =>
      'Transfers: ${_transfersSuspended ? 'suspended' : 'active'}';

  String get stateStatus {
    final id = _selectedTorrentId;
    if (id == null) return 'State: no torrent selected';
    final state = _progress[id]?.state ?? _torrents[id]?.state ?? 'starting';
    return 'State: $state (torrent $id)';
  }

  String get progressStatus {
    final id = _selectedTorrentId;
    final value = id == null ? null : _progress[id];
    if (id == null || value == null) return 'Progress: waiting';
    final percentage = (value.progress * 100).clamp(0, 100).toStringAsFixed(1);
    return 'Progress: $percentage% '
        '(${value.pieces}/${value.piecesTotal} verified pieces, torrent $id)';
  }

  String get metadataStatus {
    final id = _selectedTorrentId;
    final value = id == null ? null : _metadata[id];
    if (id == null || value == null) return 'Metadata: waiting';
    return 'Metadata: ${value.name}; ${value.files.length} files; '
        '${value.totalBytes} bytes; torrent $id';
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _initializationState = ExampleInitializationState.initializing;
    _clearError();
    _notify();
    _progressSubscription = _service.progress.listen(
      _onProgress,
      onError: (Object error, StackTrace stackTrace) =>
          _recordError('Progress stream failed', error),
    );
    _metadataSubscription = _service.metadata.listen(
      _onMetadata,
      onError: (Object error, StackTrace stackTrace) =>
          _recordError('Metadata stream failed', error),
    );

    try {
      _downloadPath = await _downloadDirectory.getDefaultPath();
      await _service.initialize();
      _transfersSuspended = await _service.areTransfersSuspended();
      await refresh(silent: true);
      _initializationState = ExampleInitializationState.ready;
      _actionStatus = 'Torrent engine initialized.';
    } catch (error) {
      _initializationState = ExampleInitializationState.failed;
      _recordError('Initialization failed', error, notify: false);
    }
    _notify();
  }

  void setMagnet(String value) {
    _magnet = value;
  }

  void setDownloadPath(String value) {
    _downloadPath = value;
  }

  Future<bool> pickDownloadDirectory() async {
    try {
      final picked = await _downloadDirectory.pickPath();
      if (picked == null) {
        _actionStatus = 'Directory selection cancelled.';
        _notify();
        return false;
      }
      _downloadPath = picked;
      _actionStatus = 'Download directory selected.';
      _clearError();
      _notify();
      return true;
    } catch (error) {
      _recordError('Directory selection failed', error);
      return false;
    }
  }

  Future<bool> suspendTransfers() => _setTransfersSuspended(true);

  Future<bool> resumeTransfers() => _setTransfersSuspended(false);

  Future<bool> _setTransfersSuspended(bool suspended) async {
    _setBusy(true);
    try {
      await _service.setTransfersSuspended(suspended);
      _transfersSuspended = await _service.areTransfersSuspended();
      _actionStatus = _transfersSuspended
          ? 'All transfers suspended.'
          : 'All transfers resumed.';
      _clearError();
      return true;
    } catch (error) {
      _recordError(
        suspended ? 'Suspend transfers failed' : 'Resume transfers failed',
        error,
        notify: false,
      );
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<int?> startMagnet() async {
    final magnet = _magnet.trim();
    final path = _downloadPath.trim();
    if (!magnet.startsWith('magnet:?')) {
      _recordError('Start failed', const FormatException('Enter a magnet URI'));
      return null;
    }
    if (path.isEmpty) {
      _recordError(
        'Start failed',
        const FormatException('Choose a download directory'),
      );
      return null;
    }

    _setBusy(true);
    try {
      final id = await _service.start(magnet: magnet, path: path);
      _selectedTorrentId = id;
      _torrents[id] = ExampleTorrent(
        id: id,
        displayName: 'Torrent $id',
        savePath: path,
        state: 'starting',
      );
      _actionStatus = 'Started torrent $id.';
      _clearError();
      await refresh(silent: true);
      return id;
    } catch (error) {
      _recordError('Start failed', error, notify: false);
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refresh({bool silent = false}) async {
    try {
      final ids = await _service.getActiveTorrentIds();
      final active = ids.toSet();
      _torrents.removeWhere((id, _) => !active.contains(id));
      _progress.removeWhere((id, _) => !active.contains(id));
      for (final id in ids) {
        try {
          _torrents[id] = await _service.getTorrentInfo(id);
        } catch (_) {
          // A newly started torrent may not have a query snapshot yet. Stream
          // events and the next refresh will fill it without hiding its card.
        }
      }
      if (_selectedTorrentId == null || !active.contains(_selectedTorrentId)) {
        _selectedTorrentId = ids.isEmpty ? null : ids.last;
      }
      if (!silent) {
        _actionStatus = 'Active torrent list refreshed.';
        _clearError();
      }
    } catch (error) {
      _recordError('Refresh failed', error, notify: false);
    }
    _notify();
  }

  Future<bool> pause(int id) => _runTorrentAction(
    id,
    verb: 'Paused',
    operation: () => _service.pause(id),
  );

  Future<bool> resume(int id) => _runTorrentAction(
    id,
    verb: 'Resumed',
    operation: () => _service.resume(id),
  );

  Future<bool> cancel(int id) => _runTorrentAction(
    id,
    verb: 'Cancelled',
    operation: () => _service.cancel(id),
  );

  Future<bool> finalise(int id) => _runTorrentAction(
    id,
    verb: 'Finalised',
    operation: () => _service.finalise(id),
  );

  Future<bool> _runTorrentAction(
    int id, {
    required String verb,
    required Future<void> Function() operation,
  }) async {
    _selectedTorrentId = id;
    _setBusy(true);
    try {
      await operation();
      _actionStatus = '$verb torrent $id.';
      _clearError();
      await refresh(silent: true);
      return true;
    } catch (error) {
      _recordError('$verb operation failed', error, notify: false);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  void _onProgress(ExampleProgress value) {
    final previousState = _progress[value.id]?.state;
    _progress[value.id] = value;
    final current = _torrents[value.id];
    if (current != null) {
      _torrents[value.id] = current.copyWith(state: value.state);
    }
    _selectedTorrentId ??= value.id;
    if (value.state == 'error' && previousState != 'error') {
      _startNativeErrorDiagnostic(value.id);
      return;
    }
    _notify();
  }

  void _startNativeErrorDiagnostic(int id) {
    final generation = ++_nativeErrorGeneration;
    _selectedTorrentId = id;
    _actionStatus = 'Torrent $id entered an error state.';
    _lastError = 'Torrent $id failed; loading native diagnostics.';
    _notify();
    unawaited(_loadNativeError(id, generation));
  }

  Future<void> _loadNativeError(int id, int generation) async {
    String message;
    try {
      final nativeMessage = (await _service.getLastError(id)).trim();
      message = nativeMessage.isEmpty
          ? 'the native manager provided no additional detail'
          : nativeMessage;
    } catch (error) {
      message = 'native diagnostics could not be read: $error';
    }
    if (_disposed || generation != _nativeErrorGeneration) return;
    _actionStatus = 'Torrent $id failed.';
    _lastError = 'Torrent $id failed: $message';
    _notify();
  }

  void _clearError() {
    _nativeErrorGeneration++;
    _lastError = '';
  }

  void _onMetadata(ExampleMetadata value) {
    _metadata[value.id] = value;
    final current = _torrents[value.id];
    if (current != null) {
      _torrents[value.id] = current.copyWith(displayName: value.name);
    }
    _selectedTorrentId ??= value.id;
    _notify();
  }

  void _setBusy(bool value) {
    _busy = value;
    _notify();
  }

  void _recordError(String context, Object error, {bool notify = true}) {
    _nativeErrorGeneration++;
    _lastError = '$context: $error';
    _actionStatus = context;
    if (notify) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_progressSubscription?.cancel());
    unawaited(_metadataSubscription?.cancel());
    super.dispose();
  }
}
