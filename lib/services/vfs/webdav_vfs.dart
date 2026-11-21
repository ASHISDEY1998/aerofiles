import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../../models/network_connection.dart';
import '../../models/vfs_node.dart';
import 'vfs_provider.dart';

class WebDavVfs implements VfsProvider {
  final NetworkConnection connection;
  late final webdav.Client _client;

  WebDavVfs(this.connection) {
    final scheme = connection.port == 443 ? 'https' : 'http';
    final url = '$scheme://${connection.host}:${connection.port}${connection.path}';
    _client = webdav.newClient(
      url,
      user: connection.username,
      password: connection.password,
      debug: false,
    );
  }

  @override
  String get providerId => connection.id;

  @override
  String get displayName => connection.name;

  @override
  String get rootPath => '/';

  @override
  Future<List<VfsNode>> listDirectory(String path) async {
    final List<VfsNode> nodes = [];
    try {
      final list = await _client.readDir(path);
      for (final item in list) {
        final name = item.name ?? '';
        if (name.isEmpty || name == '.' || name == '..') continue;

        final isDir = item.isDir ?? false;
        nodes.add(
          VfsNode(
            path: item.path ?? p.join(path, name),
            name: name,
            size: item.size ?? 0,
            isDirectory: isDir,
            modified: item.mTime ?? DateTime.now(),
            remoteStorageId: connection.id,
          ),
        );
      }

      nodes.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } catch (_) {}

    return nodes;
  }

  @override
  Future<VfsNode?> getMetadata(String path) async {
    return null;
  }

  @override
  Future<bool> createDirectory(String parentPath, String dirName) async {
    try {
      await _client.mkdir(p.join(parentPath, dirName));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> rename(String path, String newName) async {
    return false;
  }

  @override
  Future<bool> delete(String path, {bool moveToTrash = true}) async {
    try {
      await _client.removeAll(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> copy(String sourcePath, String destPath, {void Function(double)? onProgress}) async {
    return false;
  }

  @override
  Future<bool> move(String sourcePath, String destPath, {void Function(double)? onProgress}) async {
    return false;
  }

  @override
  Future<String> getPlaybackUri(String path) async {
    // Return streaming authenticated HTTP/HTTPS URL for direct playback in libmpv
    final scheme = connection.port == 443 ? 'https' : 'http';
    if (connection.username.isNotEmpty) {
      return '$scheme://${Uri.encodeComponent(connection.username)}:${Uri.encodeComponent(connection.password)}@${connection.host}:${connection.port}$path';
    }
    return '$scheme://${connection.host}:${connection.port}$path';
  }
}
