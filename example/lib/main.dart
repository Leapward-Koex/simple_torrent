import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:simple_torrent/simple_torrent.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _magnetCtrl = TextEditingController(text: "");
  String _outputDir = '/storage/emulated/0/Download';

  /// id → latest stats
  final Map<int, TorrentStats> _stats = {};
  StreamSubscription<TorrentStats>? _sub;

  @override
  void initState() {
    super.initState();
    // SimpleTorrent.init(concurrency: 4);
    _sub = SimpleTorrent.statsStream.listen((s) {
      setState(() => _stats[s.id] = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _magnetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) setState(() => _outputDir = dir);
  }

  Future<void> _start() async {
    final magnet = _magnetCtrl.text.trim();
    if (magnet.isEmpty) return;
    await SimpleTorrent.start(magnet: magnet, path: _outputDir);
    _magnetCtrl.clear();
  }

  void _pause(int id) => SimpleTorrent.pause(id);
  void _resume(int id) => SimpleTorrent.resume(id);
  void _cancel(int id) => SimpleTorrent.cancel(id);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Torrent Demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('Simple Torrent Demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(controller: _magnetCtrl, decoration: const InputDecoration(labelText: 'Magnet URI', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Save to: $_outputDir', overflow: TextOverflow.ellipsis)),
                  TextButton(onPressed: _pickDir, child: const Text('Choose Folder')),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _start, child: const Text('Start Torrent')),
              const Divider(height: 32),
              Expanded(
                child:
                    _stats.isEmpty
                        ? const Center(child: Text('No torrents running'))
                        : ListView(children: _stats.values.map(_buildTile).toList()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(TorrentStats s) {
    final pct = s.progress.clamp(0, 100);
    return ListTile(
      title: Text('Torrent #${s.id}   $pct%'),
      subtitle: Text(
        '↓ ${_fmtRate(s.downloadRate)} • '
        '↑ ${_fmtRate(s.uploadRate)} • '
        'pieces ${s.pieces}/${s.piecesTotal} • '
        'seeds ${s.seeds} • peers ${s.peers}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (cmd) {
          switch (cmd) {
            case 'pause':
              _pause(s.id);
              break;
            case 'resume':
              _resume(s.id);
              break;
            case 'cancel':
              _cancel(s.id);
              break;
          }
        },
        itemBuilder:
            (c) => [
              const PopupMenuItem(value: 'pause', child: Text('Pause')),
              const PopupMenuItem(value: 'resume', child: Text('Resume')),
              const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
            ],
      ),
    );
  }

  String _fmtRate(int bps) {
    if (bps < 1024) return '$bps B/s';
    const units = ['KB/s', 'MB/s', 'GB/s'];
    double v = bps / 1024;
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }
}
