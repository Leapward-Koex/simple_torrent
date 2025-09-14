import 'dart:typed_data';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

enum TorrentState {
  starting,
  downloadingMetadata,
  downloading,
  seeding,
  paused,
  error,
  stopped,
}

extension TorrentStateExtension on TorrentState {
  static TorrentState fromString(String value) {
    switch (value) {
      case 'starting':
        return TorrentState.starting;
      case 'downloadingMetadata':
        return TorrentState.downloadingMetadata;
      case 'downloading':
        return TorrentState.downloading;
      case 'seeding':
        return TorrentState.seeding;
      case 'paused':
        return TorrentState.paused;
      case 'error':
        return TorrentState.error;
      case 'stopped':
        return TorrentState.stopped;
      default:
        return TorrentState.error;
    }
  }

  String get name {
    switch (this) {
      case TorrentState.starting:
        return 'starting';
      case TorrentState.downloadingMetadata:
        return 'downloadingMetadata';
      case TorrentState.downloading:
        return 'downloading';
      case TorrentState.seeding:
        return 'seeding';
      case TorrentState.paused:
        return 'paused';
      case TorrentState.error:
        return 'error';
      case TorrentState.stopped:
        return 'stopped';
    }
  }
}

/// Strongly-typed torrent configuration
class TorrentConfig {
  final int? maxTorrents;
  final int? maxDownloadRate;
  final int? maxUploadRate;
  final bool? enableDHT;
  final String? userAgent;
  final int? downloadLimit;
  final int? uploadLimit;
  final int? connections;
  final String? downloadPath;
  final bool? autoManaged;
  final bool? sequentialDownload;

  const TorrentConfig({
    this.maxTorrents,
    this.maxDownloadRate,
    this.maxUploadRate,
    this.enableDHT,
    this.userAgent,
    this.downloadLimit,
    this.uploadLimit,
    this.connections,
    this.downloadPath,
    this.autoManaged,
    this.sequentialDownload,
  });

  factory TorrentConfig.fromMap(Map<dynamic, dynamic> map) {
    return TorrentConfig(
      maxTorrents: map['maxTorrents'] as int?,
      maxDownloadRate: map['maxDownloadRate'] as int?,
      maxUploadRate: map['maxUploadRate'] as int?,
      enableDHT: map['enableDHT'] as bool?,
      userAgent: map['userAgent'] as String?,
      downloadLimit: map['downloadLimit'] as int?,
      uploadLimit: map['uploadLimit'] as int?,
      connections: map['connections'] as int?,
      downloadPath: map['downloadPath'] as String?,
      autoManaged: map['autoManaged'] as bool?,
      sequentialDownload: map['sequentialDownload'] as bool?,
    );
  }

  /// Convert torrent config to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'maxTorrents': maxTorrents,
      'maxDownloadRate': maxDownloadRate,
      'maxUploadRate': maxUploadRate,
      'enableDHT': enableDHT,
      'userAgent': userAgent,
      'downloadLimit': downloadLimit,
      'uploadLimit': uploadLimit,
      'connections': connections,
      'downloadPath': downloadPath,
      'autoManaged': autoManaged,
      'sequentialDownload': sequentialDownload,
    };
  }
}

/// Torrent information
class TorrentInfo {
  final int id;
  final String magnetUri;
  final String savePath;
  final String displayName;
  final TorrentState state;
  final String lastError;
  final DateTime createdAt;

  const TorrentInfo({
    required this.id,
    required this.magnetUri,
    required this.savePath,
    required this.displayName,
    required this.state,
    required this.lastError,
    required this.createdAt,
  });

  factory TorrentInfo.fromMap(Map<dynamic, dynamic> map) {
    return TorrentInfo(
      id: map['id'] as int,
      magnetUri: map['magnetUri'] as String,
      savePath: map['savePath'] as String,
      displayName: map['displayName'] as String,
      state: TorrentStateExtension.fromString(map['state'] as String),
      lastError: map['lastError'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
    );
  }

  /// Convert torrent info to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'magnetUri': magnetUri,
      'savePath': savePath,
      'displayName': displayName,
      'state': state.name,
      'lastError': lastError,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }
}

/// Cross-platform contract.
abstract class SimpleTorrentPlatform extends PlatformInterface {
  SimpleTorrentPlatform() : super(token: _token);
  static final Object _token = Object();

  static SimpleTorrentPlatform? _instance;

  /// The default instance of [SimpleTorrentPlatform] to use.
  ///
  /// Defaults to a test implementation if no platform-specific implementation has been set.
  static SimpleTorrentPlatform get instance =>
      _instance ?? _TestTorrentPlatform();

