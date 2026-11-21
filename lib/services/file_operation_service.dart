import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../models/vfs_node.dart';
import '../theme/apple_theme.dart';
import 'vfs/local_vfs.dart';
import 'vfs/smb_vfs.dart';
import 'vfs/vfs_provider.dart';

class FileOperationService {
  static final FileOperationService instance = FileOperationService._();
  FileOperationService._();

  Future<bool> copyItems({
    required List<VfsNode> items,
    required String targetDirPath,
    required VfsProvider targetVfs,
    required VfsProvider sourceVfs,
    void Function(double progress, String currentItem)? onProgress,
  }) async {
    bool allOk = true;
    for (int i = 0; i < items.length; i++) {
      final node = items[i];
      onProgress?.call(i / items.length, node.name);
      final destPath = p.join(targetDirPath, node.name);

      try {
        if (sourceVfs is LocalVfs && targetVfs is LocalVfs) {
          final ok = await targetVfs.copy(node.path, destPath);
          if (!ok) allOk = false;
        } else if (sourceVfs is LocalVfs && targetVfs is SmbVfs) {
          if (node.isDirectory) {
            final ok = await _copyLocalDirToSmb(Directory(node.path), destPath, targetVfs);
            if (!ok) allOk = false;
          } else {
            final f = File(node.path);
            if (await f.exists()) {
              final ok = await targetVfs.writeLocalFile(destPath, f);
              if (!ok) allOk = false;
            } else {
              allOk = false;
            }
          }
        } else if (sourceVfs is SmbVfs && targetVfs is LocalVfs) {
          final f = File(destPath);
          final ok = await sourceVfs.readToLocalFile(node.path, f);
          if (!ok) allOk = false;
        }
      } catch (_) {
        allOk = false;
      }
    }
    onProgress?.call(1.0, 'Done');
    return allOk;
  }

  Future<bool> _copyLocalDirToSmb(Directory localDir, String remoteDirPath, SmbVfs smb) async {
    try {
      final parent = p.dirname(remoteDirPath);
      final name = p.basename(remoteDirPath);
      await smb.createDirectory(parent, name);
      await for (final entity in localDir.list(recursive: false)) {
        final childDest = p.join(remoteDirPath, p.basename(entity.path));
        if (entity is Directory) {
          await _copyLocalDirToSmb(entity, childDest, smb);
        } else if (entity is File) {
          await smb.writeLocalFile(childDest, entity);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> moveItems({
    required List<VfsNode> items,
    required String targetDirPath,
    required VfsProvider targetVfs,
    required VfsProvider sourceVfs,
    void Function(double progress, String currentItem)? onProgress,
  }) async {
    final success = await copyItems(
      items: items,
      targetDirPath: targetDirPath,
      targetVfs: targetVfs,
      sourceVfs: sourceVfs,
      onProgress: onProgress,
    );
    if (success) {
      for (final node in items) {
        await sourceVfs.delete(node.path, moveToTrash: false);
      }
    }
    return success;
  }

  Future<void> shareItems(List<VfsNode> items) async {
    final localFiles = items
        .where((e) => !e.isDirectory && !e.path.startsWith('http'))
        .map((e) => XFile(e.path))
        .toList();

    if (localFiles.isNotEmpty) {
      await Share.shareXFiles(localFiles);
    }
  }

  void showFileInfo(BuildContext context, VfsNode node) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(node.modified);

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          node.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        message: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            _infoRow('Type', node.isDirectory ? 'Folder' : (node.extension.isEmpty ? 'File' : node.extension.toUpperCase()), isDark),
            _infoRow('Size', '${node.formattedSize} (${NumberFormat('#,###').format(node.size)} bytes)', isDark),
            _infoRow('Modified', dateStr, isDark),
            _infoRow('Path', node.path, isDark, isPath: true, onCopy: () {
              Clipboard.setData(ClipboardData(text: node.path));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied to clipboard')),
              );
            }),
          ],
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark, {bool isPath = false, VoidCallback? onCopy}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: isPath ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                fontSize: 13,
              ),
            ),
          ),
          if (isPath && onCopy != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onCopy,
              child: const Icon(CupertinoIcons.doc_on_doc, size: 14, color: AppleColors.systemBlue),
            ),
          ],
        ],
      ),
    );
  }
}
