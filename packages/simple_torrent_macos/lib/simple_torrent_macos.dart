import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';
import 'simple_torrent_macos_method_channel.dart';

/// The macOS implementation of [SimpleTorrentPlatform].
///
/// This class implements the `package:simple_torrent` functionality for macOS.
class SimpleTorrentMacOS {
  /// Registers this class as the platform implementation for macOS.
  static void registerWith() {
    SimpleTorrentPlatform.instance = SimpleTorrentMacOSMethodChannel();
  }
}
