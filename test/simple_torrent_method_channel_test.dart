import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

// Mock method channel implementation for testing
class TestMethodChannelSimpleTorrent extends SimpleTorrentPlatform {
  static const MethodChannel _channel = MethodChannel('simple_torrent_test');

  @override
  Future<void> init({TorrentConfig? config}) async {
    await _channel.invokeMethod('init', config?.toMap());
  }

  @override
  Future<void> updateConfig(TorrentConfig config) async {
    await _channel.invokeMethod('updateConfig', config.toMap());
  }

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) async {
    return await _channel.invokeMethod('start', {
      'magnet': magnet,
      'path': path,
      'displayName': displayName,
    });
  }

  @override
  Future<int> startFromTorrentData({
    required Uint8List data,
    required String path,
    String? displayName,
  }) async {
    return await _channel.invokeMethod('startFromTorrentData', {
      'data': data,
      'path': path,
      'displayName': displayName,
    });
  }

  @override
  Future<int> startFromTorrentFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  }) async {
    return await _channel.invokeMethod('startFromTorrentFile', {
      'torrentFilePath': torrentFilePath,
      'path': path,
      'displayName': displayName,
    });
  }

  @override
  Future<void> pause(int id) async {
    await _channel.invokeMethod('pause', {'id': id});
  }

  @override
  Future<void> resume(int id) async {
    await _channel.invokeMethod('resume', {'id': id});
  }

  @override
  Future<void> togglePause(int id) async {
    await _channel.invokeMethod('togglePause', {'id': id});
  }

  @override
  Future<void> cancel(int id) async {
    await _channel.invokeMethod('cancel', {'id': id});
  }

  @override
  Future<void> finalise(int id) async {
    await _channel.invokeMethod('finalise', {'id': id});
  }

  @override
  Future<List<int>> getActiveTorrentIds() async {
    final result = await _channel.invokeMethod('getActiveTorrentIds');
    return List<int>.from(result);
  }

  @override
  Future<bool> exists(int id) async {
    return await _channel.invokeMethod('exists', {'id': id});
  }

  @override
  Future<TorrentState> getState(int id) async {
    final stateString = await _channel.invokeMethod('getState', {'id': id});
    return TorrentStateExtension.fromString(stateString);
  }

  @override
  Future<TorrentInfo> getTorrentInfo(int id) async {
    final result = await _channel.invokeMethod('getTorrentInfo', {'id': id});
    return TorrentInfo.fromMap(result);
  }

  @override
  Future<String> getLastError(int id) async {
    return await _channel.invokeMethod('getLastError', {'id': id});
  }

  @override
  Stream<TorrentStats> get statsStream => const Stream.empty();

  @override
  Stream<TorrentMetadata> get metadataStream => const Stream.empty();

  @override
  Stream<TorrentStats> statsFor(int id) => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestMethodChannelSimpleTorrent platform = TestMethodChannelSimpleTorrent();
  const MethodChannel channel = MethodChannel('simple_torrent_test');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'init':
              return null;
            case 'start':
              return 1;
            case 'getState':
              return 'downloading';
            case 'exists':
              return true;
            case 'getActiveTorrentIds':
              return [1, 2, 3];
            case 'getTorrentInfo':
              return {
                'id': 1,
                'magnetUri': 'magnet:?xt=urn:btih:test',
                'savePath': '/test/downloads',
                'displayName': 'Test Torrent',
                'state': 'downloading',
                'lastError': '',
                'createdAt': DateTime.now().millisecondsSinceEpoch,
              };
            case 'getLastError':
              return 'No error';
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('can initialize platform', () async {
    await platform.init();
    // Should not throw
  });

  test('can start torrent', () async {
    final id = await platform.start(
      magnet: 'magnet:?xt=urn:btih:test',
      path: '/test/downloads',
    );
    expect(id, 1);
  });

  test('can check if torrent exists', () async {
    final exists = await platform.exists(1);
    expect(exists, true);
  });

  test('can get active torrent IDs', () async {
    final ids = await platform.getActiveTorrentIds();
    expect(ids, [1, 2, 3]);
  });

  test('can get torrent state', () async {
    final state = await platform.getState(1);
    expect(state, TorrentState.downloading);
  });

  test('can get torrent info', () async {
    final info = await platform.getTorrentInfo(1);
    expect(info.displayName, 'Test Torrent');
    expect(info.id, 1);
  });

  test('can get last error', () async {
    final error = await platform.getLastError(1);
    expect(error, 'No error');
  });
}
