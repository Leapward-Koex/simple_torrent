import 'package:flutter_test/flutter_test.dart';
import 'package:simple_torrent/simple_torrent.dart';
import 'package:simple_torrent/simple_torrent_platform_interface.dart';
import 'package:simple_torrent/simple_torrent_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSimpleTorrentPlatform
    with MockPlatformInterfaceMixin
    implements SimpleTorrentPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SimpleTorrentPlatform initialPlatform = SimpleTorrentPlatform.instance;

  test('$MethodChannelSimpleTorrent is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSimpleTorrent>());
  });

  test('getPlatformVersion', () async {
    SimpleTorrent simpleTorrentPlugin = SimpleTorrent();
    MockSimpleTorrentPlatform fakePlatform = MockSimpleTorrentPlatform();
    SimpleTorrentPlatform.instance = fakePlatform;

    expect(await simpleTorrentPlugin.getPlatformVersion(), '42');
  });
}
