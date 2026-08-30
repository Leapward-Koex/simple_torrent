import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    final packageRoot = Directory('macos').existsSync()
        ? Directory.current
        : Directory('packages/simple_torrent_macos');
    source = File(
      '${packageRoot.path}/macos/simple_torrent_macos/Sources/'
      'simple_torrent_macos/SimpleTorrentPlugin.swift',
    ).readAsStringSync();
  });

  test('declares the additive transfer suspension C ABI exactly', () {
    expect(
      source,
      contains(
        '@_silgen_name("simple_torrent_manager_set_transfers_suspended")',
      ),
    );
    expect(
      source,
      contains('@_silgen_name("simple_torrent_manager_transfers_suspended")'),
    );
    expect(
      source,
      isNot(contains('simple_torrent_manager_are_transfers_suspended')),
    );
    expect(source, contains('_ suspendedOut: UnsafeMutablePointer<UInt8>?'));
  });

  test('setTransfersSuspended strictly decodes and forwards a boolean', () {
    final start = source.indexOf('case "setTransfersSuspended":');
    final end = source.indexOf('case "areTransfersSuspended":', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    expect(handler, contains('arguments?["suspended"]'));
    expect(handler, contains('rawSuspended as? NSNumber'));
    expect(handler, contains('CFGetTypeID(number) == CFBooleanGetTypeID()'));
    expect(handler, contains('suspended must be a boolean'));
    expect(
      handler,
      contains(
        'nativeSetTransfersSuspended(manager, number.boolValue ? 1 : 0)',
      ),
    );
  });

  test('areTransfersSuspended preserves false as a successful value', () {
    final start = source.indexOf('case "areTransfersSuspended":');
    final end = source.indexOf('case "start":', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    expect(handler, contains('nativeTransfersSuspended(manager, &suspended)'));
    expect(handler, contains('code == 0'));
    expect(handler, contains('result(suspended != 0)'));
  });
}
