import 'dart:async';
import 'package:flutter/services.dart';
import 'simple_torrent_platform_interface.dart';

/// Android implementation via MethodChannel / EventChannel.
class MethodChannelSimpleTorrent extends SimpleTorrentPlatform {
  static const _methods = MethodChannel('simple_torrent/methods');
  static const _events = EventChannel('simple_torrent/progress');

  // Lazily‑constructed broadcast stream.
  late final Stream<TorrentProgress> _progress$ = _events.receiveBroadcastStream().map(
    (e) => TorrentProgress.fromMap(e as Map<dynamic, dynamic>),
  );

  @override
  Future<void> init({int concurrency = 2}) => _methods.invokeMethod('init', {'concurrency': concurrency});

  @override
  Future<String> start({required String magnet, required String path}) async =>
      (await _methods.invokeMethod<String>('start', {'magnet': magnet, 'path': path})) ?? '';

  @override
  Future<void> pause(String id) => _methods.invokeMethod('pause', {'id': id});

  @override
  Future<void> resume(String id) => _methods.invokeMethod('resume', {'id': id});

  @override
  Future<void> cancel(String id) => _methods.invokeMethod('cancel', {'id': id});

  @override
  Stream<TorrentProgress> get progressStream => _progress$;
}
