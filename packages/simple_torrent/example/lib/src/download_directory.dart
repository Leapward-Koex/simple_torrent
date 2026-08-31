import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class ExampleDownloadDirectory {
  Future<String> getDefaultPath();

  /// Optional human-only flow. Automated tests inject an implementation and
  /// never invoke a platform picker or permission dialog.
  Future<String?> pickPath();
}

class AppPrivateDownloadDirectory implements ExampleDownloadDirectory {
  const AppPrivateDownloadDirectory();

  @override
  Future<String> getDefaultPath() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'simple_torrent_example', 'downloads'),
    );
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> pickPath() => FilePicker.getDirectoryPath(
    dialogTitle: 'Choose a torrent download directory',
  );
}

class FixedDownloadDirectory implements ExampleDownloadDirectory {
  const FixedDownloadDirectory(this.path, {this.pickedPath});

  final String path;
  final String? pickedPath;

  @override
  Future<String> getDefaultPath() async => path;

  @override
  Future<String?> pickPath() async => pickedPath;
}
