import 'package:flutter/services.dart';

/// Stable error categories exposed by simple_torrent.
enum SimpleTorrentErrorCode {
  invalidArgument,
  invalidConfig,
  notInitialized,
  torrentNotFound,
  torrentLimitReached,
  duplicateTorrent,
  invalidMagnet,
  invalidTorrent,
  invalidTorrentData,
  invalidTorrentFile,
  io,
  timeout,
  unavailable,
  nativeError,
  invalidResponse,
  unknown,
}

extension SimpleTorrentErrorCodeWireName on SimpleTorrentErrorCode {
  String get wireName => switch (this) {
    SimpleTorrentErrorCode.invalidArgument => 'invalid_argument',
    SimpleTorrentErrorCode.invalidConfig => 'invalid_config',
    SimpleTorrentErrorCode.notInitialized => 'not_initialized',
    SimpleTorrentErrorCode.torrentNotFound => 'torrent_not_found',
    SimpleTorrentErrorCode.torrentLimitReached => 'torrent_limit_reached',
    SimpleTorrentErrorCode.duplicateTorrent => 'duplicate_torrent',
    SimpleTorrentErrorCode.invalidMagnet => 'invalid_magnet',
    SimpleTorrentErrorCode.invalidTorrent => 'invalid_torrent',
    SimpleTorrentErrorCode.invalidTorrentData => 'invalid_torrent_data',
    SimpleTorrentErrorCode.invalidTorrentFile => 'invalid_torrent_file',
    SimpleTorrentErrorCode.io => 'io_error',
    SimpleTorrentErrorCode.timeout => 'timeout',
    SimpleTorrentErrorCode.unavailable => 'unavailable',
    SimpleTorrentErrorCode.nativeError => 'native_error',
    SimpleTorrentErrorCode.invalidResponse => 'invalid_response',
    SimpleTorrentErrorCode.unknown => 'unknown',
  };
}

/// An error reported by the platform implementation or channel contract.
class SimpleTorrentException implements Exception {
  const SimpleTorrentException(this.code, this.message, {this.details});

  factory SimpleTorrentException.fromPlatformException(
    PlatformException exception,
  ) {
    return SimpleTorrentException(
      _codeFromWireName(exception.code),
      exception.message ?? 'The native torrent operation failed.',
      details: exception.details,
    );
  }

  final SimpleTorrentErrorCode code;
  final String message;
  final Object? details;

  @override
  String toString() => 'SimpleTorrentException(${code.wireName}): $message';

  static SimpleTorrentErrorCode _codeFromWireName(String value) {
    final snakeCase = value.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match[1]}_${match[2]}',
    );
    final normalized = snakeCase.toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'invalid_argument' ||
      'bad_arguments' => SimpleTorrentErrorCode.invalidArgument,
      'invalid_config' => SimpleTorrentErrorCode.invalidConfig,
      'not_initialized' => SimpleTorrentErrorCode.notInitialized,
      'torrent_not_found' ||
      'not_found' => SimpleTorrentErrorCode.torrentNotFound,
      'torrent_limit_reached' ||
      'limit_reached' => SimpleTorrentErrorCode.torrentLimitReached,
      'duplicate_torrent' ||
      'already_exists' => SimpleTorrentErrorCode.duplicateTorrent,
      'invalid_magnet' => SimpleTorrentErrorCode.invalidMagnet,
      'invalid_torrent' => SimpleTorrentErrorCode.invalidTorrent,
      'invalid_torrent_data' => SimpleTorrentErrorCode.invalidTorrentData,
      'invalid_torrent_file' => SimpleTorrentErrorCode.invalidTorrentFile,
      'io' || 'io_error' => SimpleTorrentErrorCode.io,
      'timeout' => SimpleTorrentErrorCode.timeout,
      'unavailable' || 'missing_plugin' => SimpleTorrentErrorCode.unavailable,
      'native_error' => SimpleTorrentErrorCode.nativeError,
      'invalid_response' => SimpleTorrentErrorCode.invalidResponse,
      _ => SimpleTorrentErrorCode.unknown,
    };
  }
}