  /// Platform-specific implementations should set this with their own platform-specific class
  /// that extends [SimpleTorrentPlatform] when they register themselves.
  static set instance(SimpleTorrentPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init({TorrentConfig? config});
  Future<void> updateConfig(TorrentConfig config);
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  });

  /// Start a torrent from .torrent file data
  Future<int> startFromTorrentData({
    required Uint8List data,
    required String path,
    String? displayName,
  });

  /// Start a torrent from a .torrent file on disk
  Future<int> startFromTorrentFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  });

  Future<void> pause(int id);
  Future<void> resume(int id);

  /// Toggle pause/resume based on current state
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

  /// Torrent queries
  Future<List<int>> getActiveTorrentIds();
  Future<bool> exists(int id);
  Future<TorrentState> getState(int id);
  Future<TorrentInfo> getTorrentInfo(int id);
  Future<String> getLastError(int id);

  /// Stream APIs for real-time updates
  Stream<TorrentStats> get statsStream;
  Stream<TorrentMetadata> get metadataStream;

  /// Get a stream for a specific torrent
  Stream<TorrentStats> statsFor(int id) {
    return statsStream.where((stats) => stats.id == id);
  }
}

/// Strongly-typed progress payload.
class TorrentStats {
  final int id;
  final int downloadRate; // bytes/s
  final int uploadRate; // bytes/s
  final int pieces;
  final int piecesTotal;
  final double progress; // 0.0-1.0
  final int seeds;
  final int peers;
  final TorrentState state;

  const TorrentStats({
    required this.id,
    required this.downloadRate,
    required this.uploadRate,
    required this.pieces,
    required this.piecesTotal,
    required this.progress,
    required this.seeds,
    required this.peers,
    required this.state,
  });

  // Convenience getters for backward compatibility
  int get dlRate => downloadRate;
  int get ulRate => uploadRate;

  factory TorrentStats.fromMap(Map<dynamic, dynamic> m) => TorrentStats(
    id: m['id'] as int,
    downloadRate: m['download_rate'] as int,
    uploadRate: m['upload_rate'] as int,
    pieces: m['pieces'] as int,
    piecesTotal: m['pieces_total'] as int,
    progress: (m['progress'] as num).toDouble(),
    seeds: m['seeds'] as int,
    peers: m['peers'] as int,
    state: TorrentStateExtension.fromString(m['state'] as String),
  );

  /// Convert stats to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'download_rate': downloadRate,
      'upload_rate': uploadRate,
      'pieces': pieces,
      'pieces_total': piecesTotal,
      'progress': progress,
      'seeds': seeds,
      'peers': peers,
      'state': state.name,
    };
  }
}

class TorrentMetadata {
  final int id;
  final String name;
  final int totalBytes;
  final int pieceSize;
  final int pieceCount;
  final int fileCount;
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

  /// Convert metadata to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'total_bytes': totalBytes,
      'piece_size': pieceSize,
      'piece_count': pieceCount,
      'file_count': fileCount,
      'creation_date': creationDate,
      'private': isPrivate,
      'v2': isV2,
    };
  }
}

/// Test implementation of [SimpleTorrentPlatform] that throws for all methods.
class _TestTorrentPlatform extends SimpleTorrentPlatform {
  @override
  Future<void> init({TorrentConfig? config}) async {
    throw UnimplementedError('init() has not been implemented.');
  }

  @override
  Future<void> updateConfig(TorrentConfig config) async {
    throw UnimplementedError('updateConfig() has not been implemented.');
  }

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) async {
    throw UnimplementedError('start() has not been implemented.');
  }

  @override
  Future<int> startFromTorrentData({
    required Uint8List data,
    required String path,
    String? displayName,
  }) async {
    throw UnimplementedError(
      'startFromTorrentData() has not been implemented.',
    );
  }

  @override
  Future<int> startFromTorrentFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  }) async {
    throw UnimplementedError(
      'startFromTorrentFile() has not been implemented.',
    );
  }

  @override
  Future<void> pause(int id) async {
    throw UnimplementedError('pause() has not been implemented.');
  }

  @override
  Future<void> resume(int id) async {
    throw UnimplementedError('resume() has not been implemented.');
  }

  @override
  Future<void> cancel(int id) async {
    throw UnimplementedError('cancel() has not been implemented.');
  }

  @override
  Future<void> finalise(int id) async {
    throw UnimplementedError('finalise() has not been implemented.');
  }

  @override
  Future<List<int>> getActiveTorrentIds() async {
    throw UnimplementedError('getActiveTorrentIds() has not been implemented.');
  }

  @override
  Future<bool> exists(int id) async {
    throw UnimplementedError('exists() has not been implemented.');
  }

  @override
  Future<TorrentState> getState(int id) async {
    throw UnimplementedError('getState() has not been implemented.');
  }

  @override
  Future<TorrentInfo> getTorrentInfo(int id) async {
    throw UnimplementedError('getTorrentInfo() has not been implemented.');
  }

  @override
  Future<String> getLastError(int id) async {
    throw UnimplementedError('getLastError() has not been implemented.');
  }

  @override
  Stream<TorrentStats> get statsStream => const Stream.empty();

  @override
  Stream<TorrentMetadata> get metadataStream => const Stream.empty();
}
