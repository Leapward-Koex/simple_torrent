import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finalise uses a serial worker and returns on the Apple main queue', () {
    final packageRoot = Directory('ios').existsSync()
        ? Directory.current
        : Directory('packages/simple_torrent_ios');
    final source = File(
      '${packageRoot.path}/ios/simple_torrent_ios/Sources/'
      'simple_torrent_ios/SimpleTorrentPlugin.swift',
    ).readAsStringSync();

    expect(source, contains('private let finaliseQueue = DispatchQueue('));
    final finaliseCase = source.indexOf('case "finalise":');
    final nextCase = source.indexOf(
      'case "getActiveTorrentIds":',
      finaliseCase,
    );
    final finaliseSource = source.substring(finaliseCase, nextCase);
    expect(finaliseSource, contains('finaliseQueue.async'));
    expect(finaliseSource, contains('nativeFinalise(manager, id)'));
    expect(finaliseSource, contains('DispatchQueue.main.async'));
    expect(finaliseSource, contains('finish(code, result: result)'));
  });

  test('deinit transfers teardown to the finalise worker without waiting', () {
    final packageRoot = Directory('ios').existsSync()
        ? Directory.current
        : Directory('packages/simple_torrent_ios');
    final source = File(
      '${packageRoot.path}/ios/simple_torrent_ios/Sources/'
      'simple_torrent_ios/SimpleTorrentPlugin.swift',
    ).readAsStringSync();
    final deinitStart = source.indexOf('deinit {');
    final registerStart = source.indexOf(
      'public static func register',
      deinitStart,
    );
    final deinitSource = source.substring(deinitStart, registerStart);

    expect(deinitSource, isNot(contains('finaliseQueue.sync')));
    final managerCapture = deinitSource.indexOf(
      'let managerToDestroy = manager',
    );
    final contextCapture = deinitSource.indexOf(
      'let contextToRelease = callbackContext',
    );
    final enqueue = deinitSource.indexOf('finaliseQueue.async');
    final destroy = deinitSource.indexOf('nativeDestroy(managerToDestroy)');
    final release = deinitSource.indexOf('contextToRelease?.release()');
    expect(managerCapture, greaterThanOrEqualTo(0));
    expect(contextCapture, greaterThan(managerCapture));
    expect(enqueue, greaterThan(contextCapture));
    expect(destroy, greaterThan(enqueue));
    expect(release, greaterThan(destroy));
    expect(deinitSource.substring(enqueue), isNot(contains('self.')));
  });
}
