import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'simple_torrent_method_channel.dart';

/// Cross‑platform contract.
abstract class SimpleTorrentPlatform extends PlatformInterface {
  SimpleTorrentPlatform() : super(token: _token);
  static final Object _token = Object();

  static SimpleTorrentPlatform _instance = MethodChannelSimpleTorrent();
  static SimpleTorrentPlatform get instance => _instance;

  static set instance(SimpleTorrentPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init({int concurrency = 2});
  Future<String> start({required String magnet, required String path});
  Future<void> pause(String id);
  Future<void> resume(String id);
  Future<void> cancel(String id);
  Stream<TorrentProgress> get progressStream;
}

/// Typed progress payload.
class TorrentProgress {
  final String id;
  final int downloaded;
  final int uploaded;
  final int left;
  final int piecesTotal;
  final int piecesComplete;
  final int piecesRemaining;
  final double progress;

  const TorrentProgress({
    required this.id,
    required this.downloaded,
    required this.uploaded,
    required this.left,
    required this.piecesTotal,
    required this.piecesComplete,
    required this.piecesRemaining,
    required this.progress,
  });

  factory TorrentProgress.fromMap(Map<dynamic, dynamic> m) => TorrentProgress(
    id: m['id'] as String,
    downloaded: m['downloaded'] as int,
    uploaded: m['uploaded'] as int,
    left: m['left'] as int,
    piecesTotal: m['piecesTotal'] as int,
    piecesComplete: m['piecesComplete'] as int,
    piecesRemaining: m['piecesRemaining'] as int,
    progress: (m['progress'] as num).toDouble(),
  );
}
