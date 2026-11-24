import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import '../../models/network_connection.dart';
import '../../models/vfs_node.dart';
import '../log_service.dart';
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

  Future<void> _ensureDirectoryExists(SftpClient sftp, String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    String current = path.startsWith('/') ? '/' : '';
    for (final seg in segments) {
      current = current == '/' ? '/$seg' : (current.isEmpty ? seg : '$current/$seg');
      try {
        await sftp.mkdir(current);
      } catch (_) {}
    }
  }

  Future<bool> writeLocalFile(
    String remotePath,
    File localFile, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    SftpFile? sftpFile;
    try {
      final sftp = await _getSftp();
      final totalBytes = await localFile.length();

      final parent = p.dirname(remotePath);
      if (parent.isNotEmpty && parent != '/' && parent != '.') {
        await _ensureDirectoryExists(sftp, parent);
      }

      sftpFile = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.truncate | SftpFileOpenMode.write,
      );

      int offset = 0;
      final stream = localFile.openRead();
      await for (final chunk in stream) {
        if (isCanceled?.call() == true) {
          throw Exception('Transfer canceled by user');
        }
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await sftpFile.write(Stream.value(bytes), offset: offset).done;
        offset += bytes.length;
        onProgress?.call(offset, totalBytes);
      }

      await sftpFile.close();
      sftpFile = null;
      return true;
    } catch (e, st) {
      LogService.instance.error('SFTP_VFS', 'writeLocalFile failed for $remotePath: $e', e, st);
      if (sftpFile != null) {
        try {
          await sftpFile.close();
        } catch (_) {}
      }
      return false;
    }
  }

  Future<bool> readToLocalFile(
    String remotePath,
    File localFile, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    SftpFile? sftpFile;
    IOSink? sink;
    try {
      final sftp = await _getSftp();
      final stat = await sftp.stat(remotePath);
      final totalBytes = stat.size ?? 0;

      await localFile.parent.create(recursive: true);
      sink = localFile.openWrite();
      sftpFile = await sftp.open(remotePath, mode: SftpFileOpenMode.read);

      await for (final chunk in sftpFile.read(
        onProgress: (bytesRead) {
          onProgress?.call(bytesRead, totalBytes);
        },
      )) {
        if (isCanceled?.call() == true) {
          throw Exception('Transfer canceled by user');
        }
        sink.add(chunk);
      }

      await sink.flush();
      await sink.close();
      sink = null;
      await sftpFile.close();
      sftpFile = null;
      return true;
    } catch (e, st) {
      LogService.instance.error('SFTP_VFS', 'readToLocalFile failed for $remotePath: $e', e, st);
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (sftpFile != null) {
        try {
          await sftpFile.close();
        } catch (_) {}
      }
      return false;
    }
  }

  void dispose() {
    _sftp?.close();
    _sftp = null;
    _client?.close();
    _client = null;
  }

  @override
  Future<String> getPlaybackUri(String path) async {
    // sftp streaming uri format for mpv
    if (connection.username.isNotEmpty) {
      return 'sftp://${Uri.encodeComponent(connection.username)}:${Uri.encodeComponent(connection.password)}@${connection.host}:${connection.port}$path';
    }
    return 'sftp://${connection.host}:${connection.port}$path';
  }
}
