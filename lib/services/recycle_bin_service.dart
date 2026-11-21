import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TrashedItem {
  final String trashId;
  final String originalPath;
  final String name;
  final int size;
  final bool isDirectory;
  final DateTime deletedAt;

  const TrashedItem({
    required this.trashId,
    required this.originalPath,
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
    'trashId': trashId,
    'originalPath': originalPath,
    'name': name,
    'size': size,
    'isDirectory': isDirectory,
    'deletedAt': deletedAt.toIso8601String(),
  };

  factory TrashedItem.fromJson(Map<String, dynamic> json) => TrashedItem(
    trashId: json['trashId'] as String,
    originalPath: json['originalPath'] as String,
    name: json['name'] as String,
    size: json['size'] as int,
    isDirectory: json['isDirectory'] as bool,
    deletedAt: DateTime.parse(json['deletedAt'] as String),
  );
}

class RecycleBinService {
  static const MethodChannel _storageChannel = MethodChannel('com.aerofiles.app/storage');

  Directory? _trashDir;
  File? _metaFile;
  final List<TrashedItem> _items = [];

  List<TrashedItem> get items => List.unmodifiable(_items);

  static Future<void> notifyMediaScanner(String filePath) async {
    try {
      if (Platform.isAndroid) {
        await _storageChannel.invokeMethod('scanFile', {'path': filePath});
      }
    } catch (_) {}
  }

  Future<void> init() async {
    try {
      // Prefer same-mount storage /storage/emulated/0/.aerofiles_trash for instant atomic rename
      const extStorage = '/storage/emulated/0';
      if (await Directory(extStorage).exists()) {
        _trashDir = Directory(p.join(extStorage, '.aerofiles_trash'));
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        _trashDir = Directory(p.join(appDir.path, '.aerofiles_trash'));
      }

      if (!await _trashDir!.exists()) {
        await _trashDir!.create(recursive: true);
      }
      _metaFile = File(p.join(_trashDir!.path, 'metadata.json'));
      await _loadMetadata();
    } catch (_) {
      final appDir = await getApplicationDocumentsDirectory();
      _trashDir = Directory(p.join(appDir.path, '.aerofiles_trash'));
      if (!await _trashDir!.exists()) {
        await _trashDir!.create(recursive: true);
      }
      _metaFile = File(p.join(_trashDir!.path, 'metadata.json'));
      await _loadMetadata();
    }
  }

  Future<void> _loadMetadata() async {
    if (_metaFile != null && await _metaFile!.exists()) {
      try {
        final content = await _metaFile!.readAsString();
        final List<dynamic> list = jsonDecode(content);
        _items.clear();
        for (final item in list) {
          _items.add(TrashedItem.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }
  }

  Future<void> _saveMetadata() async {
    if (_metaFile != null) {
      try {
        final jsonList = _items.map((e) => e.toJson()).toList();
        await _metaFile!.writeAsString(jsonEncode(jsonList));
      } catch (_) {}
    }
  }

  Future<bool> moveToTrash(String filePath) async {
    if (_trashDir == null) await init();

    try {
      final isDir = await FileSystemEntity.isDirectory(filePath);
      final name = p.basename(filePath);
      final stat = await FileStat.stat(filePath);
      final trashId = '${DateTime.now().millisecondsSinceEpoch}_$name';
      final targetPath = p.join(_trashDir!.path, trashId);

      // Attempt atomic filesystem move
      bool moved = false;
      try {
        if (isDir) {
          await Directory(filePath).rename(targetPath);
        } else {
          await File(filePath).rename(targetPath);
        }
        moved = true;
      } catch (_) {
        // Cross-device link (EXDEV) or permission: fall back to copy + delete
        try {
          if (isDir) {
            await _copyDirectory(Directory(filePath), Directory(targetPath));
            await Directory(filePath).delete(recursive: true);
          } else {
            await File(filePath).copy(targetPath);
            await File(filePath).delete();
          }
          moved = true;
        } catch (_) {
          moved = false;
        }
      }

      if (!moved) return false;

      final item = TrashedItem(
        trashId: trashId,
        originalPath: filePath,
        name: name,
        size: isDir ? 0 : stat.size,
        isDirectory: isDir,
        deletedAt: DateTime.now(),
      );

      _items.insert(0, item);
      await _saveMetadata();
      await notifyMediaScanner(filePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restore(TrashedItem item) async {
    if (_trashDir == null) await init();

    try {
      final trashPath = p.join(_trashDir!.path, item.trashId);
      final destDir = Directory(p.dirname(item.originalPath));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      bool restored = false;
      try {
        if (item.isDirectory) {
          await Directory(trashPath).rename(item.originalPath);
        } else {
          await File(trashPath).rename(item.originalPath);
        }
        restored = true;
      } catch (_) {
        try {
          if (item.isDirectory) {
            await _copyDirectory(Directory(trashPath), Directory(item.originalPath));
            await Directory(trashPath).delete(recursive: true);
          } else {
            await File(trashPath).copy(item.originalPath);
            await File(trashPath).delete();
          }
          restored = true;
        } catch (_) {
          restored = false;
        }
      }

      if (!restored) return false;

      _items.removeWhere((i) => i.trashId == item.trashId);
      await _saveMetadata();
      await notifyMediaScanner(item.originalPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> permanentDelete(TrashedItem item) async {
    if (_trashDir == null) await init();

    try {
      final trashPath = p.join(_trashDir!.path, item.trashId);
      if (item.isDirectory) {
        final d = Directory(trashPath);
        if (await d.exists()) await d.delete(recursive: true);
      } else {
        final f = File(trashPath);
        if (await f.exists()) await f.delete();
      }

      _items.removeWhere((i) => i.trashId == item.trashId);
      await _saveMetadata();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> emptyTrash() async {
    final copy = List<TrashedItem>.from(_items);
    for (final item in copy) {
      await permanentDelete(item);
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
}
