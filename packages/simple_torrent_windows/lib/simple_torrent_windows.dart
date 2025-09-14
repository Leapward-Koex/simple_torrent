import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';
import 'simple_torrent_windows_method_channel.dart';

/// The Windows implementation of [SimpleTorrentPlatform].
///
/// This class implements the `package:simple_torrent` functionality for Windows.
class SimpleTorrentWindows {
  /// Registers this class as the platform implementation for Windows.
  static void registerWith() {
    SimpleTorrentPlatform.instance = SimpleTorrentWindowsMethodChannel();
  }
}
