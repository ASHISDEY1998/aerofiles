import 'dart:convert';
import 'dart:io';
import '../../models/aerolink_models.dart';
import '../../models/vfs_node.dart';
import '../log_service.dart';
import 'vfs_provider.dart';

class AeroLinkVfs implements VfsProvider {
  final AeroLinkDevice device;
  final String authToken;

  // Cache share name to share ID mapping
  final Map<String, String> _shareNameToId = {};

  AeroLinkVfs({
    required this.device,
    required this.authToken,
  });

  @override
  String get providerId => 'aerolink_${device.deviceId}';

  @override
  String get displayName => device.deviceName;

  @override
  String get rootPath => '/';

  @override
  Future<List<VfsNode>> listDirectory(String path) async {
    final cleanPath = path.trim();

    // 1. Root Level: List all shared folders exposed by this device
    if (cleanPath == '/' || cleanPath.isEmpty) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);

        final url = Uri.parse('http://${device.ip}:${device.port}/aerolink/shares?auth=$authToken');
        final req = await client.getUrl(url);
        final res = await req.close();

        if (res.statusCode == 200) {
          final body = await utf8.decodeStream(res);
          final list = (jsonDecode(body) as List<dynamic>?) ?? [];
          final nodes = <VfsNode>[];

          _shareNameToId.clear();
          for (final item in list) {
            final id = item['id'] as String? ?? '';
            final name = item['name'] as String? ?? 'Shared Folder';
            final itemCount = (item['itemCount'] as int?) ?? 0;
            _shareNameToId[name] = id;

            nodes.add(
              VfsNode(
                path: '/$name',
                name: name,
                size: itemCount * 1024,
                isDirectory: true,
                modified: DateTime.now(),
                remoteStorageId: providerId,
              ),
            );
          }
          client.close();
          return nodes;
        }
        client.close();
      } catch (e) {
        LogService.instance.warn('AEROLINK_VFS', 'Failed to fetch shares from ${device.deviceName}: $e');
      }
      return [];
    }

    // 2. Subfolder Level: Browse inside a specific share
    try {
      final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return [];

      final shareName = segments.first;
      String? shareId = _shareNameToId[shareName];

      // If shareId not cached, fetch shares first
      if (shareId == null) {
        await listDirectory('/');
        shareId = _shareNameToId[shareName];
      }

      if (shareId == null) return [];

      final subpath = segments.length > 1 ? segments.sublist(1).join('/') : '';

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final uri = Uri.parse(
        'http://${device.ip}:${device.port}/aerolink/browse?shareId=${Uri.encodeComponent(shareId)}&subpath=${Uri.encodeComponent(subpath)}&auth=$authToken',
      );
      final req = await client.getUrl(uri);
      final res = await req.close();

      if (res.statusCode == 200) {
        final body = await utf8.decodeStream(res);
        final list = (jsonDecode(body) as List<dynamic>?) ?? [];
        final nodes = <VfsNode>[];

        for (final item in list) {
          final name = item['name'] as String? ?? '';
          final relPath = item['path'] as String? ?? '';
          final size = (item['size'] as int?) ?? 0;
          final isDir = (item['isDirectory'] as bool?) ?? false;
          final modStr = item['modified'] as String? ?? '';
          final modified = DateTime.tryParse(modStr) ?? DateTime.now();

          nodes.add(
            VfsNode(
              path: '/$shareName/$relPath',
              name: name,
              size: size,
              isDirectory: isDir,
              modified: modified,
              remoteStorageId: providerId,
            ),
          );
        }
        client.close();
        return nodes;
      }
      client.close();
    } catch (e) {
      LogService.instance.warn('AEROLINK_VFS', 'Failed to browse $path: $e');
    }
    return [];
  }

  @override
  Future<String> getPlaybackUri(String path) async {
    // Converts VfsNode path (e.g. /Movies/action/clip.mp4) into authenticated streaming HTTP URL
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';

    final shareName = segments.first;
    final shareId = _shareNameToId[shareName] ?? shareName;
    final relPath = segments.length > 1 ? segments.sublist(1).join('/') : '';

    final streamUrl =
        'http://${device.ip}:${device.port}/aerolink/stream?shareId=${Uri.encodeComponent(shareId)}&path=${Uri.encodeComponent(relPath)}&auth=$authToken';

    LogService.instance.info('AEROLINK_VFS', 'Generated zero-download stream URL: $streamUrl');
    return streamUrl;
  }

  @override
  Future<VfsNode?> getMetadata(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return VfsNode(
        path: '/',
        name: device.deviceName,
        size: 0,
        isDirectory: true,
        modified: DateTime.now(),
        remoteStorageId: providerId,
      );
    }
    final name = segments.last;
    return VfsNode(
      path: path,
      name: name,
      size: 0,
      isDirectory: path.endsWith('/') || segments.length == 1,
      modified: DateTime.now(),
      remoteStorageId: providerId,
    );
  }

  @override
  Future<bool> createDirectory(String parentPath, String dirName) async => false;

  @override
  Future<bool> rename(String path, String newName) async => false;

  @override
  Future<bool> delete(String path, {bool moveToTrash = true}) async => false;

  @override
  Future<bool> copy(String sourcePath, String destPath, {void Function(double)? onProgress}) async => false;

  @override
  Future<bool> move(String sourcePath, String destPath, {void Function(double)? onProgress}) async => false;
}
