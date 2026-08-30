import 'dart:async';

import 'package:flutter/material.dart';

import 'src/download_directory.dart';
import 'src/example_controller.dart';
import 'src/example_models.dart';
import 'src/torrent_service.dart';

class ExampleKeys {
  const ExampleKeys._();

  static const magnetField = ValueKey('magnet-field');
  static const downloadPathField = ValueKey('download-path-field');
  static const pickDirectoryButton = ValueKey('pick-directory-button');
  static const startMagnetButton = ValueKey('start-magnet-button');
  static const suspendTransfersButton = ValueKey('suspendTransfersButton');
  static const resumeTransfersButton = ValueKey('resumeTransfersButton');
  static const refreshButton = ValueKey('refresh-button');
  static const initializationStatus = ValueKey('initialization-status');
  static const transfersSuspendedStatus = ValueKey(
    'transfersSuspendedStatus',
  );
  static const actionStatus = ValueKey('action-status');
  static const stateStatus = ValueKey('state-status');
  static const progressStatus = ValueKey('progress-status');
  static const metadataStatus = ValueKey('metadata-status');
  static const errorStatus = ValueKey('error-status');
  static const activeTorrentCount = ValueKey('active-torrent-count');
  static const emptyState = ValueKey('empty-state');
  static ValueKey<String> torrentCard(int id) => ValueKey('torrent-$id');
  static ValueKey<String> torrentState(int id) => ValueKey('torrent-$id-state');
  static ValueKey<String> torrentProgress(int id) =>
      ValueKey('torrent-$id-progress');
  static ValueKey<String> pauseButton(int id) => ValueKey('torrent-$id-pause');
  static ValueKey<String> resumeButton(int id) =>
      ValueKey('torrent-$id-resume');
  static ValueKey<String> cancelButton(int id) =>
      ValueKey('torrent-$id-cancel');
  static ValueKey<String> finaliseButton(int id) =>
      ValueKey('torrent-$id-finalise');
}

class SimpleTorrentExampleApp extends StatefulWidget {
  const SimpleTorrentExampleApp({super.key, this.controller});

  final ExampleController? controller;

  @override
  State<SimpleTorrentExampleApp> createState() =>
      _SimpleTorrentExampleAppState();
}

class _SimpleTorrentExampleAppState extends State<SimpleTorrentExampleApp> {
  late final ExampleController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        ExampleController(
          service: const SimpleTorrentService(),
          downloadDirectory: const AppPrivateDownloadDirectory(),
        );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'simple_torrent example',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    ),
    home: SimpleTorrentExamplePage(controller: _controller),
  );
}

class SimpleTorrentExamplePage extends StatefulWidget {
  const SimpleTorrentExamplePage({required this.controller, super.key});

  final ExampleController controller;

  @override
  State<SimpleTorrentExamplePage> createState() =>
      _SimpleTorrentExamplePageState();
}

