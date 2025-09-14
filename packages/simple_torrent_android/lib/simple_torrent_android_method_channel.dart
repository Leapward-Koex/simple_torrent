import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:simple_torrent_platform_interface/simple_torrent_platform_interface.dart';

/// Android implementation via MethodChannel / EventChannel.
class SimpleTorrentAndroidMethodChannel extends SimpleTorrentPlatform {
  static const _methods = MethodChannel('simple_torrent/methods');
  static const _events = EventChannel('simple_torrent/progress');
  static const _metaData = EventChannel('simple_torrent/metadata');
  static const Duration _methodTimeout = Duration(seconds: 15);

  late final Stream<TorrentStats> _stats$ = _events
      .receiveBroadcastStream()
      .map((e) => TorrentStats.fromMap(e as Map<dynamic, dynamic>));
  late final Stream<TorrentMetadata> _metaData$ = _metaData
      .receiveBroadcastStream()
      .map((e) => TorrentMetadata.fromMap(e as Map<dynamic, dynamic>));

  @override
  Future<void> init({TorrentConfig? config}) async {
    return _methods
        .invokeMethod('init', {if (config != null) 'config': config.toMap()})
        .timeout(_methodTimeout);
  }

  @override
  Future<void> updateConfig(TorrentConfig config) async {
    return _methods
        .invokeMethod('init', {'config': config.toMap()})
        .timeout(_methodTimeout);
  }

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) async {
    try {
      final result = await _methods
          .invokeMethod<int>('start', {
            'magnet': magnet,
            'destination': path,
            if (displayName != null) 'displayName': displayName,
          })
          .timeout(_methodTimeout);
      return result ?? 0;
    } on TimeoutException {
      throw Exception('Torrent start operation timed out');
    }
  }

  @override
  Future<int> startFromTorrentData({
    required Uint8List data,
    required String path,
    String? displayName,
  }) async {
    try {
      final result = await _methods
          .invokeMethod<int>('startFromData', {
            'data': data,
            'destination': path,
            if (displayName != null) 'displayName': displayName,
          })
          .timeout(_methodTimeout);
      return result ?? 0;
    } on TimeoutException {
      throw Exception('Torrent start operation timed out');
    }
  }

  @override
  Future<int> startFromTorrentFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  }) async {
    try {
      final result = await _methods
          .invokeMethod<int>('startFromFile', {
            'filePath': torrentFilePath,
            'destination': path,
            if (displayName != null) 'displayName': displayName,
          })
          .timeout(_methodTimeout);
      return result ?? 0;
    } on TimeoutException {
      throw Exception('Torrent start operation timed out');
    }
  }

  @override
  Future<void> pause(int id) async {
    return _methods.invokeMethod('pause', {'id': id}).timeout(_methodTimeout);
  }

  @override
  Future<void> resume(int id) async {
    return _methods.invokeMethod('resume', {'id': id}).timeout(_methodTimeout);
  }

  @override
  Future<void> cancel(int id) async {
    return _methods.invokeMethod('cancel', {'id': id}).timeout(_methodTimeout);
  }

  @override
  Future<void> finalise(int id) async {
    return _methods
        .invokeMethod('finalise', {'id': id})
        .timeout(_methodTimeout);
  }

  @override
  Future<List<int>> getActiveTorrentIds() async {
    final result = await _methods
        .invokeListMethod<int>('getActiveTorrentIds')
        .timeout(_methodTimeout);
    return result ?? [];
  }

  @override
  Future<bool> exists(int id) async {
    final result = await _methods
        .invokeMethod<bool>('exists', {'id': id})
        .timeout(_methodTimeout);
    return result ?? false;
  }

  @override
  Future<TorrentState> getState(int id) async {
    final result = await _methods
        .invokeMethod<String>('getState', {'id': id})
        .timeout(_methodTimeout);
    return TorrentStateExtension.fromString(result ?? 'error');
  }

  @override
  Future<TorrentInfo> getTorrentInfo(int id) async {
    final result = await _methods
        .invokeMapMethod<String, dynamic>('getTorrentInfo', {'id': id})
        .timeout(_methodTimeout);
    if (result == null) {
      throw Exception('Failed to get torrent info for id: $id');
    }
    return TorrentInfo.fromMap(result);
  }

  @override
  Future<String> getLastError(int id) async {
    final result = await _methods
        .invokeMethod<String>('getLastError', {'id': id})
        .timeout(_methodTimeout);
    return result ?? '';
  }

  @override
  Stream<TorrentStats> get statsStream => _stats$;

  @override
  Stream<TorrentMetadata> get metadataStream => _metaData$;
}
