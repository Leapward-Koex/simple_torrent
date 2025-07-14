import 'dart:async';
import 'package:flutter/services.dart';
import 'simple_torrent_platform_interface.dart';

/// Android implementation via MethodChannel / EventChannel.
class MethodChannelSimpleTorrent extends SimpleTorrentPlatform {
  static const _methods = MethodChannel('simple_torrent/methods');
  static const _events = EventChannel('simple_torrent/progress');
  static const _metaData = EventChannel('simple_torrent/metadata');
  static const Duration _methodTimeout = Duration(seconds: 15);

  late final Stream<TorrentStats> _stats$ = _events.receiveBroadcastStream().map((e) => TorrentStats.fromMap(e as Map<dynamic, dynamic>));
  late final Stream<TorrentMetadata> _metaData$ = _metaData.receiveBroadcastStream().map(
    (e) => TorrentMetadata.fromMap(e as Map<dynamic, dynamic>),
  );

  @override
  Future<void> init({TorrentConfig? config}) async {
    return _methods
        .invokeMethod('init', {
          if (config != null) 'config': config.toMap(),
        })
        .timeout(_methodTimeout);
  }

  @override
  Future<void> updateConfig(TorrentConfig config) async {
    return _methods
        .invokeMethod('init', {'config': config.toMap()})
        .timeout(_methodTimeout);
  }

  @override
  Future<int> start({required String magnet, required String path, String? displayName}) async {
    try {
      final result = await _methods
          .invokeMethod<int>('start', {'magnet': magnet, 'destination': path, if (displayName != null) 'displayName': displayName})
          .timeout(_methodTimeout);
      return result ?? 0;
    } on TimeoutException {
      throw Exception('Torrent start operation timed out');
    }
  }

  @override
  Future<void> pause(int id) => _methods.invokeMethod('pause', {'id': id}).timeout(_methodTimeout);

  @override
  Future<void> resume(int id) => _methods.invokeMethod('resume', {'id': id}).timeout(_methodTimeout);

  @override
  Future<void> cancel(int id) => _methods.invokeMethod('cancel', {'id': id}).timeout(_methodTimeout);

  @override
  Future<List<int>> getActiveTorrentIds() async {
    try {
      final result = await _methods.invokeMethod<List<dynamic>>('getActiveTorrentIds');
      return result?.cast<int>() ?? [];
    } catch (e) {
      throw Exception('Failed to get active torrent IDs: $e');
    }
  }

  @override
  Future<bool> exists(int id) async {
    try {
      final result = await _methods.invokeMethod<bool>('exists', {'id': id});
      return result ?? false;
    } catch (e) {
      throw Exception('Failed to check torrent existence: $e');
    }
  }

  @override
  Future<TorrentState> getState(int id) async {
    try {
      final result = await _methods.invokeMethod<String>('getState', {'id': id});
      return TorrentStateExtension.fromString(result ?? 'error');
    } catch (e) {
      throw Exception('Failed to get torrent state: $e');
    }
  }

  @override
  Future<TorrentInfo> getTorrentInfo(int id) async {
    try {
      final result = await _methods.invokeMethod<Map<dynamic, dynamic>>('getTorrentInfo', {'id': id});
      if (result == null) {
        throw Exception('Torrent not found');
      }
      return TorrentInfo.fromMap(result);
    } catch (e) {
      throw Exception('Failed to get torrent info: $e');
    }
  }

  @override
  Future<String> getLastError(int id) async {
    try {
      final result = await _methods.invokeMethod<String>('getLastError', {'id': id});
      return result ?? 'Unknown error';
    } catch (e) {
      throw Exception('Failed to get last error: $e');
    }
  }

  @override
  Stream<TorrentStats> get statsStream => _stats$;

  @override
  Stream<TorrentMetadata> get metadataStream => _metaData$;
}
