import 'dart:io';

void main() {
  final manager = File('native/src/torrent_manager.cpp').readAsStringSync();
  final header = File('native/include/simple_torrent_native.h')
      .readAsStringSync();
  final cAbi = File('native/src/simple_torrent_native.cpp').readAsStringSync();

  final setter = _between(
    manager,
    'simple_torrent_result_t Manager::SetTransfersSuspended',
    'simple_torrent_result_t Manager::TransfersSuspended',
  );
  final getter = _between(
    manager,
    'simple_torrent_result_t Manager::TransfersSuspended',
    'simple_torrent_result_t Manager::Pause',
  );
  final add = _between(
    manager,
    'simple_torrent_result_t Manager::Add',
    'std::shared_ptr<Manager::Entry> Manager::Find',
  );

  _expect(
    setter.contains('std::lock_guard lock(mutex_)'),
    'suspension setter holds the manager mutex',
  );
  _expect(
    getter.contains('std::lock_guard lock(mutex_)'),
    'suspension getter holds the manager mutex',
  );
  final addLock = add.indexOf('std::lock_guard lock(mutex_)');
  final addTorrent = add.indexOf('session_->add_torrent');
  _expect(
    addLock >= 0 && addTorrent > addLock,
    'torrent addition is linearized by the same manager mutex',
  );
  _expect(setter.contains('session_->pause()'), 'setter pauses the session');
  _expect(setter.contains('session_->resume()'), 'setter resumes the session');
  _expect(
    setter.contains('session_->is_paused()'),
    'setter confirms the applied session state',
  );
  for (final forbidden in [
    'entries_',
    'entry->',
    'handle.pause',
    'handle.resume',
    'Manager::Pause',
    'Manager::Resume',
    'auto_managed',
  ]) {
    _expect(
      !setter.contains(forbidden),
      'setter does not use per-torrent mutation: $forbidden',
    );
  }

  for (final symbol in [
    'simple_torrent_manager_set_transfers_suspended',
    'simple_torrent_manager_transfers_suspended',
  ]) {
    _expect(header.contains(symbol), 'C header declares $symbol');
    _expect(cAbi.contains(symbol), 'C implementation exports $symbol');
  }
  _expect(
    cAbi.contains('suspended > 1'),
    'C ABI rejects non-boolean suspension values',
  );

  stdout.writeln('{"ok":true,"suite":"session-suspension-contract"}');
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  _expect(start >= 0, 'found $startMarker');
  _expect(end > start, 'found $endMarker after $startMarker');
  return source.substring(start, end);
}

void _expect(bool condition, String description) {
  if (!condition) throw StateError('FAILED: $description');
  stdout.writeln('PASS: $description');
}
