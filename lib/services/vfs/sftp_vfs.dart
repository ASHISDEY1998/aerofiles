import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import '../../models/network_connection.dart';
import '../../models/vfs_node.dart';
import 'vfs_provider.dart';

class SftpVfs implements VfsProvider {
  final NetworkConnection connection;
  SSHClient? _client;
  SftpClient? _sftp;

  SftpVfs(this.connection);

  @override
  String get providerId => connection.id;

  @override
  String get displayName => connection.name;

  @override
  String get rootPath => connection.path.isNotEmpty ? connection.path : '/';

  Future<SftpClient> _getSftp() async {
    if (_sftp != null) return _sftp!;

    final socket = await SSHSocket.connect(
      connection.host,
      connection.port,
      timeout: const Duration(seconds: 10),
    );

    _client = SSHClient(
      socket,
      username: connection.username,
      onPasswordRequest: () => connection.password,
    );

    _sftp = await _client!.sftp();
    return _sftp!;
  }

  @override
  Future<List<VfsNode>> listDirectory(String path) async {
    final List<VfsNode> nodes = [];
    try {
      final sftp = await _getSftp();
      final items = await sftp.listdir(path);

      for (final item in items) {
        final name = item.filename;
        if (name == '.' || name == '..') continue;

        final isDir = item.attr.isDirectory;
        nodes.add(
          VfsNode(
            path: p.join(path, name),
            name: name,
            size: item.attr.size ?? 0,
            isDirectory: isDir,
            modified: DateTime.fromMillisecondsSinceEpoch((item.attr.modifyTime ?? 0) * 1000),
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
  Future<VfsNode?> getMetadata(String path) async => null;

  @override
  Future<bool> createDirectory(String parentPath, String dirName) async {
    try {
      final sftp = await _getSftp();
      await sftp.mkdir(p.join(parentPath, dirName));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> rename(String path, String newName) async {
    try {
      final sftp = await _getSftp();
      await sftp.rename(path, p.join(p.dirname(path), newName));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String path, {bool moveToTrash = true}) async {
    try {
      final sftp = await _getSftp();
      final stat = await sftp.stat(path);
      if (stat.isDirectory) {
        await sftp.rmdir(path);
      } else {
        await sftp.remove(path);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> copy(String sourcePath, String destPath, {void Function(double)? onProgress}) async => false;

  @override
  Future<bool> move(String sourcePath, String destPath, {void Function(double)? onProgress}) async => false;

  @override
  Future<String> getPlaybackUri(String path) async {
    // sftp streaming uri format for mpv
    if (connection.username.isNotEmpty) {
      return 'sftp://${Uri.encodeComponent(connection.username)}:${Uri.encodeComponent(connection.password)}@${connection.host}:${connection.port}$path';
    }
    return 'sftp://${connection.host}:${connection.port}$path';
  }
}
