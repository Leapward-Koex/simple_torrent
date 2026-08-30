import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('simple_torrent/test/methods');
  late MethodChannelSimpleTorrent platform;
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    platform = MethodChannelSimpleTorrent(methods: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'start' => 1,
            'startFromData' => 2,
            'startFromFile' => 3,
            'areTransfersSuspended' => true,
            'getActiveTorrentIds' => <int>[1, 2],
            'exists' => true,
            'getState' => 'seeding',
            'getTorrentInfo' => <String, Object>{
              'id': 1,
              'magnetUri': 'magnet:test',
              'savePath': 'downloads',
              'displayName': 'Torrent',
              'state': 'downloading',
              'lastError': '',
              'createdAt': 1000,
            },
            'getLastError' => '',
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the v2 method names and argument keys', () async {
    const config = TorrentConfig(connectionsLimit: 50);
    await platform.init(config: config);
    await platform.updateConfig(config);
    await platform.start(
      magnet: 'magnet:test',
      path: 'downloads',
      displayName: 'Magnet',
    );
    await platform.startFromData(
      data: Uint8List.fromList(<int>[1, 2]),
      path: 'downloads',
    );
    await platform.startFromFile(
      torrentFilePath: 'sample.torrent',
      path: 'downloads',
    );

    expect(calls.map((call) => call.method), <String>[
      'init',
      'updateConfig',
      'start',
      'startFromData',
      'startFromFile',
    ]);
    expect(calls[0].arguments, <String, Object>{'config': config.toMap()});
    expect(calls[1].arguments, <String, Object>{'config': config.toMap()});
    expect(calls[2].arguments, <String, Object>{
      'magnet': 'magnet:test',
      'destination': 'downloads',
      'displayName': 'Magnet',
    });
    expect((calls[3].arguments as Map<Object?, Object?>).keys, <String>{
      'data',
      'destination',
    });
    expect(calls[4].arguments, <String, Object>{
      'torrentFilePath': 'sample.torrent',
      'destination': 'downloads',
    });
  });

  test('decodes management query responses', () async {
    expect(await platform.areTransfersSuspended(), isTrue);
    expect(await platform.getActiveTorrentIds(), <int>[1, 2]);
    expect(await platform.exists(1), isTrue);
    expect(await platform.getState(1), TorrentState.seeding);
    expect((await platform.getTorrentInfo(1)).displayName, 'Torrent');
    expect(await platform.getLastError(1), isEmpty);
  });

  test('uses the session transfer suspension wire contract', () async {
    await platform.setTransfersSuspended(true);
    expect(await platform.areTransfersSuspended(), isTrue);

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setTransfersSuspended');
    expect(calls[0].arguments, <String, Object>{'suspended': true});
    expect(calls[1].method, 'areTransfersSuspended');
    expect(calls[1].arguments, isNull);
  });

  test('accepts both strict Boolean suspension responses', () async {
    final responses = <bool>[true, false].iterator;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'areTransfersSuspended');
          expect(responses.moveNext(), isTrue);
          return responses.current;
        });

    expect(await platform.areTransfersSuspended(), isTrue);
    expect(await platform.areTransfersSuspended(), isFalse);
  });

  test('rejects every non-Boolean suspension response', () async {
    for (final response in <Object?>[null, 0, 1, 'false']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => response);

      await expectLater(
        platform.areTransfersSuspended(),
        throwsA(
          isA<SimpleTorrentException>().having(
            (error) => error.code,
            'code',
            SimpleTorrentErrorCode.invalidResponse,
          ),
        ),
        reason: 'The getter accepted ${response.runtimeType}: $response',
      );
    }
  });

  test('preserves typed suspension errors from the native adapter', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'native_error',
            message: 'Session pause failed.',
            details: <String, Object>{'method': call.method},
          );
        });

    for (final operation in <Future<Object?> Function()>[
      () => platform.setTransfersSuspended(true),
      platform.areTransfersSuspended,
    ]) {
      await expectLater(
        operation(),
        throwsA(
          isA<SimpleTorrentException>()
              .having(
                (error) => error.code,
                'code',
                SimpleTorrentErrorCode.nativeError,
              )
              .having(
                (error) => error.details,
                'details',
                isA<Map<Object?, Object?>>(),
              ),
        ),
      );
    }
  });

  test('converts suspension operation timeouts into typed timeouts', () async {
    platform = MethodChannelSimpleTorrent(
      methods: channel,
      methodTimeout: const Duration(milliseconds: 1),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          return false;
        });

    for (final operation in <Future<Object?> Function()>[
      () => platform.setTransfersSuspended(true),
      platform.areTransfersSuspended,
    ]) {
      await expectLater(
        operation(),
        throwsA(
          isA<SimpleTorrentException>().having(
            (error) => error.code,
            'code',
            SimpleTorrentErrorCode.timeout,
          ),
        ),
      );
    }
  });

  test('converts native error codes into typed exceptions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'invalidArgument',
            message: 'A destination is required.',
          );
        });

    await expectLater(
      platform.pause(1),
      throwsA(
        isA<SimpleTorrentException>().having(
          (error) => error.code,
          'code',
          SimpleTorrentErrorCode.invalidArgument,
        ),
      ),
    );
  });

  test('rejects malformed successful responses', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    await expectLater(
      platform.start(magnet: 'magnet:test', path: 'downloads'),
      throwsA(
        isA<SimpleTorrentException>().having(
          (error) => error.code,
          'code',
          SimpleTorrentErrorCode.invalidResponse,
        ),
      ),
    );

    await expectLater(
      platform.areTransfersSuspended(),
      throwsA(
        isA<SimpleTorrentException>().having(
          (error) => error.code,
          'code',
          SimpleTorrentErrorCode.invalidResponse,
        ),
      ),
    );
  });
}
