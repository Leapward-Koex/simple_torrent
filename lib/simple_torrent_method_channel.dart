import 'dart:async';
import 'package:flutter/services.dart';
import 'simple_torrent_platform_interface.dart';

/// Android implementation via MethodChannel / EventChannel.
class MethodChannelSimpleTorrent extends SimpleTorrentPlatform {
  static const _methods = MethodChannel('simple_torrent/methods');
  static const _events = EventChannel('simple_torrent/progress');

  late final Stream<TorrentStats> _stats$ = _events.receiveBroadcastStream().map((e) => TorrentStats.fromMap(e as Map<dynamic, dynamic>));

  @override
  Future<void> init({int concurrency = 2}) => _methods.invokeMethod('init', {'concurrency': concurrency});

  @override
  Future<int> start({required String magnet, required String path}) async =>
      (await _methods.invokeMethod<int>('start', {'magnet': magnet, 'destination': path}))!;

  @override
  Future<void> pause(int id) => _methods.invokeMethod('pause', {'id': id});

  @override
  Future<void> resume(int id) => _methods.invokeMethod('resume', {'id': id});

  @override
  Future<void> cancel(int id) => _methods.invokeMethod('cancel', {'id': id});

  @override
  Stream<TorrentStats> get statsStream => _stats$;
}
