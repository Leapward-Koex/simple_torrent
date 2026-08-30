import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_torrent/simple_torrent.dart';
import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

class FakeSimpleTorrentPlatform extends SimpleTorrentPlatform {
  TorrentConfig? initializedConfig;
  TorrentConfig? updatedConfig;
  String? method;
  Map<String, Object?>? arguments;
  final paused = <int>[];
  final resumed = <int>[];

  @override
  Future<void> init({TorrentConfig? config}) async {
    initializedConfig = config;
  }

  @override
  Future<void> updateConfig(TorrentConfig config) async {
    updatedConfig = config;
  }

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) async {
    method = 'start';
    arguments = <String, Object?>{
      'magnet': magnet,
      'path': path,
      'displayName': displayName,
    };
    return 1;
  }

  @override
  Future<int> startFromData({
    required Uint8List data,
    required String path,
    String? displayName,
  }) async {
    method = 'startFromData';
    arguments = <String, Object?>{
      'data': data,
      'path': path,
      'displayName': displayName,
    };
    return 2;
  }

  @override
  Future<int> startFromFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  }) async {
    method = 'startFromFile';
    arguments = <String, Object?>{
      'torrentFilePath': torrentFilePath,
      'path': path,
      'displayName': displayName,
    };
    return 3;
  }

  @override
  Future<void> pause(int id) async {
    paused.add(id);
  }

  @override
  Future<void> resume(int id) async {
    resumed.add(id);
  }

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> finalise(int id) async {}

  @override
  Future<List<int>> getActiveTorrentIds() async => <int>[1, 2];

  @override
  Future<bool> exists(int id) async => id == 1;

  @override
  Future<TorrentState> getState(int id) async =>
      id == 1 ? TorrentState.paused : TorrentState.downloading;

  @override
  Future<TorrentInfo> getTorrentInfo(int id) async => TorrentInfo(
    id: id,
    magnetUri: 'magnet:?xt=urn:btih:test',
    savePath: 'downloads',
    displayName: 'Test torrent',
    state: TorrentState.downloading,
    lastError: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  @override
  Future<String> getLastError(int id) async => '';

  @override
  Stream<TorrentStats> get statsStream => Stream<TorrentStats>.value(
    const TorrentStats(
      id: 1,
      downloadRate: 1024,
      uploadRate: 512,
      pieces: 4,
      piecesTotal: 8,
      progress: 0.5,
      seeds: 2,
      peers: 3,
      state: TorrentState.downloading,
    ),
  );

  @override
  Stream<TorrentMetadata> get metadataStream => Stream<TorrentMetadata>.value(
    const TorrentMetadata(
      id: 1,
      name: 'Test torrent',
      totalBytes: 64,
      pieceSize: 16,
      pieceCount: 4,
      fileCount: 1,
      creationDate: 0,
      isPrivate: false,
      v1InfoHash: '0123456789012345678901234567890123456789',
      files: <TorrentFile>[
        TorrentFile(index: 0, path: 'file.txt', size: 64, offset: 0),
      ],
    ),
  );
}

class SuspensionFakeSimpleTorrentPlatform extends FakeSimpleTorrentPlatform {
  final suspensionUpdates = <bool>[];
  bool transfersSuspended = false;

  @override
  Future<void> setTransfersSuspended(bool suspended) async {
    suspensionUpdates.add(suspended);
    transfersSuspended = suspended;
  }

  @override
  Future<bool> areTransfersSuspended() async => transfersSuspended;
}

void main() {
  late SuspensionFakeSimpleTorrentPlatform platform;

  setUp(() {
    platform = SuspensionFakeSimpleTorrentPlatform();
    SimpleTorrentPlatform.instance = platform;
  });

  test('configuration exposes implemented settings with non-null defaults', () {
    const config = TorrentConfig();

    expect(config.maxTorrents, 20);
    expect(config.downloadRateLimit, 0);
    expect(config.uploadRateLimit, 0);
    expect(config.connectionsLimit, 200);
    expect(config.enableDht, isTrue);
    expect(config.userAgent, 'simple_torrent/2.0.0');
  });

  test('static facade delegates every start source', () async {
    expect(
      await SimpleTorrent.start(magnet: 'magnet:test', path: 'downloads'),
      1,
    );
    expect(platform.method, 'start');

    expect(
      await SimpleTorrent.startFromData(
        data: Uint8List.fromList(<int>[1, 2]),
        downloadPath: 'downloads',
      ),
      2,
    );
    expect(platform.method, 'startFromData');

    expect(
      await SimpleTorrent.startFromTorrentFile(
        torrentFilePath: 'sample.torrent',
        downloadPath: 'downloads',
      ),
      3,
    );
    expect(platform.method, 'startFromFile');
  });

  test('configuration and management helpers delegate', () async {
    const config = TorrentConfig(connectionsLimit: 50, enableDht: false);
    await SimpleTorrent.init(config: config);
    await SimpleTorrent.updateConfig(config);
    await SimpleTorrentHelpers.pauseAll();
    await SimpleTorrentHelpers.resumeAll();

    expect(platform.initializedConfig, same(config));
    expect(platform.updatedConfig, same(config));
    expect(platform.paused, <int>[1, 2]);
    expect(platform.resumed, <int>[1]);
  });

  test(
    'session transfer suspension delegates independently of helpers',
    () async {
      await SimpleTorrent.setTransfersSuspended(true);
      await SimpleTorrent.setTransfersSuspended(true);

      expect(await SimpleTorrent.areTransfersSuspended(), isTrue);
      expect(platform.suspensionUpdates, <bool>[true, true]);
      expect(platform.paused, isEmpty);
      expect(platform.resumed, isEmpty);

      await SimpleTorrent.setTransfersSuspended(false);
      expect(await SimpleTorrent.areTransfersSuspended(), isFalse);
      expect(platform.suspensionUpdates, <bool>[true, true, false]);
    },
  );

  test(
    'legacy platform implementations report suspension as unavailable',
    () async {
      final legacyPlatform = FakeSimpleTorrentPlatform();
      final unavailable = isA<SimpleTorrentException>().having(
        (error) => error.code,
        'code',
        SimpleTorrentErrorCode.unavailable,
      );

      await expectLater(
        legacyPlatform.setTransfersSuspended(true),
        throwsA(unavailable),
      );
      await expectLater(
        legacyPlatform.areTransfersSuspended(),
        throwsA(unavailable),
      );
    },
  );

  test('metadata exposes info hashes and payload files', () async {
    final metadata = await SimpleTorrent.metadataStream.first;

    expect(metadata.isV1, isTrue);
    expect(metadata.isV2, isFalse);
    expect(metadata.files.single.path, 'file.txt');
    expect(
      metadata.files.fold<int>(0, (sum, file) => sum + file.size),
      metadata.totalBytes,
    );
  });
}
