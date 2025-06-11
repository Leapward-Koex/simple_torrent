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

  /// Stream of [TorrentMetadata] for *all* torrents.
  Stream<TorrentMetadata> get metadataStream;
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

class TorrentMetadata {
  final int id;
  final String name; // bytes/s
  final int totalBytes; // bytes/s
  final int pieceSize;
  final int pieceCount;
  final int fileCount; // 0-100
  final int creationDate;
  final bool isPrivate;
  final bool isV2;

  const TorrentMetadata({
    required this.id,
    required this.name,
    required this.totalBytes,
    required this.pieceSize,
    required this.pieceCount,
    required this.fileCount,
    required this.creationDate,
    required this.isPrivate,
    required this.isV2,
  });

  factory TorrentMetadata.fromMap(Map<dynamic, dynamic> m) => TorrentMetadata(
    id: m['id'] as int,
    name: m['name'] as String,
    totalBytes: m['total_bytes'] as int,
    pieceSize: m['piece_size'] as int,
    pieceCount: m['piece_count'] as int,
    fileCount: m['file_count'] as int,
    creationDate: m['creation_date'] as int,
    isPrivate: m['private'] as bool,
    isV2: m['v2'] as bool,
  );
}
