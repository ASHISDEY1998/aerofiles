import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/vfs_node.dart';
import '../theme/apple_theme.dart';
import 'transfer_manager_service.dart';
import 'vfs/vfs_provider.dart';

enum ConflictResolution {
  replace,
  skip,
  cancel,
}

class FileOperationService {
  static final FileOperationService instance = FileOperationService._();
  FileOperationService._();

  List<VfsNode> clipboardItems = [];
  bool isClipboardCut = false;
  VfsProvider? clipboardSourceVfs;

  static const MethodChannel _storageChannel = MethodChannel('com.aerofiles.app/storage');

  static Future<void> updateNotification({
    required String title,
    required String content,
    required int progress,
    required int max,
  }) async {
    try {
      if (Platform.isAndroid) {
        await _storageChannel.invokeMethod('updateTransferNotification', {
          'title': title,
          'content': content,
          'progress': progress,
          'max': max,
        });
      }
    } catch (_) {}
  }

  static Future<void> stopNotification() async {
    try {
      if (Platform.isAndroid) {
        await _storageChannel.invokeMethod('stopTransferNotification');
      }
    } catch (_) {}
  }

  /// Checks whether any items to transfer already exist in [targetDirPath] on [targetVfs].
  /// If collisions exist, prompts the user with an alert to Cancel, Skip, or Replace.
  /// Returns the resolved list of items to transfer, or `null` if user cancelled.
  Future<List<VfsNode>?> resolveConflicts({
    required BuildContext context,
    required List<VfsNode> items,
    required String targetDirPath,
    required VfsProvider targetVfs,
  }) async {
    if (items.isEmpty) return items;

    List<VfsNode> existingFiles = [];
    try {
      existingFiles = await targetVfs.listDirectory(targetDirPath);
    } catch (_) {
      // If destination listing is unavailable or directory is empty, proceed
      return items;
    }

    final existingNames = existingFiles.map((e) => e.name.toLowerCase()).toSet();
    final conflictingItems = items.where((i) => existingNames.contains(i.name.toLowerCase())).toList();

    if (conflictingItems.isEmpty) {
      return items;
    }

    if (!context.mounted) return items;

    final isSingle = conflictingItems.length == 1;
    final title = isSingle ? 'File Already Exists' : 'Files Already Exist';
    final content = isSingle
        ? '"${conflictingItems.first.name}" already exists in the destination folder. Do you want to replace it or skip?'
        : '"${conflictingItems.first.name}" and ${conflictingItems.length - 1} other item${conflictingItems.length - 1 == 1 ? '' : 's'} already exist in the destination folder. Do you want to replace existing files or skip them?';

    final choice = await showCupertinoDialog<ConflictResolution>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(content),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, ConflictResolution.cancel),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, ConflictResolution.skip),
            child: Text(isSingle ? 'Skip' : 'Skip Existing'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, ConflictResolution.replace),
            child: Text(isSingle ? 'Replace' : 'Replace All'),
          ),
        ],
      ),
    );

    if (choice == null || choice == ConflictResolution.cancel) {
      return null;
    }

    if (choice == ConflictResolution.skip) {
      final conflictingSet = conflictingItems.map((e) => e.name.toLowerCase()).toSet();
      return items.where((i) => !conflictingSet.contains(i.name.toLowerCase())).toList();
    }

    // Replace All
    return items;
  }

  Future<bool> copyItems({
    required List<VfsNode> items,
    required String targetDirPath,
    required VfsProvider targetVfs,
    required VfsProvider sourceVfs,
    void Function(double progress, String currentItem)? onProgress,
  }) async {
    await TransferManagerService.instance.startTransfer(
      items: items,
      targetDirPath: targetDirPath,
      targetVfs: targetVfs,
      sourceVfs: sourceVfs,
      isMove: false,
    );
    return true;
  }

  Future<bool> moveItems({
    required List<VfsNode> items,
    required String targetDirPath,
    required VfsProvider targetVfs,
    required VfsProvider sourceVfs,
    void Function(double progress, String currentItem)? onProgress,
  }) async {
    await TransferManagerService.instance.startTransfer(
      items: items,
      targetDirPath: targetDirPath,
      targetVfs: targetVfs,
      sourceVfs: sourceVfs,
      isMove: true,
    );
    return true;
  }

  Future<void> shareItems(List<VfsNode> items) async {
    final localFiles = items
        .where((e) => !e.isDirectory && !e.path.startsWith('http'))
        .map((e) => XFile(e.path))
        .toList();

    if (localFiles.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(files: localFiles));
    }
  }

  Future<void> openWith(VfsNode node) async {
    if (node.isDirectory) return;
    try {
      if (Platform.isAndroid) {
        final success = await _storageChannel.invokeMethod<bool>('openWith', {
          'path': node.path,
          'mimeType': node.mimeType,
        });
        if (success == true) return;
      }
    } catch (_) {}

    try {
      await OpenFilex.open(
        node.path,
        type: node.mimeType.isNotEmpty ? node.mimeType : null,
      );
    } catch (_) {}
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
