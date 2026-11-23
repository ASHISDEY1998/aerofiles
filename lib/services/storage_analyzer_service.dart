import 'dart:collection';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/storage_info.dart';
import '../models/vfs_node.dart';

class StorageAnalyzerService {
  static const MethodChannel _storageChannel = MethodChannel('com.aerofiles.app/storage');

  Future<Map<String, int>> getHardwareStorage({String? path}) async {
    if (Platform.isAndroid) {
      try {
        final res = await _storageChannel.invokeMethod<Map>('getStorageStats', {
          'path': ?path,
        });
        if (res != null) {
          final total = (res['totalBytes'] as num?)?.toInt() ?? 0;
          final used = (res['usedBytes'] as num?)?.toInt() ?? 0;
          final free = (res['freeBytes'] as num?)?.toInt() ?? 0;
          if (total > 0) {
            return {'total': total, 'used': used, 'free': free};
          }
        }
      } catch (_) {}
    }
    return {
      'total': 128 * 1024 * 1024 * 1024,
      'used': 64 * 1024 * 1024 * 1024,
      'free': 64 * 1024 * 1024 * 1024,
    };
  }

  Future<StorageInfo> analyze(String rootPath, {void Function(String currentFolder)? onProgress}) async {
    final hw = await getHardwareStorage(path: rootPath);
    int totalCapacity = hw['total']!;
    int realUsed = hw['used']!;
    int realFree = hw['free']!;

    int videoBytes = 0;
    int imageBytes = 0;
    int audioBytes = 0;
    int docBytes = 0;
    int appBytes = 0;
    int otherBytes = 0;
    int junkBytes = 0;

    final List<VfsNode> largeFiles = [];
    final Map<int, List<VfsNode>> filesBySize = {};

    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) {
      return StorageInfo(
        totalBytes: totalCapacity,
        usedBytes: realUsed,
        freeBytes: realFree,
      );
    }

    // Use robust BFS queue instead of list(recursive: true) to avoid Android/data crash
    final queue = Queue<Directory>();
    queue.add(rootDir);

    // Prioritize main folders first
    final priorityDirs = [
      'DCIM',
      'Download',
      'Pictures',
      'Movies',
      'Music',
      'Documents',
      'Podcasts',
      'Recordings',
    ];
    for (final dirName in priorityDirs) {
      final d = Directory(p.join(rootPath, dirName));
      if (d.existsSync()) queue.add(d);
    }

    final visited = <String>{};

    int itemsScanned = 0;
    const maxItems = 10000;

    while (queue.isNotEmpty && itemsScanned < maxItems) {
      final currentDir = queue.removeFirst();
      final currentPath = currentDir.path;

      if (visited.contains(currentPath)) continue;
      visited.add(currentPath);

      // Skip Android system protected folders that crash directory listing
      if (currentPath.contains('/Android/data') ||
          currentPath.contains('/Android/obb') ||
          currentPath.contains('/.aerofiles_trash') ||
          currentPath.contains('/.aerofiles_vault')) {
        continue;
      }

      try {
        final entities = currentDir.listSync(followLinks: false);
        for (final entity in entities) {
          itemsScanned++;
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (!name.startsWith('.') && name != 'Android') {
              queue.add(entity);
            }
          } else if (entity is File) {
            try {
              final stat = entity.statSync();
              final size = stat.size;
              final name = p.basename(entity.path);

              final node = VfsNode(
                path: entity.path,
                name: name,
                size: size,
                isDirectory: false,
                modified: stat.modified,
              );

              // Categorize
              switch (node.category) {
                case FileCategory.video:
                  videoBytes += size;
                  break;
                case FileCategory.image:
                  imageBytes += size;
                  break;
                case FileCategory.audio:
                  audioBytes += size;
                  break;
                case FileCategory.document:
                  docBytes += size;
                  break;
                case FileCategory.app:
                  appBytes += size;
                  break;
                default:
                  otherBytes += size;
                  break;
              }

              // Detect Junk / Temporary files
              final ext = node.extension;
              if (ext == '.tmp' || ext == '.log' || ext == '.bak' || name.startsWith('cache_')) {
                junkBytes += size;
              }

              // Track large files (> 25 MB)
              if (size > 25 * 1024 * 1024) {
                largeFiles.add(node);
              }

              // Track potential duplicates (non-zero files with same size)
              if (size > 1024 * 1024) {
                filesBySize.putIfAbsent(size, () => []).add(node);
              }
            } catch (_) {}
          }
        }
      } catch (_) {
        // Continue if single directory permission is denied
      }
    }

    // Sort large files descending
    largeFiles.sort((a, b) => b.size.compareTo(a.size));

    // Filter duplicate groups using fast binary sample hash verification
    final List<DuplicateGroup> duplicates = [];
    filesBySize.forEach((size, list) {
      if (list.length > 1) {
        final Map<String, List<VfsNode>> hashGroups = {};
        for (final node in list) {
          final hash = _computeQuickHash(File(node.path));
          if (hash.isNotEmpty) {
            hashGroups.putIfAbsent(hash, () => []).add(node);
          }
        }
        for (final entry in hashGroups.entries) {
          if (entry.value.length > 1) {
            duplicates.add(DuplicateGroup(fileSize: size, files: entry.value));
          }
        }
      }
    });
    duplicates.sort((a, b) => b.totalWastedBytes.compareTo(a.totalWastedBytes));

    final accountedMedia = videoBytes + imageBytes + audioBytes + docBytes + appBytes;
    final int systemAndOtherBytes = (realUsed > accountedMedia)
        ? (realUsed - accountedMedia)
        : otherBytes;

    return StorageInfo(
      totalBytes: totalCapacity,
      usedBytes: realUsed,
      freeBytes: realFree,
      videoBytes: videoBytes,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
      docBytes: docBytes,
      appBytes: appBytes,
      otherBytes: systemAndOtherBytes,
      largeFiles: largeFiles.take(50).toList(),
      duplicateGroups: duplicates.take(50).toList(),
      junkCacheBytes: junkBytes,
    );
  }

  String _computeQuickHash(File file) {
    try {
      final len = file.lengthSync();
      if (len == 0) return '0_empty';
      final raf = file.openSync(mode: FileMode.read);
      try {
        final sampleSize = len < 8192 ? len : 4096;
        final head = raf.readSync(sampleSize);
        int tailSum = 0;
        if (len > 8192) {
          raf.setPositionSync(len - 4096);
          final tail = raf.readSync(4096);
          for (final b in tail) {
            tailSum = (tailSum * 31 + b) & 0x7FFFFFFF;
          }
        }
        int headSum = 0;
        for (final b in head) {
          headSum = (headSum * 31 + b) & 0x7FFFFFFF;
        }
        return '${len}_${headSum}_$tailSum';
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return '';
    }
  }
}
