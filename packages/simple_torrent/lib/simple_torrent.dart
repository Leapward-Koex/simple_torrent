library;

export 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart'
    show
        SimpleTorrentErrorCode,
        SimpleTorrentErrorCodeWireName,
        SimpleTorrentException,
        TorrentConfig,
        TorrentFile,
        TorrentInfo,
        TorrentMetadata,
        TorrentState,
        TorrentStats;

import 'dart:typed_data';

import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

/// Static facade for the registered simple_torrent platform implementation.
class SimpleTorrent {
  const SimpleTorrent._();

  static SimpleTorrentPlatform get _platform => SimpleTorrentPlatform.instance;

  static Future<void> init({TorrentConfig? config}) =>
      _platform.init(config: config);

  static Future<void> updateConfig(TorrentConfig config) =>
      _platform.updateConfig(config);

  /// Suspends or restores all network transfers for this plugin instance.
  ///
  /// Starting torrents remains allowed while suspended, but they do not
  /// transfer until suspension is removed. Per-torrent pause state is
  /// preserved across changes to this session-wide setting.
  static Future<void> setTransfersSuspended(bool suspended) =>
      _platform.setTransfersSuspended(suspended);

  /// Whether network transfers are currently suspended for this plugin
  /// instance.
  static Future<bool> areTransfersSuspended() =>
      _platform.areTransfersSuspended();

  static Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) => _platform.start(magnet: magnet, path: path, displayName: displayName);

  /// Starts a torrent from in-memory `.torrent` bytes.
  static Future<int> startFromData({
    required Uint8List data,
    required String downloadPath,
    String? displayName,
  }) => _platform.startFromData(
    data: data,
    path: downloadPath,
    displayName: displayName,
  );

  /// Starts a torrent from a `.torrent` file on disk.
  static Future<int> startFromFile({
    required String torrentFilePath,
    required String downloadPath,
    String? displayName,
  }) => _platform.startFromFile(
    torrentFilePath: torrentFilePath,
    path: downloadPath,
    displayName: displayName,
  );

  /// Backwards-compatible spelling of [startFromFile].
  static Future<int> startFromTorrentFile({
    required String torrentFilePath,
    required String downloadPath,
    String? displayName,
  }) => startFromFile(
    torrentFilePath: torrentFilePath,
    downloadPath: downloadPath,
    displayName: displayName,
  );

  static Future<void> pause(int id) => _platform.pause(id);
  static Future<void> resume(int id) => _platform.resume(id);
  static Future<void> togglePause(int id) => _platform.togglePause(id);
  static Future<void> cancel(int id) => _platform.cancel(id);
  static Future<void> finalise(int id) => _platform.finalise(id);
  static Future<List<int>> getActiveTorrentIds() =>
      _platform.getActiveTorrentIds();
  static Future<bool> exists(int id) => _platform.exists(id);
  static Future<TorrentState> getState(int id) => _platform.getState(id);
  static Future<TorrentInfo> getTorrentInfo(int id) =>
      _platform.getTorrentInfo(id);
  static Future<String> getLastError(int id) => _platform.getLastError(id);

  static Stream<TorrentStats> get statsStream => _platform.statsStream;
  static Stream<TorrentMetadata> get metadataStream => _platform.metadataStream;
  static Stream<TorrentStats> statsFor(int id) => _platform.statsFor(id);
}

extension TorrentInfoExtensions on TorrentInfo {
  Future<void> pause() => SimpleTorrent.pause(id);
  Future<void> resume() => SimpleTorrent.resume(id);
  Future<void> togglePause() => SimpleTorrent.togglePause(id);
  Future<void> cancel() => SimpleTorrent.cancel(id);
  Future<void> finalise() => SimpleTorrent.finalise(id);
  Stream<TorrentStats> get statsStream => SimpleTorrent.statsFor(id);
  Future<TorrentState> getCurrentState() => SimpleTorrent.getState(id);
}

/// Convenience operations composed from the static facade.
abstract final class SimpleTorrentHelpers {
  static Future<(int id, Stream<TorrentStats> stats)> startAndWatch({
    required String magnet,
    required String path,
    String? displayName,
  }) async {
    final id = await SimpleTorrent.start(
      magnet: magnet,
      path: path,
      displayName: displayName,
    );
    return (id, SimpleTorrent.statsFor(id));
  }

  static Future<void> pauseAll() async {
    final ids = await SimpleTorrent.getActiveTorrentIds();
    await Future.wait(ids.map(SimpleTorrent.pause));
  }

  static Future<void> resumeAll() async {
    final ids = await SimpleTorrent.getActiveTorrentIds();
    final states = await Future.wait(ids.map(SimpleTorrent.getState));
    final pausedIds = <int>[
      for (var index = 0; index < ids.length; index++)
        if (states[index] == TorrentState.paused) ids[index],
    ];
    await Future.wait(pausedIds.map(SimpleTorrent.resume));
  }

  static Future<List<TorrentInfo>> getAllTorrents() async {
    final ids = await SimpleTorrent.getActiveTorrentIds();
    return Future.wait(ids.map(SimpleTorrent.getTorrentInfo));
  }
}
