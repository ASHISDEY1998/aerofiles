import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

enum FileCategory {
  folder,
  video,
  audio,
  image,
  document,
  archive,
  app,
  other,
}

class VfsNode {
  final String path;
  final String name;
  final int size; // bytes
  final bool isDirectory;
  final DateTime modified;
  final String? customMimeType;
  final String? remoteStorageId; // null for local, connection ID for remote

  const VfsNode({
    required this.path,
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.modified,
    this.customMimeType,
    this.remoteStorageId,
  });

  String get extension => p.extension(name).toLowerCase();

  String get mimeType {
    if (customMimeType != null) return customMimeType!;
    return lookupMimeType(name) ?? 'application/octet-stream';
  }

  FileCategory get category {
    if (isDirectory) return FileCategory.folder;
    final ext = extension;

    // Videos
    const videoExts = {
      '.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.webm',
      '.ts', '.m2ts', '.vob', '.ogv', '.3gp', '.rmvb', '.m4v', '.f4v'
    };
    if (videoExts.contains(ext) || mimeType.startsWith('video/')) {
      return FileCategory.video;
    }

    // Audio
    const audioExts = {
      '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.opus',
      '.alac', '.wma', '.ape', '.aiff', '.dts', '.ac3'
    };
    if (audioExts.contains(ext) || mimeType.startsWith('audio/')) {
      return FileCategory.audio;
    }

    // Images
    const imageExts = {
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg',
      '.heic', '.heif', '.tiff', '.ico', '.raw'
    };
    if (imageExts.contains(ext) || mimeType.startsWith('image/')) {
      return FileCategory.image;
    }

    // Documents
    const docExts = {
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
      '.txt', '.csv', '.json', '.xml', '.html', '.md', '.epub'
    };
    if (docExts.contains(ext)) {
      return FileCategory.document;
    }

    // Archives
    const archiveExts = {
      '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.iso'
    };
    if (archiveExts.contains(ext)) {
      return FileCategory.archive;
    }

    // Apps
    if (ext == '.apk' || ext == '.ipa' || ext == '.dmg' || ext == '.exe') {
      return FileCategory.app;
    }

    return FileCategory.other;
  }

  bool get isVideo => category == FileCategory.video;
  bool get isAudio => category == FileCategory.audio;
  bool get isImage => category == FileCategory.image;
  bool get isDocument => category == FileCategory.document;
  bool get isArchive => category == FileCategory.archive;

  String get formattedSize {
    if (isDirectory) return '';
    if (size <= 0) return '0 B';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(modified);

    if (difference.inDays == 0) {
      return DateFormat('h:mm a').format(modified);
    } else if (difference.inDays < 7) {
      return DateFormat('E, h:mm a').format(modified);
    } else if (now.year == modified.year) {
      return DateFormat('MMM d').format(modified);
    } else {
      return DateFormat('MM/dd/yyyy').format(modified);
    }
  }

  VfsNode copyWith({
    String? path,
    String? name,
    int? size,
    bool? isDirectory,
    DateTime? modified,
    String? customMimeType,
    String? remoteStorageId,
  }) {
    return VfsNode(
      path: path ?? this.path,
      name: name ?? this.name,
      size: size ?? this.size,
      isDirectory: isDirectory ?? this.isDirectory,
      modified: modified ?? this.modified,
      customMimeType: customMimeType ?? this.customMimeType,
      remoteStorageId: remoteStorageId ?? this.remoteStorageId,
    );
  }
}
