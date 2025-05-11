library;

export 'simple_torrent_platform_interface.dart' show TorrentProgress;

import 'simple_torrent_platform_interface.dart';

/// Public API used by Flutter apps.
class SimpleTorrent {
  const SimpleTorrent._();

  static final _p = SimpleTorrentPlatform.instance;

  static Future<void> init({int concurrency = 2}) => _p.init(concurrency: concurrency);

  static Future<String> start({required String magnet, required String path}) => _p.start(magnet: magnet, path: path);

  static Future<void> pause(String id) => _p.pause(id);
  static Future<void> resume(String id) => _p.resume(id);
  static Future<void> cancel(String id) => _p.cancel(id);

  static Stream<TorrentProgress> get progressStream => _p.progressStream;
}
