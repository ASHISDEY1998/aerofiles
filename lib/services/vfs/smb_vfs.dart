import 'dart:async';
import 'dart:io';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:path/path.dart' as p;
import '../../models/network_connection.dart';
import '../../models/vfs_node.dart';
import 'vfs_provider.dart';

class SmbVfs implements VfsProvider {
  final NetworkConnection connection;
  final Map<String, Smb2Pool> _activePools = {};
  HttpServer? _streamServer;
  int _streamPort = 8999;
  String _defaultShare = '';

  SmbVfs(this.connection) {
    String path = connection.path.trim();
    if (path.startsWith('/')) path = path.substring(1);
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      _defaultShare = segments.first;
    }
  }

  @override
  String get providerId => connection.id;

  @override
  String get displayName => connection.name;

  @override
  String get rootPath => '';

  Future<void> connect() async {
    await _startStreamingBridge();
  }

  Future<Smb2Pool> _getPoolForShare(String shareName) async {
    if (_activePools.containsKey(shareName)) {
      return _activePools[shareName]!;
    }

    final pool = await Smb2Pool.connect(
      host: connection.host,
      share: shareName,
      user: connection.isAnonymous || connection.username.isEmpty ? null : connection.username,
      password: connection.isAnonymous || connection.password.isEmpty ? null : connection.password,
      workers: 2,
    );
    _activePools[shareName] = pool;
    return pool;
  }

  Future<void> _startStreamingBridge() async {
    if (_streamServer != null) return;
    try {
      _streamServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _streamPort = _streamServer!.port;
      _streamServer!.listen(_handleStreamRequest);
    } catch (_) {}
  }

  Future<void> _handleStreamRequest(HttpRequest request) async {
    final rawPath = request.uri.queryParameters['path'];
    if (rawPath == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final clean = rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
    final parts = clean.split('/');
    if (parts.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final shareName = _defaultShare.isNotEmpty ? _defaultShare : parts.first;
    final filePath = _defaultShare.isNotEmpty ? clean : parts.skip(1).join('/');

    try {
      final pool = await _getPoolForShare(shareName);
      final totalSize = await pool.fileSize(filePath);
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      int start = 0;
      int end = totalSize - 1;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final rParts = rangeHeader.substring(6).split('-');
        if (rParts.isNotEmpty && rParts[0].isNotEmpty) {
          start = int.tryParse(rParts[0]) ?? 0;
        }
        if (rParts.length > 1 && rParts[1].isNotEmpty) {
          end = int.tryParse(rParts[1]) ?? (totalSize - 1);
        }
      }

      final contentLength = end - start + 1;
      final response = request.response;

      response.statusCode = HttpStatus.partialContent;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalSize');
      response.headers.contentLength = contentLength;
      response.headers.contentType = ContentType('video', 'mp4');

      // Stream in 128KB chunks for instant seeking
      const chunkSize = 128 * 1024;
      int current = start;

      while (current <= end) {
        final toRead = (end - current + 1).clamp(0, chunkSize);
        final bytes = await pool.readFileRange(filePath, offset: current, length: toRead);
        if (bytes.isEmpty) break;
        response.add(bytes);
        current += bytes.length;
      }

      await response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  @override
  Future<List<VfsNode>> listDirectory(String path) async {
    await connect();

    String cleanPath = path.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);

    // If no default share configured AND at root level:
    // Try share enumeration with quick 3s timeout
    if (_defaultShare.isEmpty && cleanPath.isEmpty) {
      try {
        final shares = await Smb2Pool.listSharesOn(
          host: connection.host,
          user: connection.isAnonymous || connection.username.isEmpty ? null : connection.username,
          password: connection.isAnonymous || connection.password.isEmpty ? null : connection.password,
          timeoutSeconds: 3,
        );

        final List<VfsNode> shareNodes = [];
        for (final s in shares) {
          // Skip IPC$ and administrative hidden shares
          if (s.name == 'IPC\$' || s.name.endsWith(r'$')) continue;
          shareNodes.add(
            VfsNode(
              path: s.name,
              name: s.name,
              size: 0,
              isDirectory: true,
              modified: DateTime.now(),
              remoteStorageId: connection.id,
            ),
          );
        }
        if (shareNodes.isNotEmpty) {
          return shareNodes;
        }
      } catch (_) {}

      // Fallback: If share listing failed or returned no public shares (e.g. guest mode or restricted NetShareEnum),
      // present known storage shares for this server
      final List<VfsNode> fallbackShares = [];
      const known = ['Storage Drive HDD', 'ZimaOS-HD', 'DATA'];
      for (final name in known) {
        fallbackShares.add(
          VfsNode(
            path: name,
            name: name,
            size: 0,
            isDirectory: true,
            modified: DateTime.now(),
            remoteStorageId: connection.id,
          ),
        );
      }
      return fallbackShares;
    }

    // Determine target share and subpath
    String shareName;
    String subPath;

    if (_defaultShare.isNotEmpty) {
      shareName = _defaultShare;
      subPath = cleanPath;
    } else {
      final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        shareName = 'DATA';
        subPath = '';
      } else {
        shareName = segments.first;
        subPath = segments.skip(1).join('/');
      }
    }

    final List<VfsNode> nodes = [];
    try {
      final pool = await _getPoolForShare(shareName);
      final list = await pool.listDirectory(subPath);

      for (final item in list) {
        if (item.name == '.' || item.name == '..') continue;

        final itemFullPath = _defaultShare.isNotEmpty
            ? p.join(subPath, item.name)
            : p.join(shareName, subPath, item.name);

        nodes.add(
          VfsNode(
            path: itemFullPath,
            name: item.name,
            size: item.size,
            isDirectory: item.isDirectory,
            modified: item.stat.modified,
            remoteStorageId: connection.id,
          ),
        );
      }

      nodes.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    } catch (_) {
    }

    return nodes;
  }

  @override
  Future<VfsNode?> getMetadata(String path) async {
    return null;
  }

  @override
  Future<bool> createDirectory(String parentPath, String dirName) async {
    try {
      final clean = p.join(parentPath, dirName);
      final segments = clean.split('/').where((s) => s.isNotEmpty).toList();
      final share = _defaultShare.isNotEmpty ? _defaultShare : segments.first;
      final sub = _defaultShare.isNotEmpty ? clean : segments.skip(1).join('/');

      final pool = await _getPoolForShare(share);
      await pool.mkdir(sub);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> rename(String path, String newName) async {
    try {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      final share = _defaultShare.isNotEmpty ? _defaultShare : segments.first;
      final sub = _defaultShare.isNotEmpty ? path : segments.skip(1).join('/');
      final targetSub = p.join(p.dirname(sub), newName);

      final pool = await _getPoolForShare(share);
      await pool.rename(sub, targetSub);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String path, {bool moveToTrash = true}) async {
    try {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      final share = _defaultShare.isNotEmpty ? _defaultShare : segments.first;
      final sub = _defaultShare.isNotEmpty ? path : segments.skip(1).join('/');

      final pool = await _getPoolForShare(share);
      final stat = await pool.stat(sub);
      if (stat.isDirectory) {
        await pool.rmdir(sub);
      } else {
        await pool.deleteFile(sub);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> writeLocalFile(String remotePath, File localFile) async {
    try {
      final segments = remotePath.split('/').where((s) => s.isNotEmpty).toList();
      final share = _defaultShare.isNotEmpty ? _defaultShare : segments.first;
      final sub = _defaultShare.isNotEmpty ? remotePath : segments.skip(1).join('/');

      final pool = await _getPoolForShare(share);
      final bytes = await localFile.readAsBytes();
      await pool.writeFile(sub, bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> readToLocalFile(String remotePath, File localFile) async {
    try {
      final segments = remotePath.split('/').where((s) => s.isNotEmpty).toList();
      final share = _defaultShare.isNotEmpty ? _defaultShare : segments.first;
      final sub = _defaultShare.isNotEmpty ? remotePath : segments.skip(1).join('/');

      final pool = await _getPoolForShare(share);
      final bytes = await pool.readFile(sub);
      await localFile.writeAsBytes(bytes);
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
    await _startStreamingBridge();
    return 'http://127.0.0.1:$_streamPort/stream?path=${Uri.encodeComponent(path)}';
  }

  void dispose() {
    _streamServer?.close(force: true);
    _streamServer = null;
    for (final pool in _activePools.values) {
      pool.disconnect();
    }
    _activePools.clear();
  }
}
