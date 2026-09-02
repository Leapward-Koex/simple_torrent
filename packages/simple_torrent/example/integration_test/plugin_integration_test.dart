import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:simple_torrent/simple_torrent.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Native automation can enable platform accessibility after flutter_test
  // records its semantics-handle baseline. Pin the test dispatcher so that
  // this framework-owned handle is not reported as a leak from the test.
  binding.platformDispatcher.semanticsEnabledTestValue = false;

  testWidgets(
    'native plugin initializes and answers a query',
    (_) async {
      await SimpleTorrent.init(
        config: const TorrentConfig(
          maxTorrents: 2,
          downloadRateLimit: 0,
          uploadRateLimit: 0,
          connectionsLimit: 50,
          enableDht: true,
          userAgent: 'simple_torrent_smoke_test/2.0.0',
        ),
      );
      expect(await SimpleTorrent.getActiveTorrentIds(), isA<List<int>>());
    },
    // These native-only checks do not inspect the accessibility tree.
    semanticsEnabled: false,
  );
}
