import 'dart:collection';

/// The public WIRED torrent used by the release integration test.
const wiredMagnet =
    'magnet:?xt=urn:btih:a88fda5954e89178c372716a6a78b8180ed4dad3&dn=The+WIRED+CD+-+Rip.+Sample.+Mash.+Share&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fwired-cd.torrent';

const wiredV1InfoHash = 'a88fda5954e89178c372716a6a78b8180ed4dad3';
const wiredTorrentName = 'The WIRED CD - Rip. Sample. Mash. Share';

enum ExampleInitializationState { idle, initializing, ready, failed }

class ExampleTorrent {
  const ExampleTorrent({
    required this.id,
    required this.displayName,
    required this.savePath,
    required this.state,
    this.lastError = '',
  });

  final int id;
  final String displayName;
  final String savePath;
  final String state;
  final String lastError;

  ExampleTorrent copyWith({
    String? displayName,
    String? state,
    String? lastError,
  }) => ExampleTorrent(
    id: id,
    displayName: displayName ?? this.displayName,
    savePath: savePath,
    state: state ?? this.state,
    lastError: lastError ?? this.lastError,
  );
}

class ExampleProgress {
  const ExampleProgress({
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

  final int id;
  final int downloadRate;
  final int uploadRate;
  final int pieces;
  final int piecesTotal;
  final double progress;
  final int seeds;
  final int peers;
  final String state;

  ExampleProgress copyWith({String? state}) => ExampleProgress(
    id: id,
    downloadRate: downloadRate,
    uploadRate: uploadRate,
    pieces: pieces,
    piecesTotal: piecesTotal,
    progress: progress,
    seeds: seeds,
    peers: peers,
    state: state ?? this.state,
  );
}

class ExampleTorrentFile {
  const ExampleTorrentFile({
    required this.path,
    required this.size,
    required this.offset,
  });

  final String path;
  final int size;
  final int offset;
}

class ExampleMetadata {
  const ExampleMetadata({
    required this.id,
    required this.name,
    required this.totalBytes,
    required this.pieceSize,
    required this.pieceCount,
    required this.files,
    this.v1InfoHash,
    this.v2InfoHash,
  });

  final int id;
  final String name;
  final int totalBytes;
  final int pieceSize;
  final int pieceCount;
  final List<ExampleTorrentFile> files;
  final String? v1InfoHash;
  final String? v2InfoHash;
}

UnmodifiableMapView<int, T> immutableView<T>(Map<int, T> source) =>
    UnmodifiableMapView(source);
