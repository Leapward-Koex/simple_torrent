import 'package:flutter/material.dart';
import 'package:simple_torrent/simple_torrent.dart';

void main() {
  runApp(const MyApp());
}

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
      home: const TorrentManagerPage(),
    );
  }
}

class TorrentManagerPage extends StatefulWidget {
  const TorrentManagerPage({super.key});

  @override
  State<TorrentManagerPage> createState() => _TorrentManagerPageState();
}

class _TorrentManagerPageState extends State<TorrentManagerPage> {
  final _magnetController = TextEditingController(text: '');
  final _pathController = TextEditingController(
    text: '/storage/emulated/0/Download',
  );
  final _nameController = TextEditingController();

  List<TorrentInfo> _torrents = [];
  final Map<int, TorrentStats> _stats = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeTorrentManager();
    _listenToStats();
  }

  Future<void> _initializeTorrentManager() async {
    try {
      // Initialize with custom configuration
      await SimpleTorrent.init(
        config: const TorrentConfig(
          maxTorrents: 10,
          maxDownloadRate: 1024, // 1 MB/s
          maxUploadRate: 512, // 512 KB/s
          enableDHT: true,
          userAgent: 'MyTorrentApp/1.0',
        ),
      );

      // Load existing torrents
      await _refreshTorrents();

      setState(() {
        _initialized = true;
      });
    } catch (e) {
      _showError('Failed to initialize: $e');
    }
  }

  void _listenToStats() {
    SimpleTorrent.statsStream.listen((stats) {
      print(
        '📊 Stats update - ID: ${stats.id}, State: ${stats.state.name}, Progress: ${(stats.progress * 100).toStringAsFixed(1)}%',
      );
      setState(() {
        _stats[stats.id] = stats;
      });
    });

    SimpleTorrent.metadataStream.listen((metadata) {
      print('📝 Metadata update - ID: ${metadata.id}, Name: ${metadata.name}');
    });
  }

  Future<void> _refreshTorrents() async {
    try {
      final torrents = await SimpleTorrentHelpers.getAllTorrents();
      setState(() {
        _torrents = torrents;
      });
    } catch (e) {
      _showError('Failed to refresh torrents: $e');
    }
  }

  Future<void> _addTorrent() async {
    if (_magnetController.text.isEmpty || _pathController.text.isEmpty) {
      _showError('Please fill in magnet and path');
      return;
    }

    try {
      final id = await SimpleTorrent.start(
        magnet: _magnetController.text,
        path: _pathController.text,
        displayName: _nameController.text.isEmpty ? null : _nameController.text,
      );

      _magnetController.clear();
      _nameController.clear();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Torrent started with ID: $id')));

      await _refreshTorrents();
    } catch (e) {
      _showError('Failed to start torrent: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Torrent Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTorrents,
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'pauseAll':
                  await SimpleTorrentHelpers.pauseAll();
                  await _refreshTorrents();
                  break;
                case 'resumeAll':
                  await SimpleTorrentHelpers.resumeAll();
                  await _refreshTorrents();
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'pauseAll',
                    child: Text('Pause All'),
                  ),
                  const PopupMenuItem(
                    value: 'resumeAll',
                    child: Text('Resume All'),
                  ),
                ],
          ),
        ],
      ),
      body: _initialized ? _buildBody() : _buildLoading(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTorrentDialog,
        tooltip: 'Add Torrent',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initializing torrent manager...'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_torrents.isEmpty) {
      return const Center(
        child: Text(
          'No torrents active.\nTap + to add a torrent.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: _torrents.length,
      itemBuilder: (context, index) {
        final torrent = _torrents[index];
        final stats = _stats[torrent.id];

        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text(torrent.displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Torrent State: ${torrent.state.name}'),
                if (stats != null) Text('Stats State: ${stats.state.name}'),
                if (stats != null) Text('Progress: ${stats.progress * 100}%'),
                if (stats != null)
                  Text(
                    'Speed: ↓${_formatBytes(stats.dlRate)}/s ↑${_formatBytes(stats.ulRate)}/s',
                  ),
                if (stats != null)
                  Text('Peers: ${stats.peers} (${stats.seeds} seeds)'),
                if (torrent.lastError.isNotEmpty)
                  Text(
                    'Error: ${torrent.lastError}',
                    style: const TextStyle(color: Colors.red),
                  ),
              ],
            ),
            leading: _buildStateIcon(torrent.state),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'pause':
                    await torrent.pause();
                    break;
                  case 'resume':
                    await torrent.resume();
                    break;
                  case 'cancel':
                    await torrent.cancel();
                    break;
                  case 'finalise':
                    await torrent.finalise();
                    break;
                }
                await _refreshTorrents();
              },
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(value: 'pause', child: Text('Pause')),
                    const PopupMenuItem(value: 'resume', child: Text('Resume')),
                    const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                    const PopupMenuItem(
                      value: 'finalise',
                      child: Text('Finalise'),
                    ),
                  ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateIcon(TorrentState state) {
    switch (state) {
      case TorrentState.starting:
        return const Icon(Icons.hourglass_empty, color: Colors.orange);
      case TorrentState.downloadingMetadata:
        return const Icon(Icons.info, color: Colors.blue);
      case TorrentState.downloading:
        return const Icon(Icons.download, color: Colors.green);
      case TorrentState.seeding:
        return const Icon(Icons.upload, color: Colors.purple);
      case TorrentState.paused:
        return const Icon(Icons.pause, color: Colors.grey);
      case TorrentState.error:
        return const Icon(Icons.error, color: Colors.red);
      case TorrentState.stopped:
        return const Icon(Icons.stop, color: Colors.black);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  void _showAddTorrentDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Torrent'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _magnetController,
                  decoration: const InputDecoration(
                    labelText: 'Magnet URI',
                    hintText: 'magnet:?xt=urn:btih:...',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(labelText: 'Download Path'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name (optional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _addTorrent();
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _magnetController.dispose();
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
