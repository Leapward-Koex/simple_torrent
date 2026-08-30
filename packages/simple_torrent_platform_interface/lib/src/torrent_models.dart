/// Lifecycle state reported by the native torrent manager.
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
  static TorrentState fromString(String value) => switch (value) {
    'starting' => TorrentState.starting,
    'downloadingMetadata' => TorrentState.downloadingMetadata,
    'downloading' => TorrentState.downloading,
    'seeding' => TorrentState.seeding,
    'paused' => TorrentState.paused,
    'stopped' => TorrentState.stopped,
    _ => TorrentState.error,
  };
}

/// A payload file described by torrent metadata.
class TorrentFile {
  const TorrentFile({
    required this.index,
    required this.path,
    required this.size,
    required this.offset,
  });

  factory TorrentFile.fromMap(Map<dynamic, dynamic> map) => TorrentFile(
    index: _requiredInt(map, 'index'),
    path: _requiredString(map, 'path'),
    size: _requiredInt(map, 'size'),
    offset: _requiredInt(map, 'offset'),
  );

  final int index;
  final String path;
  final int size;
  final int offset;

  Map<String, Object> toMap() => <String, Object>{
    'index': index,
    'path': path,
    'size': size,
    'offset': offset,
  };
}

/// Real-time progress for one torrent.
class TorrentStats {
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

  factory TorrentStats.fromMap(Map<dynamic, dynamic> map) => TorrentStats(
    id: _requiredInt(map, 'id'),
    downloadRate: _requiredInt(map, 'download_rate'),
    uploadRate: _requiredInt(map, 'upload_rate'),
    pieces: _requiredInt(map, 'pieces'),
    piecesTotal: _requiredInt(map, 'pieces_total'),
    progress: _requiredNum(map, 'progress').toDouble(),
    seeds: _requiredInt(map, 'seeds'),
    peers: _requiredInt(map, 'peers'),
    state: TorrentStateExtension.fromString(_requiredString(map, 'state')),
  );

  final int id;
  final int downloadRate;
  final int uploadRate;
  final int pieces;
  final int piecesTotal;
  final double progress;
  final int seeds;
  final int peers;
  final TorrentState state;

  /// Backwards-compatible shorthand for [downloadRate].
  int get dlRate => downloadRate;

  /// Backwards-compatible shorthand for [uploadRate].
  int get ulRate => uploadRate;

  /// The number of pieces libtorrent has checked and accepted.
  int get verifiedPieces => pieces;

  Map<String, Object> toMap() => <String, Object>{
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

/// Static metadata received after libtorrent resolves a torrent.
class TorrentMetadata {
  const TorrentMetadata({
    required this.id,
    required this.name,
    required this.totalBytes,
    required this.pieceSize,
    required this.pieceCount,
    required this.fileCount,
    required this.creationDate,
    required this.isPrivate,
    this.v1InfoHash,
    this.v2InfoHash,
    this.files = const <TorrentFile>[],
  });

  factory TorrentMetadata.fromMap(Map<dynamic, dynamic> map) {
    final rawFiles = map['files'];
    final files = rawFiles is List
        ? rawFiles
              .whereType<Map>()
              .map((file) => TorrentFile.fromMap(file))
              .toList(growable: false)
        : const <TorrentFile>[];

    return TorrentMetadata(
      id: _requiredInt(map, 'id'),
      name: _requiredString(map, 'name'),
      totalBytes: _requiredInt(map, 'total_bytes'),
      pieceSize: _requiredInt(map, 'piece_size'),
      pieceCount: _requiredInt(map, 'piece_count'),
      fileCount: _requiredInt(map, 'file_count'),
      creationDate: _requiredInt(map, 'creation_date'),
      isPrivate: map['private'] as bool? ?? false,
      v1InfoHash: _optionalString(map['v1_info_hash']),
      v2InfoHash: _optionalString(map['v2_info_hash']),
      files: files,
    );
  }

  final int id;
  final String name;
  final int totalBytes;
  final int pieceSize;
  final int pieceCount;
  final int fileCount;
  final int creationDate;
  final bool isPrivate;
  final String? v1InfoHash;
  final String? v2InfoHash;
  final List<TorrentFile> files;

  bool get isV1 => v1InfoHash != null;
  bool get isV2 => v2InfoHash != null;
  bool get isHybrid => isV1 && isV2;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'total_bytes': totalBytes,
    'piece_size': pieceSize,
    'piece_count': pieceCount,
    'file_count': fileCount,
    'creation_date': creationDate,
    'private': isPrivate,
    'v1_info_hash': v1InfoHash,
    'v2_info_hash': v2InfoHash,
    'files': files.map((file) => file.toMap()).toList(growable: false),
  };
}

/// Current manager information for a torrent.
class TorrentInfo {
  const TorrentInfo({
    required this.id,
    required this.magnetUri,
    required this.savePath,
    required this.displayName,
    required this.state,
    required this.lastError,
    required this.createdAt,
  });

  factory TorrentInfo.fromMap(Map<dynamic, dynamic> map) => TorrentInfo(
    id: _requiredInt(map, 'id'),
    magnetUri: _requiredString(map, 'magnetUri'),
    savePath: _requiredString(map, 'savePath'),
    displayName: _requiredString(map, 'displayName'),
    state: TorrentStateExtension.fromString(_requiredString(map, 'state')),
    lastError: _requiredString(map, 'lastError'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      _requiredInt(map, 'createdAt'),
    ),
  );

  final int id;
  final String magnetUri;
  final String savePath;
  final String displayName;
  final TorrentState state;
  final String lastError;
  final DateTime createdAt;

  Map<String, Object> toMap() => <String, Object>{
    'id': id,
    'magnetUri': magnetUri,
    'savePath': savePath,
    'displayName': displayName,
    'state': state.name,
    'lastError': lastError,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}

int _requiredInt(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected integer value for "$key".');
}

num _requiredNum(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is num) {
    return value;
  }
  throw FormatException('Expected numeric value for "$key".');
}

String _requiredString(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string value for "$key".');
}

String? _optionalString(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return value.toLowerCase();
}
