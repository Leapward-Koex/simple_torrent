import 'package:simple_torrent/simple_torrent.dart';

import 'example_models.dart';

abstract interface class ExampleTorrentService {
  Future<void> initialize();

  Future<void> setTransfersSuspended(bool suspended);
  Future<bool> areTransfersSuspended();

  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  });

  Future<void> pause(int id);
  Future<void> resume(int id);
  Future<void> cancel(int id);
  Future<void> finalise(int id);
  Future<List<int>> getActiveTorrentIds();
  Future<ExampleTorrent> getTorrentInfo(int id);
  Future<String> getLastError(int id);

  Stream<ExampleProgress> get progress;
  Stream<ExampleMetadata> get metadata;
}

/// Thin adapter around the public API. Keeping this outside the widgets makes
/// every UI path deterministic in widget and integration tests.
class SimpleTorrentService implements ExampleTorrentService {
  const SimpleTorrentService();

  @override
  Future<void> initialize() => SimpleTorrent.init(
    config: const TorrentConfig(
      maxTorrents: 5,
      downloadRateLimit: 0,
      uploadRateLimit: 0,
      connectionsLimit: 200,
      enableDht: true,
      userAgent: 'simple_torrent_example/2.0.0',
    ),
  );

  @override
  Future<void> setTransfersSuspended(bool suspended) =>
      SimpleTorrent.setTransfersSuspended(suspended);

  @override
  Future<bool> areTransfersSuspended() => SimpleTorrent.areTransfersSuspended();

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) =>
      SimpleTorrent.start(magnet: magnet, path: path, displayName: displayName);

  @override
  Future<void> pause(int id) => SimpleTorrent.pause(id);

  @override
  Future<void> resume(int id) => SimpleTorrent.resume(id);

  @override
  Future<void> cancel(int id) => SimpleTorrent.cancel(id);

  @override
  Future<void> finalise(int id) => SimpleTorrent.finalise(id);

  @override
  Future<List<int>> getActiveTorrentIds() =>
      SimpleTorrent.getActiveTorrentIds();

  @override
  Future<ExampleTorrent> getTorrentInfo(int id) async {
    final value = await SimpleTorrent.getTorrentInfo(id);
    return ExampleTorrent(
      id: value.id,
      displayName: value.displayName,
      savePath: value.savePath,
      state: value.state.name,
      lastError: value.lastError,
    );
  }

  @override
  Future<String> getLastError(int id) => SimpleTorrent.getLastError(id);

  @override
  Stream<ExampleProgress> get progress => SimpleTorrent.statsStream.map(
    (value) => ExampleProgress(
      id: value.id,
      downloadRate: value.downloadRate,
      uploadRate: value.uploadRate,
      pieces: value.pieces,
      piecesTotal: value.piecesTotal,
      progress: value.progress,
      seeds: value.seeds,
      peers: value.peers,
      state: value.state.name,
    ),
  );

  @override
  Stream<ExampleMetadata> get metadata => SimpleTorrent.metadataStream.map(
    (value) => ExampleMetadata(
      id: value.id,
      name: value.name,
      totalBytes: value.totalBytes,
      pieceSize: value.pieceSize,
      pieceCount: value.pieceCount,
      v1InfoHash: value.v1InfoHash,
      v2InfoHash: value.v2InfoHash,
      files: [
        for (final file in value.files)
          ExampleTorrentFile(
            path: file.path,
            size: file.size,
            offset: file.offset,
          ),
      ],
    ),
  );
}
