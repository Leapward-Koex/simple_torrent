import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native events are posted to the delegated top-level window', () {
    final packageRoot = Directory('windows').existsSync()
        ? Directory.current
        : Directory('packages/simple_torrent_windows');
    final source = File('${packageRoot.path}/windows/simple_torrent_plugin.cpp')
        .readAsStringSync();

    expect(
      source,
      contains('GetAncestor(view_window_, GA_ROOT)'),
      reason: 'Flutter GetNativeWindow returns the child view HWND',
    );
    expect(
      source,
      contains('root_window == nullptr ? view_window_ : root_window'),
      reason: 'non-standard embedders still need a safe view-HWND fallback',
    );
    expect(source, contains('PostMessage(event_window, kNativeEventMessage'));
    final queueEventStart = source.indexOf(
      'void SimpleTorrentPlugin::QueueEvent',
    );
    final windowHandlerStart = source.indexOf(
      'std::optional<LRESULT> SimpleTorrentPlugin::HandleWindowMessage',
      queueEventStart,
    );
    final queueEventSource = source.substring(
      queueEventStart,
      windowHandlerStart,
    );
    expect(
      queueEventSource,
      contains('GetAncestor(view_window_, GA_ROOT)'),
      reason: 'the root must be resolved after runner reparenting, not cached',
    );
    expect(
      source,
      contains('RegisterTopLevelWindowProcDelegate'),
      reason: 'the posted HWND and registered dispatcher must be the same tier',
    );
  });

  test('one-shot metadata remains buffered until Dart listens', () {
    final packageRoot = Directory('windows').existsSync()
        ? Directory.current
        : Directory('packages/simple_torrent_windows');
    final source = File('${packageRoot.path}/windows/simple_torrent_plugin.cpp')
        .readAsStringSync();

    expect(source, contains('metadata_buffer_.insert_or_assign'));
    expect(source, contains('while (!metadata_buffer_.empty())'));
    expect(source, contains('metadata_sink_->Success'));
  });

  test('finalise is worker-owned and completes on the platform dispatcher', () {
    final packageRoot = Directory('windows').existsSync()
        ? Directory.current
        : Directory('packages/simple_torrent_windows');
    final source = File('${packageRoot.path}/windows/simple_torrent_plugin.cpp')
        .readAsStringSync();
    final header = File('${packageRoot.path}/windows/simple_torrent_plugin.h')
        .readAsStringSync();

    expect(header, contains('std::shared_ptr<NativeState> native_state_'));
    expect(source, contains('QueueFinalise(id, std::move(result))'));

    final workerStart = source.indexOf(
      'struct SimpleTorrentPlugin::NativeState',
    );
    final completionStart = source.indexOf(
      'void SimpleTorrentPlugin::RegisterWithRegistrar',
      workerStart,
    );
    final workerSource = source.substring(workerStart, completionStart);
    expect(workerSource, contains('std::enable_shared_from_this'));
    expect(
      workerSource,
      contains('std::thread worker([state = std::move(state)]'),
    );
    expect(workerSource, contains('worker.detach()'));
    expect(workerSource, contains('simple_torrent_manager_finalise'));
    expect(workerSource, contains('DispatchFinaliseCompletion'));
    expect(workerSource, isNot(contains('MethodResult')));

    final queueStart = source.indexOf(
      'void SimpleTorrentPlugin::QueueFinalise(',
      completionStart,
    );
    final completionQueueStart = source.indexOf(
      'void SimpleTorrentPlugin::QueueFinaliseCompletion(',
      queueStart,
    );
    final queueSource = source.substring(queueStart, completionQueueStart);
    expect(queueSource, contains('finalise_results_.emplace'));
    expect(queueSource, contains('native_state->EnqueueFinalise'));

    final handlerStart = source.indexOf(
      'std::optional<LRESULT> SimpleTorrentPlugin::HandleWindowMessage',
    );
    final drainEventsStart = source.indexOf(
      'void SimpleTorrentPlugin::DrainEvents()',
      handlerStart,
    );
    final handlerSource = source.substring(handlerStart, drainEventsStart);
    expect(handlerSource, contains('DrainFinaliseCompletions()'));
    final drainStart = source.indexOf(
      'void SimpleTorrentPlugin::DrainFinaliseCompletions()',
    );
    final cancelStart = source.indexOf(
      'void SimpleTorrentPlugin::CancelPendingFinaliseResults()',
      drainStart,
    );
    final drainSource = source.substring(drainStart, cancelStart);
    expect(drainSource, contains('finalise_results_.find'));
    expect(drainSource, contains('Complete(completion.code, result.get())'));
  });

  test(
    'plugin destruction cancels results and delegates teardown without waiting',
    () {
      final packageRoot = Directory('windows').existsSync()
          ? Directory.current
          : Directory('packages/simple_torrent_windows');
      final source = File(
        '${packageRoot.path}/windows/simple_torrent_plugin.cpp',
      ).readAsStringSync();
      final destructorStart = source.indexOf(
        'SimpleTorrentPlugin::~SimpleTorrentPlugin()',
      );
      final callbacksStart = source.indexOf(
        'void SimpleTorrentPlugin::OnStats',
        destructorStart,
      );
      final destructorSource = source.substring(
        destructorStart,
        callbacksStart,
      );

      final invalidate = destructorSource.indexOf('InvalidatePlugin()');
      final cancel = destructorSource.indexOf('CancelPendingFinaliseResults()');
      final shutdown = destructorSource.indexOf('Shutdown()');
      expect(invalidate, greaterThanOrEqualTo(0));
      expect(cancel, greaterThan(invalidate));
      expect(shutdown, greaterThan(cancel));
      expect(destructorSource, isNot(contains('.join()')));
      expect(
        destructorSource,
        isNot(contains('simple_torrent_manager_destroy')),
      );
    },
  );

  test(
    'callback bridge is invalidated and manager is destroyed exactly once',
    () {
      final packageRoot = Directory('windows').existsSync()
          ? Directory.current
          : Directory('packages/simple_torrent_windows');
      final source = File(
        '${packageRoot.path}/windows/simple_torrent_plugin.cpp',
      ).readAsStringSync();
      final stateStart = source.indexOf(
        'struct SimpleTorrentPlugin::NativeState',
      );
      final registerStart = source.indexOf(
        'void SimpleTorrentPlugin::RegisterWithRegistrar',
        stateStart,
      );
      final stateSource = source.substring(stateStart, registerStart);

      expect(stateSource, contains('std::lock_guard lock(callback_mutex_)'));
      expect(stateSource, contains('plugin_ = nullptr'));
      expect(stateSource, contains('if (plugin_ != nullptr)'));
      expect(source, contains('static_cast<NativeState*>(user_data)'));
      expect(stateSource, contains('manager_.exchange(nullptr'));
      expect(stateSource, contains('DestroyManager();'));
      expect(
        'simple_torrent_manager_destroy'.allMatches(source).length,
        1,
        reason: 'the atomic exchange owns the sole native destruction call',
      );
    },
  );

  test(
    'teardown cancellation owns MethodResults only on the platform object',
    () {
      final packageRoot = Directory('windows').existsSync()
          ? Directory.current
          : Directory('packages/simple_torrent_windows');
      final source = File(
        '${packageRoot.path}/windows/simple_torrent_plugin.cpp',
      ).readAsStringSync();
      final header = File('${packageRoot.path}/windows/simple_torrent_plugin.h')
          .readAsStringSync();
      final cancelStart = source.indexOf(
        'void SimpleTorrentPlugin::CancelPendingFinaliseResults()',
      );
      final postStart = source.indexOf(
        'void SimpleTorrentPlugin::PostPlatformMessage()',
        cancelStart,
      );
      final cancelSource = source.substring(cancelStart, postStart);

      expect(header, contains('finalise_results_'));
      expect(cancelSource, contains('item.second->Error("not_initialized"'));
      expect(cancelSource, contains('finalise_results_.clear()'));
    },
  );
}
