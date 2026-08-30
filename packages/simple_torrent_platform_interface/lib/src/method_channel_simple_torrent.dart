import 'dart:async';

import 'package:flutter/services.dart';

import 'channel_names.dart';
import 'simple_torrent_exception.dart';
import 'simple_torrent_platform.dart';
import 'torrent_config.dart';
import 'torrent_models.dart';

/// Shared production MethodChannel implementation used by every platform.
class MethodChannelSimpleTorrent extends SimpleTorrentPlatform {
  factory MethodChannelSimpleTorrent({
    MethodChannel methods = const MethodChannel(
      SimpleTorrentChannelNames.methods,
    ),
    EventChannel progress = const EventChannel(
      SimpleTorrentChannelNames.progress,
    ),
    EventChannel metadata = const EventChannel(
      SimpleTorrentChannelNames.metadata,
    ),
    // Native finalisation waits for both durable writes and closed file
    // handles, with a bounded 60-second native deadline.
    Duration methodTimeout = const Duration(seconds: 75),
  }) =>
      MethodChannelSimpleTorrent._(methods, progress, metadata, methodTimeout);

  MethodChannelSimpleTorrent._(
    this._methods,
    this._progress,
    this._metadata,
    this._methodTimeout,
  );

  final MethodChannel _methods;
  final EventChannel _progress;
  final EventChannel _metadata;
  final Duration _methodTimeout;

  late final Stream<TorrentStats> _stats = _eventStream(
    _progress,
    TorrentStats.fromMap,
    'progress',
  );
  late final Stream<TorrentMetadata> _metadataEvents = _eventStream(
    _metadata,
    TorrentMetadata.fromMap,
    'metadata',
  );

  @override
  Future<void> init({TorrentConfig? config}) => _invokeVoid(
    'init',
    <String, Object>{if (config != null) 'config': config.toMap()},
  );

  @override
  Future<void> updateConfig(TorrentConfig config) =>
      _invokeVoid('updateConfig', <String, Object>{'config': config.toMap()});

  @override
  Future<void> setTransfersSuspended(bool suspended) => _invokeVoid(
    'setTransfersSuspended',
    <String, Object>{'suspended': suspended},
  );

  @override
  Future<bool> areTransfersSuspended() async {
    final result = await _invoke<Object?>('areTransfersSuspended');
    if (result is! bool) {
      throw _invalidResponse('areTransfersSuspended', result);
    }
    return result;
  }

  @override
  Future<int> start({
    required String magnet,
    required String path,
    String? displayName,
  }) => _start('start', <String, Object>{
    'magnet': magnet,
    'destination': path,
    'displayName': ?displayName,
  });

  @override
  Future<int> startFromData({
    required Uint8List data,
    required String path,
    String? displayName,
  }) => _start('startFromData', <String, Object>{
    'data': data,
    'destination': path,
    'displayName': ?displayName,
  });

  @override
  Future<int> startFromFile({
    required String torrentFilePath,
    required String path,
    String? displayName,
  }) => _start('startFromFile', <String, Object>{
    'torrentFilePath': torrentFilePath,
    'destination': path,
    'displayName': ?displayName,
  });

  @override
  Future<void> pause(int id) =>
      _invokeVoid('pause', <String, Object>{'id': id});

  @override
  Future<void> resume(int id) =>
      _invokeVoid('resume', <String, Object>{'id': id});

  @override
  Future<void> cancel(int id) =>
      _invokeVoid('cancel', <String, Object>{'id': id});

  @override
  Future<void> finalise(int id) =>
      _invokeVoid('finalise', <String, Object>{'id': id});

  @override
  Future<List<int>> getActiveTorrentIds() async {
    final result = await _invoke<Object?>('getActiveTorrentIds');
    if (result is! List || result.any((value) => value is! num)) {
      throw _invalidResponse('getActiveTorrentIds', result);
    }
    return result.cast<num>().map((id) => id.toInt()).toList(growable: false);
  }

  @override
  Future<bool> exists(int id) async {
    final result = await _invoke<Object?>('exists', <String, Object>{'id': id});
    if (result is! bool) {
      throw _invalidResponse('exists', result);
    }
    return result;
  }

  @override
  Future<TorrentState> getState(int id) async {
    final result = await _invoke<Object?>('getState', <String, Object>{
      'id': id,
    });
    if (result is! String) {
      throw _invalidResponse('getState', result);
    }
    return TorrentStateExtension.fromString(result);
  }

  @override
  Future<TorrentInfo> getTorrentInfo(int id) async {
    final result = await _invoke<Object?>('getTorrentInfo', <String, Object>{
      'id': id,
    });
    if (result is! Map) {
      throw _invalidResponse('getTorrentInfo', result);
    }
    try {
      return TorrentInfo.fromMap(result);
    } on FormatException catch (error) {
      throw _invalidResponse('getTorrentInfo', result, error.message);
    }
  }

  @override
  Future<String> getLastError(int id) async {
    final result = await _invoke<Object?>('getLastError', <String, Object>{
      'id': id,
    });
    if (result is! String) {
      throw _invalidResponse('getLastError', result);
    }
    return result;
  }

  @override
  Stream<TorrentStats> get statsStream => _stats;

  @override
  Stream<TorrentMetadata> get metadataStream => _metadataEvents;

  Future<int> _start(String method, Map<String, Object> arguments) async {
    final result = await _invoke<Object?>(method, arguments);
    if (result is! num || result.toInt() <= 0) {
      throw _invalidResponse(method, result);
    }
    return result.toInt();
  }

  Future<void> _invokeVoid(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    await _invoke<Object?>(method, arguments);
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object>? arguments]) async {
    try {
      return await _methods
          .invokeMethod<T>(method, arguments)
          .timeout(_methodTimeout);
    } on TimeoutException {
      throw SimpleTorrentException(
        SimpleTorrentErrorCode.timeout,
        'The "$method" operation timed out after '
        '${_methodTimeout.inSeconds} seconds.',
      );
    } on PlatformException catch (error) {
      throw SimpleTorrentException.fromPlatformException(error);
    } on MissingPluginException catch (error) {
      throw SimpleTorrentException(
        SimpleTorrentErrorCode.unavailable,
        error.message ?? 'The platform plugin is unavailable.',
      );
    }
  }

  Stream<T> _eventStream<T>(
    EventChannel channel,
    T Function(Map<dynamic, dynamic>) decode,
    String streamName,
  ) {
    return channel
        .receiveBroadcastStream()
        .map((event) {
          if (event is! Map) {
            throw _invalidResponse('$streamName event', event);
          }
          try {
            return decode(event);
          } on FormatException catch (error) {
            throw _invalidResponse('$streamName event', event, error.message);
          }
        })
        .transform(
          StreamTransformer<T, T>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              if (error is PlatformException) {
                sink.addError(
                  SimpleTorrentException.fromPlatformException(error),
                  stackTrace,
                );
              } else {
                sink.addError(error, stackTrace);
              }
            },
          ),
        );
  }

  SimpleTorrentException _invalidResponse(
    String operation,
    Object? value, [
    String? reason,
  ]) {
    return SimpleTorrentException(
      SimpleTorrentErrorCode.invalidResponse,
      'The native "$operation" response did not match the v2 contract.',
      details: <String, Object?>{'value': value, 'reason': reason},
    );
  }
}
