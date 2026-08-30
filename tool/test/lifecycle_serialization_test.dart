import 'dart:io';

void main() {
  final source = File('native/src/torrent_manager.cpp').readAsStringSync();

  final pause = _between(
    source,
    'simple_torrent_result_t Manager::Pause',
    'simple_torrent_result_t Manager::Resume',
  );
  final resume = _between(
    source,
    'simple_torrent_result_t Manager::Resume',
    'simple_torrent_result_t Manager::Cancel',
  );
  final cancel = _between(
    source,
    'simple_torrent_result_t Manager::Cancel',
    'simple_torrent_result_t Manager::Finalise',
  );
  final finalise = _between(
    source,
    'simple_torrent_result_t Manager::Finalise',
    'std::vector<std::int32_t> Manager::ActiveIds',
  );

  _expectLifecycleGuard(
    pause,
    'entry->handle.unset_flags',
    'pause rejects an entry already claimed by finalise',
  );
  _expectLifecycleGuard(
    resume,
    'entry->handle.clear_error',
    'resume rejects an entry already claimed by finalise',
  );
  _expectLifecycleGuard(
    cancel,
    'entry->active.store(false)',
    'cancel rejects an entry already claimed by finalise',
  );

  final cancelInactive = cancel.indexOf('entry->active.store(false)');
  final cancelRemove = cancel.indexOf('session_->remove_torrent');
  final cancelUnlock = cancel.indexOf('lifecycle_lock.unlock()');
  final cancelMapLock = cancel.indexOf('std::lock_guard lock(mutex_)');
  _expect(
    cancelRemove > cancelInactive,
    'cancel marks inactive before removal',
  );
  _expect(cancelUnlock > cancelRemove, 'cancel serialises native removal');
  _expect(
    cancelMapLock > cancelUnlock,
    'cancel releases the entry lock before acquiring the manager lock',
  );

  final claimLock = finalise.indexOf(
    'std::lock_guard lifecycle_lock(entry->lifecycle_mutex)',
  );
  final claimGuard = finalise.indexOf(
    'if (entry->finalising || !entry->active.load())',
    claimLock,
  );
  final claimFlag = finalise.indexOf('entry->finalising = true', claimGuard);
  final claimInactive = finalise.indexOf(
    'entry->active.store(false)',
    claimFlag,
  );
  _expect(claimLock >= 0, 'finalise locks the entry lifecycle');
  _expect(claimGuard > claimLock, 'finalise validates while locked');
  _expect(claimFlag > claimGuard, 'finalise claims the entry while locked');
  _expect(
    claimInactive > claimFlag,
    'finalise claims the entry before marking it inactive',
  );

  final catchStart = finalise.indexOf('} catch (...) {');
  final catchSource = finalise.substring(catchStart);
  _expect(
    catchSource.contains(
      'std::lock_guard lifecycle_lock(entry->lifecycle_mutex)',
    ),
    'finalise failure state is restored under the lifecycle lock',
  );
  _expect(
    catchSource.indexOf('entry->active.store(true)') >
        catchSource.indexOf('if (!removal_started)'),
    'pre-removal finalise failure atomically reactivates the entry',
  );

  stdout.writeln('{"ok":true,"suite":"lifecycle-serialization"}');
}

void _expectLifecycleGuard(
  String source,
  String firstMutation,
  String description,
) {
  final lock = source.indexOf(
    'std::unique_lock lifecycle_lock(entry->lifecycle_mutex)',
  );
  final guard = source.indexOf(
    'if (entry->finalising || !entry->active.load())',
    lock,
  );
  final mutation = source.indexOf(firstMutation, guard);
  _expect(lock >= 0, '$description: locks lifecycle');
  _expect(guard > lock, '$description: checks finalising while locked');
  _expect(mutation > guard, '$description: checks before mutation');
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
