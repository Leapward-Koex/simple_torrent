import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

/// The iOS implementation of [SimpleTorrentPlatform].
///
/// This class implements the `package:simple_torrent` functionality for iOS.
class SimpleTorrentIOS {
  /// Registers this class as the platform implementation for iOS.
  static void registerWith() {
    SimpleTorrentPlatform.instance = MethodChannelSimpleTorrent();
  }
}
