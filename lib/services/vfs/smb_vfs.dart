import 'dart:async';
import 'dart:io';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../models/network_connection.dart';
import '../../models/vfs_node.dart';
import '../log_service.dart';
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

    LogService.instance.info('SMB', 'Connecting to SMB host ${connection.host}, share: $shareName');
    final pool = await Smb2Pool.connect(
      host: connection.host,
      share: shareName,
      user: connection.isAnonymous || connection.username.isEmpty ? null : connection.username,
      password: connection.isAnonymous || connection.password.isEmpty ? null : connection.password,
      workers: 4,
    );
    _activePools[shareName] = pool;
    LogService.instance.info('SMB', 'Connected successfully to share: $shareName');
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
      final isRange = rangeHeader != null && rangeHeader.startsWith('bytes=');

      int start = 0;
      int end = totalSize - 1;

      if (isRange) {
        final rParts = rangeHeader.substring(6).split('-');
        if (rParts.isNotEmpty && rParts[0].isNotEmpty) {
          start = int.tryParse(rParts[0]) ?? 0;
        }
        if (rParts.length > 1 && rParts[1].isNotEmpty) {
          end = int.tryParse(rParts[1]) ?? (totalSize - 1);
        }
      }

      final contentLength = (end - start) + 1;
      final response = request.response;

      // Determine accurate MIME content type
      final ext = p.extension(filePath).toLowerCase();
      ContentType contentType;
      if (ext == '.jpg' || ext == '.jpeg') {
        contentType = ContentType('image', 'jpeg');
      } else if (ext == '.png') {
        contentType = ContentType('image', 'png');
      } else if (ext == '.webp') {
        contentType = ContentType('image', 'webp');
      } else if (ext == '.gif') {
        contentType = ContentType('image', 'gif');
      } else if (ext == '.bmp') {
        contentType = ContentType('image', 'bmp');
      } else if (ext == '.mp4' || ext == '.m4v') {
        contentType = ContentType('video', 'mp4');
      } else if (ext == '.mkv') {
        contentType = ContentType('video', 'x-matroska');
      } else if (ext == '.webm') {
        contentType = ContentType('video', 'webm');
      } else if (ext == '.avi') {
        contentType = ContentType('video', 'x-msvideo');
      } else if (ext == '.mov') {
        contentType = ContentType('video', 'quicktime');
      } else if (ext == '.wmv') {
        contentType = ContentType('video', 'x-ms-wmv');
      } else if (ext == '.flv') {
        contentType = ContentType('video', 'x-flv');
      } else if (ext == '.ts' || ext == '.m2ts' || ext == '.mts') {
        contentType = ContentType('video', 'mp2t');
      } else if (ext == '.vob') {
        contentType = ContentType('video', 'x-ms-vob');
      } else if (ext == '.3gp') {
        contentType = ContentType('video', '3gpp');
      } else if (ext == '.ogv') {
        contentType = ContentType('video', 'ogg');
      } else if (ext == '.mpg' || ext == '.mpeg') {
        contentType = ContentType('video', 'mpeg');
      } else if (ext == '.mp3') {
        contentType = ContentType('audio', 'mpeg');
      } else if (ext == '.flac') {
        contentType = ContentType('audio', 'flac');
      } else if (ext == '.wav') {
        contentType = ContentType('audio', 'wav');
      } else {
        contentType = ContentType('application', 'octet-stream');
      }

      response.headers.contentType = contentType;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set('Access-Control-Allow-Origin', '*');

      if (isRange) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalSize');
      } else {
        response.statusCode = HttpStatus.ok;
      }
      response.headers.contentLength = contentLength;

      bool clientClosed = false;
      response.done.catchError((_) {
        clientClosed = true;
      });

      // Stream in 128KB chunks for instant seeking
      const chunkSize = 128 * 1024;
      int current = start;

      while (current <= end && !clientClosed) {
        final toRead = (end - current + 1).clamp(0, chunkSize);
        final bytes = await pool.readFileRange(filePath, offset: current, length: toRead);
        if (bytes.isEmpty || clientClosed) break;
        try {
          response.add(bytes);
          await response.flush();
        } catch (_) {
          break; // Client aborted/closed connection
        }
        current += bytes.length;
      }

      if (!clientClosed) {
        try {
          await response.close();
        } catch (_) {}
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
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
    // Try share enumeration with 4s timeout
    if (_defaultShare.isEmpty && cleanPath.isEmpty) {
      try {
        final shares = await Smb2Pool.listSharesOn(
          host: connection.host,
          user: connection.isAnonymous || connection.username.isEmpty ? null : connection.username,
          password: connection.isAnonymous || connection.password.isEmpty ? null : connection.password,
          timeoutSeconds: 4,
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
        } else {
          throw Exception('No accessible shares found on ${connection.host}. Please verify permissions or specify a share name.');
        }
      } catch (e) {
        throw Exception('Cannot connect to SMB server at ${connection.host}:${connection.port}. Check host IP, network, and credentials.');
      }
    }

    // Determine target share and subpath
    final (shareName, subPath) = _resolveShareAndSub(cleanPath);

    final List<VfsNode> nodes = [];
    try {
      final pool = await _getPoolForShare(shareName);
      final list = await pool.listDirectory(subPath);

      for (final item in list) {
        if (item.name == '.' || item.name == '..') continue;

        final itemFullPath = _defaultShare.isNotEmpty
            ? (subPath.isEmpty ? item.name : '$subPath/${item.name}')
            : (subPath.isEmpty ? '$shareName/${item.name}' : '$shareName/$subPath/${item.name}');

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

  @visibleForTesting
  (String, String) resolveShareAndSub(String remotePath) => _resolveShareAndSub(remotePath);

  (String, String) _resolveShareAndSub(String remotePath) {
    var clean = remotePath.trim();
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }

    if (clean.isEmpty) {
      final share = _defaultShare.isNotEmpty ? _defaultShare : 'DATA';
      return (share, '');
    }

    final segments = clean.split('/').where((s) => s.isNotEmpty).toList();
    if (_defaultShare.isNotEmpty) {
      if (segments.isNotEmpty && segments.first.toLowerCase() == _defaultShare.toLowerCase()) {
        final sub = segments.skip(1).join('/');
        return (_defaultShare, sub);
      } else {
        return (_defaultShare, clean);
      }
    } else {
      final share = segments.first;
      final sub = segments.skip(1).join('/');
      return (share, sub);
    }
  }

  Future<void> _ensureDirectoryExists(Smb2Pool pool, String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    String current = '';
    for (final seg in segments) {
      current = current.isEmpty ? seg : '$current/$seg';
      try {
        await pool.mkdir(current);
      } catch (_) {
        // Ignored if directory already exists
      }
    }
  }

  @override
  Future<bool> createDirectory(String parentPath, String dirName) async {
    try {
      final full = parentPath.isEmpty ? dirName : p.join(parentPath, dirName);
      final (share, sub) = _resolveShareAndSub(full);
      final pool = await _getPoolForShare(share);
      await _ensureDirectoryExists(pool, sub);
      return true;
    } catch (e, st) {
      LogService.instance.error('SMB_VFS', 'Failed to create directory $dirName in $parentPath: $e', e, st);
      return false;
    }
  }

  @override
  Future<bool> rename(String path, String newName) async {
    try {
      final (share, sub) = _resolveShareAndSub(path);
      final targetSub = p.join(p.dirname(sub), newName);
      final pool = await _getPoolForShare(share);
      await pool.rename(sub, targetSub);
      return true;
    } catch (e, st) {
      LogService.instance.error('SMB_VFS', 'Failed to rename $path to $newName: $e', e, st);
      return false;
    }
  }

  @override
  Future<bool> delete(String path, {bool moveToTrash = true}) async {
    try {
      final (share, sub) = _resolveShareAndSub(path);
      if (sub.isEmpty) return false;

      final pool = await _getPoolForShare(share);
      await _deleteRecursive(pool, sub);
      return true;
    } catch (e, st) {
      LogService.instance.error('SMB_VFS', 'Failed to delete $path: $e', e, st);
      return false;
    }
  }

  Future<void> _deleteRecursive(Smb2Pool pool, String subPath) async {
    final stat = await pool.stat(subPath);
    if (stat.isDirectory) {
      final children = await pool.listDirectory(subPath);
      for (final child in children) {
        if (child.name == '.' || child.name == '..') continue;
        final childSub = subPath.isEmpty ? child.name : '$subPath/${child.name}';
        await _deleteRecursive(pool, childSub);
      }
      await pool.rmdir(subPath);
    } else {
      await pool.deleteFile(subPath);
    }
  }

  Future<bool> writeLocalFile(
    String remotePath,
    File localFile, {
    void Function(int sent, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    Smb2PoolHandle? handle;
    Smb2Pool? pool;
    try {
      final (share, sub) = _resolveShareAndSub(remotePath);
      pool = await _getPoolForShare(share);
      final totalBytes = await localFile.length();

      LogService.instance.info('SMB_VFS', 'Starting streaming upload to "$share/$sub" ($totalBytes bytes)');

      final parent = p.dirname(sub);
      if (parent.isNotEmpty && parent != '.' && parent != '/') {
        await _ensureDirectoryExists(pool, parent);
      }

      handle = await pool.openFileWrite(sub);
      try {
        await pool.ftruncateHandle(handle, 0);
      } catch (_) {}

      int offset = 0;
      final stream = localFile.openRead();
      await for (final chunk in stream) {
        if (isCanceled?.call() == true) {
          LogService.instance.warn('SMB_VFS', 'Transfer canceled by user for $sub');
          throw Exception('Transfer canceled by user');
        }

        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await pool.writeToHandle(handle, bytes, offset: offset);
        offset += bytes.length;
        onProgress?.call(offset, totalBytes);
      }

      await pool.closeHandle(handle);
      handle = null;
      LogService.instance.info('SMB_VFS', 'Streaming upload completed for "$share/$sub" ($offset / $totalBytes bytes)');
      return true;
    } catch (e, st) {
      LogService.instance.error('SMB_VFS', 'writeLocalFile error for $remotePath: $e', e, st);
      if (handle != null && pool != null) {
        try {
          await pool.closeHandle(handle);
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
    IOSink? sink;
    try {
      final (share, sub) = _resolveShareAndSub(remotePath);
      final pool = await _getPoolForShare(share);

      await localFile.parent.create(recursive: true);
      sink = localFile.openWrite();

      await for (final chunk in pool.streamFile(
        sub,
        onProgress: onProgress,
        isCanceled: isCanceled,
      )) {
        sink.add(chunk);
      }

      await sink.flush();
      await sink.close();
      sink = null;
      return true;
    } catch (e, st) {
      LogService.instance.error('SMB_VFS', 'readToLocalFile error for $remotePath: $e', e, st);
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
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
