import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory packageRoot;
  late String source;

  setUpAll(() {
    packageRoot = Directory('windows').existsSync()
        ? Directory.current
        : Directory('packages/simple_torrent_windows');
    source = File(
      '${packageRoot.path}/windows/simple_torrent_plugin.cpp',
    ).readAsStringSync();
  });

  test('setTransfersSuspended strictly decodes and forwards a boolean', () {
    final start = source.indexOf('if (method == "setTransfersSuspended")');
    final end = source.indexOf('if (method == "areTransfersSuspended")', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    expect(handler, contains('Find(*arguments, "suspended")'));
    expect(handler, contains('std::get_if<bool>(value)'));
    expect(handler, contains('suspended must be a boolean'));
    expect(handler, contains('simple_torrent_manager_set_transfers_suspended'));
  });

  test('areTransfersSuspended returns false as a successful value', () {
    final start = source.indexOf('if (method == "areTransfersSuspended")');
    final end = source.indexOf('if (method == "getActiveTorrentIds")', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);
    expect(handler, contains('simple_torrent_manager_transfers_suspended'));
    expect(handler, contains('code == SIMPLE_TORRENT_OK'));
    expect(handler, contains('EncodableValue(suspended != 0)'));
  });

  test('staged C header declares both additive ABI functions', () {
    final header = File(
      '${packageRoot.path}/windows/include/simple_torrent_native.h',
    ).readAsStringSync();
    expect(header, contains('simple_torrent_manager_set_transfers_suspended'));
    expect(header, contains('simple_torrent_manager_transfers_suspended'));
  });
}
