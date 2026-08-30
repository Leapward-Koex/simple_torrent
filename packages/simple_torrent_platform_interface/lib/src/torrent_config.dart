import 'simple_torrent_exception.dart';

/// Runtime settings supported by the native torrent manager.
///
/// Rate limits are expressed in bytes per second. A rate of zero means
/// unlimited.
class TorrentConfig {
  const TorrentConfig({
    this.maxTorrents = 20,
    this.downloadRateLimit = 0,
    this.uploadRateLimit = 0,
    this.connectionsLimit = 200,
    this.enableDht = true,
    this.userAgent = 'simple_torrent/2.0.0',
  });

  factory TorrentConfig.fromMap(Map<dynamic, dynamic> map) {
    return TorrentConfig(
      maxTorrents: _integer(map, 'maxTorrents', 20),
      downloadRateLimit: _integer(map, 'downloadRateLimit', 0),
      uploadRateLimit: _integer(map, 'uploadRateLimit', 0),
      connectionsLimit: _integer(map, 'connectionsLimit', 200),
      enableDht: map['enableDht'] as bool? ?? true,
      userAgent: map['userAgent'] as String? ?? 'simple_torrent/2.0.0',
    );
  }

  final int maxTorrents;
  final int downloadRateLimit;
  final int uploadRateLimit;
  final int connectionsLimit;
  final bool enableDht;
  final String userAgent;

  Map<String, Object> toMap() {
    validate();
    return <String, Object>{
      'maxTorrents': maxTorrents,
      'downloadRateLimit': downloadRateLimit,
      'uploadRateLimit': uploadRateLimit,
      'connectionsLimit': connectionsLimit,
      'enableDht': enableDht,
      'userAgent': userAgent,
    };
  }

  /// Validates values before they are sent to the native implementation.
  ///
  /// Native managers repeat these checks because channel input is untrusted.
  void validate() {
    final invalidField = switch (this) {
      TorrentConfig(maxTorrents: <= 0 || > 10000) => 'maxTorrents',
      TorrentConfig(downloadRateLimit: < 0 || > 0x7fffffff) =>
        'downloadRateLimit',
      TorrentConfig(uploadRateLimit: < 0 || > 0x7fffffff) => 'uploadRateLimit',
      TorrentConfig(connectionsLimit: <= 0 || > 100000) => 'connectionsLimit',
      TorrentConfig(userAgent: final value) when value.trim().isEmpty =>
        'userAgent',
      TorrentConfig(userAgent: final value) when value.contains('\u0000') =>
        'userAgent',
      _ => null,
    };
    if (invalidField != null) {
      throw SimpleTorrentException(
        SimpleTorrentErrorCode.invalidConfig,
        'TorrentConfig.$invalidField has an invalid value.',
      );
    }
  }

  static int _integer(Map<dynamic, dynamic> map, String key, int defaultValue) {
    final value = map[key];
    return value is num ? value.toInt() : defaultValue;
  }
}
