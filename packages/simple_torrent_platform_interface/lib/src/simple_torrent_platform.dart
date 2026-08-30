import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'simple_torrent_exception.dart';
import 'torrent_config.dart';
import 'torrent_models.dart';

/// Cross-platform contract implemented by the endorsed platform packages.
abstract class SimpleTorrentPlatform extends PlatformInterface {
  SimpleTorrentPlatform() : super(token: _token);

  static final Object _token = Object();
  static SimpleTorrentPlatform _instance = _UnavailableSimpleTorrentPlatform();

  static SimpleTorrentPlatform get instance => _instance;

  static set instance(SimpleTorrentPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init({TorrentConfig? config});
  Future<void> updateConfig(TorrentConfig config);

  /// Suspends or restores all network transfers for this plugin instance.
  ///
  /// The default implementation preserves source compatibility for platform
  /// implementations that predate this API, while reporting that the runtime
  /// feature is unavailable when called.
  Future<void> setTransfersSuspended(bool suspended) async =>
      _transferSuspensionUnavailable();

  /// Whether network transfers are currently suspended for this plugin
  /// instance.
  Future<bool> areTransfersSuspended() async =>
      _transferSuspensionUnavailable();

  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  });

  Future<int> startFromData({
    required Uint8List data,
    required String path,
    String? displayName,
  });

  Future<int> startFromFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  });

  Future<void> pause(int id);
  Future<void> resume(int id);

  Future<void> togglePause(int id) async {
    final state = await getState(id);
    if (state == TorrentState.paused) {
      await resume(id);
    } else {
      await pause(id);
    }
  }

  Future<void> cancel(int id);
  Future<void> finalise(int id);
  Future<List<int>> getActiveTorrentIds();
  Future<bool> exists(int id);
  Future<TorrentState> getState(int id);
  Future<TorrentInfo> getTorrentInfo(int id);
  Future<String> getLastError(int id);

  Stream<TorrentStats> get statsStream;
  Stream<TorrentMetadata> get metadataStream;

  Stream<TorrentStats> statsFor(int id) =>
      statsStream.where((stats) => stats.id == id);

  Never _transferSuspensionUnavailable() => throw const SimpleTorrentException(
    SimpleTorrentErrorCode.unavailable,
    'The registered simple_torrent platform does not support transfer '
    'suspension.',
  );
}

class _UnavailableSimpleTorrentPlatform extends SimpleTorrentPlatform {
  Never _unavailable() => throw const SimpleTorrentException(
    SimpleTorrentErrorCode.unavailable,
    'No simple_torrent platform implementation has been registered.',
  );

  @override
  Future<void> init({TorrentConfig? config}) async => _unavailable();

  @override
  Future<void> updateConfig(TorrentConfig config) async => _unavailable();

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) async => _unavailable();

  @override
  Future<int> startFromData({
    required Uint8List data,
    required String path,
    String? displayName,
  }) async => _unavailable();

  @override
  Future<int> startFromFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  }) async => _unavailable();

  @override
  Future<void> pause(int id) async => _unavailable();

  @override
  Future<void> resume(int id) async => _unavailable();

  @override
  Future<void> cancel(int id) async => _unavailable();

  @override
  Future<void> finalise(int id) async => _unavailable();

  @override
  Future<List<int>> getActiveTorrentIds() async => _unavailable();

  @override
  Future<bool> exists(int id) async => _unavailable();

  @override
  Future<TorrentState> getState(int id) async => _unavailable();

  @override
  Future<TorrentInfo> getTorrentInfo(int id) async => _unavailable();

  @override
  Future<String> getLastError(int id) async => _unavailable();

  @override
  Stream<TorrentStats> get statsStream => Stream<TorrentStats>.error(
    const SimpleTorrentException(
      SimpleTorrentErrorCode.unavailable,
      'No simple_torrent platform implementation has been registered.',
    ),
  );

  @override
  Stream<TorrentMetadata> get metadataStream => Stream<TorrentMetadata>.error(
    const SimpleTorrentException(
      SimpleTorrentErrorCode.unavailable,
      'No simple_torrent platform implementation has been registered.',
    ),
  );
}
