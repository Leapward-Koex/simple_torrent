import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:simple_torrent/simple_torrent.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Torrent Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SimpleDemoPage(),
    );
  }
}

class SimpleDemoPage extends StatefulWidget {
  const SimpleDemoPage({super.key});

  @override
  State<SimpleDemoPage> createState() => _SimpleDemoPageState();
}

class _SimpleDemoPageState extends State<SimpleDemoPage> {
  static const _bbbMagnet =
      'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fbig-buck-bunny.torrent';

  final _pathController = TextEditingController(
    text:
        Platform.isAndroid
            ? '/storage/emulated/0/Download'
            : Platform.isIOS
            ? 'Documents'
            : Platform.isMacOS
            ? Platform.environment['HOME']! + '/Downloads'
            : '/tmp',
  );
  bool _initialised = false;

  // Live data
  final Map<int, TorrentStats> _stats = {};
  final Map<int, TorrentInfo> _infos = {};
  StreamSubscription<TorrentStats>? _statsSub;
  StreamSubscription<TorrentMetadata>? _metaSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await SimpleTorrent.init(
        config: const TorrentConfig(
          maxTorrents: 3,
          enableDHT: true,
          userAgent: 'SimpleTorrentDemo/1.0',
        ),
      );
      await _loadActive();
      _listenStreams();
      setState(() => _initialised = true);
    } catch (e) {
      _show('Init failed: $e', isError: true);
    }
  }

  void _listenStreams() {
    _statsSub?.cancel();
    _metaSub?.cancel();
    _statsSub = SimpleTorrent.statsStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _stats[s.id] = s;
      });
    });
    _metaSub = SimpleTorrent.metadataStream.listen((m) {
      // Optionally react to metadata; not required for this demo UI
    });
  }

  Future<void> _loadActive() async {
    try {
      final ids = await SimpleTorrent.getActiveTorrentIds();
      final Map<int, TorrentInfo> nextInfos = {};
      for (final id in ids) {
        try {
          final info = await SimpleTorrent.getTorrentInfo(id);
          nextInfos[id] = info;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _infos
            ..clear()
            ..addAll(nextInfos);
        });
      }
    } catch (e) {
      _show('Failed to load active torrents: $e', isError: true);
    }
  }

  String get _downloadPath =>
      _pathController.text.isEmpty
          ? '/storage/emulated/0/Download'
          : _pathController.text;

  Future<void> _pickDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        setState(() {
          _pathController.text = result;
        });
      }
    } catch (e) {
      _show('Failed to pick directory: $e', isError: true);
    }
  }

  Future<void> _startMagnet() async {
    try {
      final id = await SimpleTorrent.start(
        magnet: _bbbMagnet,
        path: _downloadPath,
        displayName: 'Big Buck Bunny (magnet)',
      );
      await _loadActive();
      _show('Started magnet, id=$id');
    } catch (e) {
      _show('Failed: $e', isError: true);
    }
  }

  Future<void> _startFromData() async {
    try {
      final data = await rootBundle.load('assets/big-buck-bunny.torrent');
      final id = await SimpleTorrent.startFromData(
        data: data.buffer.asUint8List(),
        downloadPath: _downloadPath,
        displayName: 'Big Buck Bunny (.torrent data)',
      );
      await _loadActive();
      _show('Started from data, id=$id');
    } catch (e) {
      _show('Failed: $e', isError: true);
    }
  }

  Future<void> _startFromFile() async {
    try {
      final data = await rootBundle.load('assets/big-buck-bunny.torrent');
      final dir = await Directory.systemTemp.createTemp('torrent_');
      final file = File('${dir.path}/big-buck-bunny.torrent');
      await file.writeAsBytes(data.buffer.asUint8List());

      final id = await SimpleTorrent.startFromTorrentFile(
        torrentFilePath: file.path,
        downloadPath: _downloadPath,
        displayName: 'Big Buck Bunny (.torrent file)',
      );
      await _loadActive();
      _show('Started from file, id=$id');
    } catch (e) {
      _show('Failed: $e', isError: true);
    }
  }

  Future<void> _pause(int id) async {
    try {
      await SimpleTorrent.pause(id);
      await _loadActive();
    } catch (e) {
      _show('Pause failed: $e', isError: true);
    }
  }

  Future<void> _resume(int id) async {
    try {
      await SimpleTorrent.resume(id);
      await _loadActive();
    } catch (e) {
      _show('Resume failed: $e', isError: true);
    }
  }

  Future<void> _cancel(int id) async {
    try {
      await SimpleTorrent.cancel(id);
      await _loadActive();
    } catch (e) {
      _show('Cancel failed: $e', isError: true);
    }
  }

  Future<void> _finalise(int id) async {
    try {
      await SimpleTorrent.finalise(id);
      await _loadActive();
    } catch (e) {
      _show('Finalise failed: $e', isError: true);
    }
  }

  void _show(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _infos.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Torrent Demo'),
        actions: [
          IconButton(onPressed: _loadActive, icon: const Icon(Icons.refresh)),
        ],
      ),
      body:
          _initialised
              ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pathController,
                            decoration: const InputDecoration(
                              labelText: 'Download path',
                              hintText: 'Select a directory for downloads',
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _pickDirectory,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Browse'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _startMagnet,
                            child: const Text('Magnet'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _startFromData,
                            child: const Text('.torrent data'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _startFromFile,
                            child: const Text('.torrent file'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Expanded(
                      child:
                          items.isEmpty
                              ? const Center(child: Text('No active torrents'))
                              : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final id = items[index];
                                  final info = _infos[id]!;
                                  final s = _stats[id];
                                  final state = (s?.state ?? info.state).name;
                                  final progress = s?.progress ?? 0.0;
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            info.displayName.isNotEmpty
                                                ? info.displayName
                                                : 'Torrent $id',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text('State: $state'),
                                          Text(
                                            'Progress: ${(progress * 100).toStringAsFixed(1)}%',
                                          ),
                                          const SizedBox(height: 6),
                                          LinearProgressIndicator(
                                            value:
                                                progress
                                                    .clamp(0.0, 1.0)
                                                    .toDouble(),
                                          ),
                                          if (s != null) ...[
                                            Text(
                                              'Speed: ↓${_fmtBytes(s.dlRate)}/s ↑${_fmtBytes(s.ulRate)}/s',
                                            ),
                                            Text(
                                              'Pieces: ${s.pieces}/${s.piecesTotal}',
                                            ),
                                            Text(
                                              'Peers: ${s.peers} (seeds: ${s.seeds})',
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              TextButton(
                                                onPressed: () => _pause(id),
                                                child: const Text('Pause'),
                                              ),
                                              TextButton(
                                                onPressed: () => _resume(id),
                                                child: const Text('Resume'),
                                              ),
                                              TextButton(
                                                onPressed: () => _cancel(id),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () => _finalise(id),
                                                child: const Text('Finalise'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              )
              : const Center(child: CircularProgressIndicator()),
    );
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _statsSub?.cancel();
    _metaSub?.cancel();
    _pathController.dispose();
    super.dispose();
  }
}