class _SimpleTorrentExamplePageState extends State<SimpleTorrentExamplePage> {
  late final TextEditingController _magnetController;
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _magnetController = TextEditingController(text: widget.controller.magnet);
    _pathController = TextEditingController(
      text: widget.controller.downloadPath,
    );
    widget.controller.addListener(_syncTextControllers);
  }

  void _syncTextControllers() {
    if (_pathController.text != widget.controller.downloadPath) {
      _pathController.value = TextEditingValue(
        text: widget.controller.downloadPath,
        selection: TextSelection.collapsed(
          offset: widget.controller.downloadPath.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncTextControllers);
    _magnetController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('simple_torrent 2.0'),
      actions: [
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Semantics(
            button: true,
            label: 'Refresh active torrents',
            child: IconButton(
              key: ExampleKeys.refreshButton,
              tooltip: 'Refresh active torrents',
              onPressed: widget.controller.isReady && !widget.controller.isBusy
                  ? widget.controller.refresh
                  : null,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => _buildBody(context),
      ),
    ),
  );

  Widget _buildBody(BuildContext context) {
    final torrents = widget.controller.torrents.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: ExampleKeys.magnetField,
            controller: _magnetController,
            onChanged: widget.controller.setMagnet,
            minLines: 2,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Magnet URI',
              helperText: 'Preset to the WIRED public sample torrent',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: ExampleKeys.downloadPathField,
                  controller: _pathController,
                  onChanged: widget.controller.setDownloadPath,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Download directory',
                    helperText:
                        'App-private by default; editable for automation',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Choose an optional download directory',
                child: FilledButton.tonalIcon(
                  key: ExampleKeys.pickDirectoryButton,
                  onPressed: widget.controller.isBusy
                      ? null
                      : widget.controller.pickDownloadDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: 'Start the magnet torrent',
            child: FilledButton.icon(
              key: ExampleKeys.startMagnetButton,
              onPressed: widget.controller.isReady && !widget.controller.isBusy
                  ? widget.controller.startMagnet
                  : null,
              icon: const Icon(Icons.download),
              label: const Text('Start magnet'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Suspend all torrent transfers',
                  child: FilledButton.tonalIcon(
                    key: ExampleKeys.suspendTransfersButton,
                    onPressed:
                        widget.controller.isReady &&
                            !widget.controller.isBusy &&
                            !widget.controller.transfersSuspended
                        ? widget.controller.suspendTransfers
                        : null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Suspend transfers'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Resume all torrent transfers',
                  child: FilledButton.tonalIcon(
                    key: ExampleKeys.resumeTransfersButton,
                    onPressed:
                        widget.controller.isReady &&
                            !widget.controller.isBusy &&
                            widget.controller.transfersSuspended
                        ? widget.controller.resumeTransfers
                        : null,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Resume transfers'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _StatusPanel(controller: widget.controller),
          const SizedBox(height: 12),
          Text(
            'Active torrents: ${torrents.length}',
            key: ExampleKeys.activeTorrentCount,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (torrents.isEmpty)
            const Card(
              key: ExampleKeys.emptyState,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No active torrents')),
              ),
            )
          else
            for (final torrent in torrents)
              _TorrentCard(
                torrent: torrent,
                progress: widget.controller.progress[torrent.id],
                busy: widget.controller.isBusy,
                onPause: () => widget.controller.pause(torrent.id),
                onResume: () => widget.controller.resume(torrent.id),
                onCancel: () => widget.controller.cancel(torrent.id),
                onFinalise: () => widget.controller.finalise(torrent.id),
              ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final ExampleController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Persistent machine-readable torrent status',
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              controller.initializationStatus,
              key: ExampleKeys.initializationStatus,
            ),
            SelectableText(
              controller.transferSuspensionStatus,
              key: ExampleKeys.transfersSuspendedStatus,
            ),
            SelectableText(
              'Action: ${controller.actionStatus}',
              key: ExampleKeys.actionStatus,
            ),
            SelectableText(
              controller.stateStatus,
              key: ExampleKeys.stateStatus,
            ),
            SelectableText(
              controller.progressStatus,
              key: ExampleKeys.progressStatus,
            ),
            SelectableText(
              controller.metadataStatus,
              key: ExampleKeys.metadataStatus,
            ),
            SelectableText(
              'Error: ${controller.lastError.isEmpty ? 'none' : controller.lastError}',
              key: ExampleKeys.errorStatus,
            ),
          ],
        ),
      ),
    ),
  );
}

class _TorrentCard extends StatelessWidget {
  const _TorrentCard({
    required this.torrent,
    required this.progress,
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onFinalise,
  });

  final ExampleTorrent torrent;
  final ExampleProgress? progress;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onFinalise;

  @override
  Widget build(BuildContext context) {
    final state = progress?.state ?? torrent.state;
    final fraction = (progress?.progress ?? 0).clamp(0.0, 1.0).toDouble();
    return Semantics(
      key: ExampleKeys.torrentCard(torrent.id),
      container: true,
      label: 'Torrent ${torrent.id}, ${torrent.displayName}, state $state',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                torrent.displayName.isEmpty
                    ? 'Torrent ${torrent.id}'
                    : torrent.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('State: $state', key: ExampleKeys.torrentState(torrent.id)),
              Text(
                'Progress: ${(fraction * 100).toStringAsFixed(1)}%',
                key: ExampleKeys.torrentProgress(torrent.id),
              ),
              LinearProgressIndicator(value: fraction),
              if (progress != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Verified pieces: ${progress!.pieces}/${progress!.piecesTotal}',
                ),
                Text(
                  'Rates: ↓${_formatBytes(progress!.downloadRate)}/s '
                  '↑${_formatBytes(progress!.uploadRate)}/s',
                ),
                Text('Peers: ${progress!.peers}; seeds: ${progress!.seeds}'),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionButton(
                    key: ExampleKeys.pauseButton(torrent.id),
                    semanticLabel: 'Pause torrent ${torrent.id}',
                    text: 'Pause',
                    onPressed: busy ? null : onPause,
                  ),
                  _ActionButton(
                    key: ExampleKeys.resumeButton(torrent.id),
                    semanticLabel: 'Resume torrent ${torrent.id}',
                    text: 'Resume',
                    onPressed: busy ? null : onResume,
                  ),
                  _ActionButton(
                    key: ExampleKeys.cancelButton(torrent.id),
                    semanticLabel:
                        'Cancel torrent ${torrent.id} and delete files',
                    text: 'Cancel',
                    onPressed: busy ? null : onCancel,
                  ),
                  _ActionButton(
                    key: ExampleKeys.finaliseButton(torrent.id),
                    semanticLabel:
                        'Finalise torrent ${torrent.id} and keep files',
                    text: 'Finalise',
                    onPressed: busy ? null : onFinalise,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.semanticLabel,
    required this.text,
    required this.onPressed,
    super.key,
  });

  final String semanticLabel;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: OutlinedButton(onPressed: onPressed, child: Text(text)),
  );
}
