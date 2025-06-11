library;

export 'simple_torrent_platform_interface.dart' show TorrentStats;

import 'simple_torrent_platform_interface.dart';

/// Public API used by Flutter apps.
class SimpleTorrent {
  const SimpleTorrent._();

  static final _p = SimpleTorrentPlatform.instance;

  static Future<void> init({int concurrency = 2}) => _p.init(concurrency: concurrency);

  static Future<int> start({required String magnet, required String path}) => _p.start(magnet: magnet, path: path);

  static Future<void> pause(int id) => _p.pause(id);
  static Future<void> resume(int id) => _p.resume(id);
  static Future<void> cancel(int id) => _p.cancel(id);

  static Stream<TorrentStats> get statsStream => _p.statsStream;
  static Stream<TorrentMetadata> get metadataStream => _p.metadataStream;
}
