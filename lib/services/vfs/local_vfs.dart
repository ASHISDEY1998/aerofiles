import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/vfs_node.dart';
import '../recycle_bin_service.dart';
import 'vfs_provider.dart';

class LocalVfs implements VfsProvider {
  final RecycleBinService? recycleBinService;

  LocalVfs({this.recycleBinService});

  @override
  String get providerId => 'local';

  @override
  String get displayName => 'Local Storage';

  @override
  String get rootPath {
    if (Platform.isAndroid) {
      return '/storage/emulated/0';
    } else if (Platform.isMacOS || Platform.isLinux) {
      return Platform.environment['HOME'] ?? '/';
    } else if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    return '/';
  }

  Future<String> getDownloadsPath() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir.path;
    }
    final dir = await getDownloadsDirectory();
    return dir?.path ?? rootPath;
  }

  @override
  Future<List<VfsNode>> listDirectory(String path, {bool showHidden = false}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return [];
    }

    final List<VfsNode> nodes = [];

    try {
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (!showHidden && name.startsWith('.')) continue;

        try {
          final stat = entity.statSync();
          final isDir = stat.type == FileSystemEntityType.directory;
          nodes.add(
            VfsNode(
              path: entity.path,
              name: name,
              size: isDir ? 0 : stat.size,
              isDirectory: isDir,
              modified: stat.modified,
            ),
          );
        } catch (_) {
          // Skip inaccessible or permission restricted items
        }
      }

      // Sort: Folders first, then case-insensitive alphabetical
      nodes.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } catch (e) {
      // Permission or I/O error
    }

    return nodes;
  }

  @override
  Future<VfsNode?> getMetadata(String path) async {
    final file = File(path);
    if (await file.exists()) {
      final stat = await file.stat();
      return VfsNode(
        path: path,
        name: p.basename(path),
        size: stat.size,
        isDirectory: false,
        modified: stat.modified,
      );
    }
    final dir = Directory(path);
    if (await dir.exists()) {
      final stat = await dir.stat();
      return VfsNode(
        path: path,
        name: p.basename(path),
        size: 0,
        isDirectory: true,
        modified: stat.modified,
      );
    }
    return null;
  }

  @override
  Future<bool> createDirectory(String parentPath, String dirName) async {
    try {
      final newDir = Directory(p.join(parentPath, dirName));
      if (!await newDir.exists()) {
        await newDir.create(recursive: true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> rename(String path, String newName) async {
    try {
      final parent = p.dirname(path);
      final target = p.join(parent, newName);
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).rename(target);
      } else {
        await File(path).rename(target);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String path, {bool moveToTrash = true}) async {
    try {
      if (moveToTrash && recycleBinService != null) {
        return await recycleBinService!.moveToTrash(path);
      }

      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      await RecycleBinService.notifyMediaScanner(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> copy(String sourcePath, String destPath, {void Function(double)? onProgress}) async {
    try {
      final isDir = await FileSystemEntity.isDirectory(sourcePath);
      if (isDir) {
        await _copyDirectory(Directory(sourcePath), Directory(destPath));
      } else {
        await File(sourcePath).copy(destPath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(p.join(destination.path, p.basename(entity.path)));
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  @override
  Future<bool> move(String sourcePath, String destPath, {void Function(double)? onProgress}) async {
    try {
      if (await FileSystemEntity.isDirectory(sourcePath)) {
        await Directory(sourcePath).rename(destPath);
      } else {
        await File(sourcePath).rename(destPath);
      }
      return true;
    } catch (_) {
      // Fallback: Copy and Delete
      final copied = await copy(sourcePath, destPath);
      if (copied) {
        await delete(sourcePath, moveToTrash: false);
        return true;
      }
      return false;
    }
  }

  @override
  Future<String> getPlaybackUri(String path) async {
    return path;
  }
}
