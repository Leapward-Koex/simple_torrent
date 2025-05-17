import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'simple_torrent_method_channel.dart';

/// Cross-platform contract.
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
  Future<int> start({required String magnet, required String path});
  Future<void> pause(int id);
  Future<void> resume(int id);
  Future<void> cancel(int id);

  /// Stream of [TorrentStats] for *all* torrents.
  Stream<TorrentStats> get statsStream;
}

/// Strongly-typed progress payload.
class TorrentStats {
  final int id;
  final int downloadRate; // bytes/s
  final int uploadRate; // bytes/s
  final int pieces;
  final int piecesTotal;
  final int progress; // 0-100
  final int seeds;
  final int peers;

  const TorrentStats({
    required this.id,
    required this.downloadRate,
    required this.uploadRate,
    required this.pieces,
    required this.piecesTotal,
    required this.progress,
    required this.seeds,
    required this.peers,
  });

  factory TorrentStats.fromMap(Map<dynamic, dynamic> m) => TorrentStats(
    id: m['id'] as int,
    downloadRate: m['download_rate'] as int,
    uploadRate: m['upload_rate'] as int,
    pieces: m['pieces'] as int,
    piecesTotal: m['pieces_total'] as int,
    progress: m['progress'] as int,
    seeds: m['seeds'] as int,
    peers: m['peers'] as int,
  );
}
