import 'package:flutter_test/flutter_test.dart';
import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

void main() {
  test('config serializes only implemented v2 settings', () {
    const config = TorrentConfig(
      maxTorrents: 5,
      downloadRateLimit: 1000,
      uploadRateLimit: 500,
      connectionsLimit: 80,
      enableDht: false,
      userAgent: 'tests/2.0',
    );

    expect(config.toMap(), <String, Object>{
      'maxTorrents': 5,
      'downloadRateLimit': 1000,
      'uploadRateLimit': 500,
      'connectionsLimit': 80,
      'enableDht': false,
      'userAgent': 'tests/2.0',
    });
    expect(TorrentConfig.fromMap(config.toMap()).toMap(), config.toMap());
  });

  test('config reports invalid native bounds with a typed error', () {
    const invalidConfigs = <TorrentConfig>[
      TorrentConfig(maxTorrents: 10001),
      TorrentConfig(downloadRateLimit: 0x80000000),
      TorrentConfig(uploadRateLimit: 0x80000000),
      TorrentConfig(connectionsLimit: 100001),
      TorrentConfig(userAgent: '   '),
      TorrentConfig(userAgent: 'invalid\u0000agent'),
    ];

    for (final config in invalidConfigs) {
      expect(
        config.toMap,
        throwsA(
          isA<SimpleTorrentException>().having(
            (error) => error.code,
            'code',
            SimpleTorrentErrorCode.invalidConfig,
          ),
        ),
      );
    }
  });

  test('metadata decodes hashes and every payload file', () {
    final metadata = TorrentMetadata.fromMap(<String, Object>{
      'id': 7,
      'name': 'Sample',
      'total_bytes': 30,
      'piece_size': 16,
      'piece_count': 2,
      'file_count': 2,
      'creation_date': 123,
      'private': false,
      'v1_info_hash': 'A88FDA5954E89178C372716A6A78B8180ED4DAD3',
      'v2_info_hash': '',
      'files': <Map<String, Object>>[
        <String, Object>{'index': 0, 'path': 'a', 'size': 10, 'offset': 0},
        <String, Object>{'index': 1, 'path': 'b', 'size': 20, 'offset': 10},
      ],
    });

    expect(metadata.v1InfoHash, 'a88fda5954e89178c372716a6a78b8180ed4dad3');
    expect(metadata.v2InfoHash, isNull);
    expect(metadata.isV1, isTrue);
    expect(metadata.isV2, isFalse);
    expect(metadata.files.map((file) => file.path), <String>['a', 'b']);
    expect(
      metadata.files.fold<int>(0, (sum, file) => sum + file.size),
      metadata.totalBytes,
    );
  });
}
