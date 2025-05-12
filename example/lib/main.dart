import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:simple_torrent/simple_torrent.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final magnetCtrl = TextEditingController(text: "");
  String outputDir = '/storage/emulated/0/Download';
  final Map<String, TorrentProgress> _progress = {};
  StreamSubscription<TorrentProgress>? sub;

  @override
  void initState() {
    super.initState();
    SimpleTorrent.init(concurrency: 2);
    sub = SimpleTorrent.progressStream.listen((p) {
      setState(() => _progress[p.id] = p);
    });
  }

  Future<void> _pickDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) setState(() => outputDir = dir);
  }

  Future<void> _start() async {
    final magnet = magnetCtrl.text.trim();
    if (magnet.isEmpty) return;
    await SimpleTorrent.start(magnet: magnet, path: outputDir);
    magnetCtrl.clear();
  }

  @override
  void dispose() {
    sub?.cancel();
    magnetCtrl.dispose();
    super.dispose();
  }

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
              TextField(controller: magnetCtrl, decoration: const InputDecoration(labelText: 'Magnet URI', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Save to: $outputDir', overflow: TextOverflow.ellipsis)),
                  TextButton(onPressed: _pickDir, child: const Text('Choose Folder')),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _start, child: const Text('Start Torrent')),
              const Divider(height: 32),
              Expanded(
                child:
                    _progress.isEmpty
                        ? const Center(child: Text('No torrents running'))
                        : ListView(
                          children:
                              _progress.values
                                  .map(
                                    (p) => ListTile(
                                      title: Text(p.id),
                                      subtitle: Text(
                                        '${p.progress.toStringAsFixed(1)} % • '
                                        'peers: ${p.peers} • '
                                        'pieces: ${p.piecesComplete} / ${p.piecesTotal} • '
                                        '${_fmtBytes(p.downloaded)} / '
                                        '${_fmtBytes(p.downloaded + p.left)}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtBytes(int b) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = b.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(1)} ${units[i]}';
  }
}
