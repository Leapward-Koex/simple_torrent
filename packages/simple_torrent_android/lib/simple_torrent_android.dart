import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

/// The Android implementation of [SimpleTorrentPlatform].
///
/// This class implements the `package:simple_torrent` functionality for Android.
class SimpleTorrentAndroid {
  /// Registers this class as the platform implementation for Android.
  static void registerWith() {
    SimpleTorrentPlatform.instance = MethodChannelSimpleTorrent();
  }
}
