import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_torrent/simple_torrent.dart';
import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSimpleTorrentPlatform
    with MockPlatformInterfaceMixin
    implements SimpleTorrentPlatform {
  @override
  Future<void> init({TorrentConfig? config}) => Future.value();

  @override
  Future<void> updateConfig(TorrentConfig config) => Future.value();

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) => Future.value(1);

  @override
  Future<int> startFromTorrentData({
    required Uint8List data,
    required String path,
    String? displayName,
  }) => Future.value(2);

  @override
  Future<int> startFromTorrentFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  }) => Future.value(3);

  @override
  Future<void> pause(int id) => Future.value();

  @override
  Future<void> resume(int id) => Future.value();

  @override
  Future<void> togglePause(int id) => Future.value();

  @override
  Future<void> cancel(int id) => Future.value();

  @override
  Future<void> finalise(int id) => Future.value();

  @override
  Future<List<int>> getActiveTorrentIds() => Future.value([1, 2, 3]);

  @override
  Future<bool> exists(int id) => Future.value(true);

  @override
  Future<TorrentState> getState(int id) =>
      Future.value(TorrentState.downloading);

  @override
  Future<TorrentInfo> getTorrentInfo(int id) => Future.value(
    TorrentInfo(
      id: id,
      magnetUri: 'magnet:?xt=urn:btih:test',
      savePath: '/test/downloads',
      displayName: 'Test Torrent',
      state: TorrentState.downloading,
      lastError: '',
      createdAt: DateTime.now(),
    ),
  );

  @override
  Future<String> getLastError(int id) => Future.value('No error');

  @override
  Stream<TorrentStats> get statsStream => Stream.value(
    TorrentStats(
      id: 1,
      downloadRate: 1024,
      uploadRate: 512,
      pieces: 50,
      piecesTotal: 100,
      progress: 0.5,
      seeds: 2,
      peers: 5,
      state: TorrentState.downloading,
    ),
  );

  @override
  Stream<TorrentMetadata> get metadataStream => Stream.value(
    TorrentMetadata(
      id: 1,
      name: 'Test Torrent',
      totalBytes: 1024 * 1024,
      pieceSize: 16384,
      pieceCount: 64,
      fileCount: 1,
      creationDate: DateTime.now().millisecondsSinceEpoch,
      isPrivate: false,
      isV2: false,
    ),
  );

  @override
  Stream<TorrentStats> statsFor(int id) => Stream.value(
    TorrentStats(
      id: id,
      downloadRate: 1024,
      uploadRate: 512,
      pieces: 50,
      piecesTotal: 100,
      progress: 0.5,
      seeds: 2,
      peers: 5,
      state: TorrentState.downloading,
    ),
  );
}

void main() {
  final SimpleTorrentPlatform initialPlatform = SimpleTorrentPlatform.instance;

  test('uses correct platform interface', () {
    expect(initialPlatform, isInstanceOf<SimpleTorrentPlatform>());
  });

  test('can start torrent with magnet link', () async {
    MockSimpleTorrentPlatform fakePlatform = MockSimpleTorrentPlatform();
    SimpleTorrentPlatform.instance = fakePlatform;

    final id = await SimpleTorrent.start(
      magnet: 'magnet:?xt=urn:btih:test',
      path: '/test/downloads',
    );

    expect(id, 1);
  });

  test('can configure with all torrent settings', () async {
    MockSimpleTorrentPlatform fakePlatform = MockSimpleTorrentPlatform();
    SimpleTorrentPlatform.instance = fakePlatform;

    // Test that all config parameters can be set without error
    const config = TorrentConfig(
      maxTorrents: 10,
      maxDownloadRate: 2048 * 1024,
      maxUploadRate: 1024 * 1024,
      enableDHT: true,
      userAgent: 'TestAgent/1.0',
      downloadLimit: 1024 * 1024,
      uploadLimit: 512 * 1024,
      connections: 100,
      downloadPath: '/test/downloads',
      autoManaged: true,
      sequentialDownload: false,
    );

    // Should not throw any exception
    await SimpleTorrent.init(config: config);
    await SimpleTorrent.updateConfig(config);
  });

  test('can get active torrent IDs', () async {
    MockSimpleTorrentPlatform fakePlatform = MockSimpleTorrentPlatform();
    SimpleTorrentPlatform.instance = fakePlatform;

    final ids = await SimpleTorrent.getActiveTorrentIds();
    expect(ids, [1, 2, 3]);
  });

  test('can get torrent info', () async {
    MockSimpleTorrentPlatform fakePlatform = MockSimpleTorrentPlatform();
    SimpleTorrentPlatform.instance = fakePlatform;

    final info = await SimpleTorrent.getTorrentInfo(1);
    expect(info.displayName, 'Test Torrent');
    expect(info.state, TorrentState.downloading);
  });
}
