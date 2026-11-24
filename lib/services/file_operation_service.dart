import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/vfs_node.dart';
import '../theme/apple_theme.dart';
import 'transfer_manager_service.dart';
import 'vfs/vfs_provider.dart';

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
