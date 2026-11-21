import 'vfs_node.dart';

class DuplicateGroup {
  final int fileSize;
  final List<VfsNode> files;

  const DuplicateGroup({
    required this.fileSize,
    required this.files,
  });

  int get totalWastedBytes => fileSize * (files.length - 1);
}

class StorageInfo {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;

  final int videoBytes;
  final int imageBytes;
  final int audioBytes;
  final int docBytes;
  final int appBytes;
  final int systemBytes;
  final int otherBytes;

  final List<VfsNode> largeFiles;
  final List<DuplicateGroup> duplicateGroups;
  final int junkCacheBytes;

  const StorageInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    this.videoBytes = 0,
    this.imageBytes = 0,
    this.audioBytes = 0,
    this.docBytes = 0,
    this.appBytes = 0,
    this.systemBytes = 0,
    this.otherBytes = 0,
    this.largeFiles = const [],
    this.duplicateGroups = const [],
    this.junkCacheBytes = 0,
  });

  double get usedPercentage {
    if (totalBytes <= 0) return 0.0;
    return (usedBytes / totalBytes).clamp(0.0, 1.0);
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedUsed => formatBytes(usedBytes);
  String get formattedTotal => formatBytes(totalBytes);
  String get formattedFree => formatBytes(freeBytes);
}
