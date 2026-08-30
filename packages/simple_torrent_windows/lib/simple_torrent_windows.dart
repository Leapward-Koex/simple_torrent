import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

/// The Windows implementation of [SimpleTorrentPlatform].
///
/// This class implements the `package:simple_torrent` functionality for Windows.
class SimpleTorrentWindows {
  /// Registers this class as the platform implementation for Windows.
  static void registerWith() {
    SimpleTorrentPlatform.instance = MethodChannelSimpleTorrent();
  }
}
