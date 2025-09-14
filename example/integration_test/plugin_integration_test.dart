// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:simple_torrent/simple_torrent.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SimpleTorrent initialization test', (WidgetTester tester) async {
    // Test basic initialization
    await SimpleTorrent.init();

    // Test getting active torrent IDs (should be empty initially)
    final activeIds = await SimpleTorrent.getActiveTorrentIds();
    expect(activeIds, isEmpty);
  });

  testWidgets('SimpleTorrent configuration test', (WidgetTester tester) async {
    // Test initialization with custom configuration
    const config = TorrentConfig(
      maxTorrents: 5,
      maxDownloadRate: 1024 * 1024, // 1MB/s
      maxUploadRate: 512 * 1024,    // 512KB/s
      enableDHT: true,
      userAgent: 'TestApp/1.0',
      downloadLimit: 1024 * 1024,   // Alternative rate limit
      uploadLimit: 512 * 1024,      // Alternative rate limit
      connections: 50,
      autoManaged: true,
    );

    await SimpleTorrent.init(config: config);

    // Verify initialization succeeded by checking we can call other methods
    final activeIds = await SimpleTorrent.getActiveTorrentIds();
    expect(activeIds, isA<List<int>>());
  });

  testWidgets('SimpleTorrent invalid torrent operations', (
    WidgetTester tester,
  ) async {
    await SimpleTorrent.init();

    // Test checking non-existent torrent
    final exists = await SimpleTorrent.exists(99999);
    expect(exists, false);

    // Test getting state of non-existent torrent
    final state = await SimpleTorrent.getState(99999);
    expect(state, TorrentState.error);
  });
}
