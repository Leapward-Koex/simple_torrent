library;

export 'simple_torrent_platform_interface.dart' show TorrentStats, TorrentMetadata, TorrentState, TorrentInfo, TorrentConfig;

import 'simple_torrent_platform_interface.dart';

/// Public API used by Flutter apps.
class SimpleTorrent {
  const SimpleTorrent._();

  static final _p = SimpleTorrentPlatform.instance;

  static Future<void> init({TorrentConfig? config}) => _p.init(config: config);

  /// Update torrent manager configuration at runtime
  static Future<void> updateConfig(TorrentConfig config) => _p.updateConfig(config);

  static Future<int> start({required String magnet, required String path, String? displayName}) =>
      _p.start(magnet: magnet, path: path, displayName: displayName);

  static Future<void> pause(int id) => _p.pause(id);
  static Future<void> resume(int id) => _p.resume(id);
  static Future<void> cancel(int id) => _p.cancel(id);
  static Future<void> finalise(int id) => _p.finalise(id);

  // New management API
  static Future<List<int>> getActiveTorrentIds() => _p.getActiveTorrentIds();
  static Future<bool> exists(int id) => _p.exists(id);
  static Future<TorrentState> getState(int id) => _p.getState(id);
  static Future<TorrentInfo> getTorrentInfo(int id) => _p.getTorrentInfo(id);
  static Future<String> getLastError(int id) => _p.getLastError(id);

  static Stream<TorrentStats> get statsStream => _p.statsStream;
  static Stream<TorrentMetadata> get metadataStream => _p.metadataStream;

  /// Get a stream for a specific torrent
  static Stream<TorrentStats> statsFor(int id) => _p.statsFor(id);
}

// Extension methods for convenience
extension TorrentInfoExtensions on TorrentInfo {
  /// Pause this torrent
  Future<void> pause() => SimpleTorrent.pause(id);

  /// Resume this torrent
  Future<void> resume() => SimpleTorrent.resume(id);

  /// Cancel this torrent
  Future<void> cancel() => SimpleTorrent.cancel(id);

  /// Finish this torrent (remove from session but keep files)
  Future<void> finalise() => SimpleTorrent.finalise(id);

  /// Get a stats stream for this torrent
  Stream<TorrentStats> get statsStream => SimpleTorrent.statsFor(id);

  /// Get the current state of this torrent
  Future<TorrentState> getCurrentState() => SimpleTorrent.getState(id);
}

class SimpleTorrentHelpers {
  /// Start a torrent and get a stream for just this torrent
  static Future<(int id, Stream<TorrentStats> stats)> startAndWatch({
    required String magnet,
    required String path,
    String? displayName,
  }) async {
    final id = await SimpleTorrent.start(magnet: magnet, path: path, displayName: displayName);
    final stream = SimpleTorrent.statsFor(id);
    return (id, stream);
  }

  /// Pause all active torrents
  static Future<void> pauseAll() async {
    final ids = await SimpleTorrent.getActiveTorrentIds();
    await Future.wait(ids.map((id) => SimpleTorrent.pause(id)));
  }

  /// Resume all paused torrents
  static Future<void> resumeAll() async {
    final ids = await SimpleTorrent.getActiveTorrentIds();
    final pausedIds = <int>[];

    for (final id in ids) {
      final state = await SimpleTorrent.getState(id);
      if (state == TorrentState.paused) {
        pausedIds.add(id);
      }
    }

    await Future.wait(pausedIds.map((id) => SimpleTorrent.resume(id)));
  }

  /// Get all torrent info objects
  static Future<List<TorrentInfo>> getAllTorrents() async {
    final ids = await SimpleTorrent.getActiveTorrentIds();
    return Future.wait(ids.map((id) => SimpleTorrent.getTorrentInfo(id)));
  }
}
