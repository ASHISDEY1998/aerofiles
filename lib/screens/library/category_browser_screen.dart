import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../models/vfs_node.dart';
import '../../services/file_operation_service.dart';
import '../../services/media/thumbnail_service.dart';
import '../../services/recycle_bin_service.dart';
import '../../services/security/safe_vault_service.dart';
import '../../services/settings_service.dart';
import '../../services/transfer_manager_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import '../../widgets/file_tile.dart';
import '../common/destination_picker_screen.dart';
import '../player/image_viewer_screen.dart';
import '../player/universal_audio_player_screen.dart';
import '../player/universal_video_player_screen.dart';
import '../player/video_merge_dialog.dart';
import '../player/video_trim_screen.dart';
import '../security/vault_pin_dialog.dart';

enum CategorySort { newToOld, oldToNew, nameAsc, nameDesc, sizeDesc, sizeAsc }
enum CategoryViewMode { folders, allFiles }

class MediaFolderGroup {
  final String folderPath;
  final String folderName;
  final String displayPath;
  final List<VfsNode> items;
  final int totalBytes;
  final DateTime latestModified;
  final VfsNode previewNode;

  MediaFolderGroup({
    required this.folderPath,
    required this.folderName,
    required this.displayPath,
    required this.items,
    required this.totalBytes,
    required this.latestModified,
    required this.previewNode,
  });
}

class CategoryBrowserScreen extends StatefulWidget {
  final String title;
  final List<VfsNode> items;
  final LocalVfs localVfs;

  const CategoryBrowserScreen({
    super.key,
    required this.title,
    required this.items,
    required this.localVfs,
  });

  @override
  State<CategoryBrowserScreen> createState() => _CategoryBrowserScreenState();
}

class _CategoryBrowserScreenState extends State<CategoryBrowserScreen> {
  late List<VfsNode> _currentItems;
  late bool _isGrid;
  bool _showSearch = false;
  String _searchQuery = '';
  CategorySort _sort = CategorySort.newToOld;
  CategoryViewMode _viewMode = CategoryViewMode.folders;
  MediaFolderGroup? _selectedFolderGroup;
  String? _filterFolderChip;

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};
  dynamic _transferSub;

  @override
  void initState() {
    super.initState();
    _isGrid = SettingsService.instance.isGridView;
    _currentItems = List.from(widget.items);
    _transferSub = TransferManagerService.instance.onTransferFinished.listen((_) {
      if (mounted) {
        setState(() {
          _currentItems.removeWhere((item) => !File(item.path).existsSync() && !Directory(item.path).existsSync());
        });
      }
    });
  }

  @override
  void dispose() {
    _transferSub?.cancel();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  List<MediaFolderGroup> get _folderGroups {
    final Map<String, List<VfsNode>> map = {};
    for (final node in _currentItems) {
      final parentDir = p.dirname(node.path);
      map.putIfAbsent(parentDir, () => []).add(node);
    }

    final root = widget.localVfs.rootPath;
    final List<MediaFolderGroup> groups = [];

    for (final entry in map.entries) {
      final dirPath = entry.key;
      final items = entry.value;

      final folderName = p.basename(dirPath).isEmpty ? 'Root' : p.basename(dirPath);

      String relPath = dirPath;
      if (dirPath.startsWith(root)) {
        relPath = dirPath.substring(root.length);
        if (relPath.startsWith('/')) relPath = relPath.substring(1);
      }
      if (relPath.isEmpty) relPath = folderName;

      items.sort((a, b) => b.modified.compareTo(a.modified));

      int totalBytes = 0;
      for (final it in items) {
        totalBytes += it.size;
      }

      groups.add(MediaFolderGroup(
        folderPath: dirPath,
        folderName: folderName,
        displayPath: relPath,
        items: items,
        totalBytes: totalBytes,
        latestModified: items.isNotEmpty ? items.first.modified : DateTime.now(),
        previewNode: items.first,
      ));
    }

    var result = groups;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((g) =>
          g.folderName.toLowerCase().contains(q) ||
          g.displayPath.toLowerCase().contains(q) ||
          g.items.any((it) => it.name.toLowerCase().contains(q))).toList();
    }

    result.sort((a, b) {
      switch (_sort) {
        case CategorySort.newToOld:
          return b.latestModified.compareTo(a.latestModified);
        case CategorySort.oldToNew:
          return a.latestModified.compareTo(b.latestModified);
        case CategorySort.nameAsc:
          return a.folderName.toLowerCase().compareTo(b.folderName.toLowerCase());
        case CategorySort.nameDesc:
          return b.folderName.toLowerCase().compareTo(a.folderName.toLowerCase());
        case CategorySort.sizeDesc:
          return b.totalBytes.compareTo(a.totalBytes);
        case CategorySort.sizeAsc:
          return a.totalBytes.compareTo(b.totalBytes);
      }
    });

    return result;
  }

  List<VfsNode> get _displayItems {
    var list = _currentItems;

    if (_selectedFolderGroup != null) {
      list = list.where((e) => p.dirname(e.path) == _selectedFolderGroup!.folderPath).toList();
    } else if (_filterFolderChip != null && _filterFolderChip!.isNotEmpty) {
      list = list.where((e) => p.dirname(e.path) == _filterFolderChip).toList();
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    list.sort((a, b) {
      switch (_sort) {
        case CategorySort.newToOld:
          return b.modified.compareTo(a.modified);
        case CategorySort.oldToNew:
          return a.modified.compareTo(b.modified);
        case CategorySort.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case CategorySort.nameDesc:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case CategorySort.sizeDesc:
          return b.size.compareTo(a.size);
        case CategorySort.sizeAsc:
          return a.size.compareTo(b.size);
      }
    });

    return list;
  }

  void _toggleSelection(VfsNode node) {
    setState(() {
      if (_selectedPaths.contains(node.path)) {
        _selectedPaths.remove(node.path);
        if (_selectedPaths.isEmpty) _isSelectionMode = false;
      } else {
        _selectedPaths.add(node.path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedPaths.length == _displayItems.length) {
        _selectedPaths.clear();
        _isSelectionMode = false;
      } else {
        _selectedPaths.addAll(_displayItems.map((e) => e.path));
      }
    });
  }

  void _handleNodeTap(VfsNode node) async {
    if (_isSelectionMode) {
      _toggleSelection(node);
      return;
    }

    if (node.isVideo) {
      final videoItems = _displayItems.where((e) => e.isVideo).toList();
      final index = videoItems.indexWhere((e) => e.path == node.path);
      final playbackUri = await widget.localVfs.getPlaybackUri(node.path);
      if (!mounted) return;
      final deleted = await Navigator.push<bool>(
        context,
        CupertinoPageRoute(
          builder: (_) => UniversalVideoPlayerScreen(
            title: node.name,
            playbackUri: playbackUri,
            playlist: videoItems.isNotEmpty ? videoItems : [node],
            initialIndex: index != -1 ? index : 0,
            vfs: widget.localVfs,
          ),
        ),
      );
      if (deleted == true && mounted) {
        final existing = <VfsNode>[];
        for (final item in _currentItems) {
          if (await File(item.path).exists()) {
            existing.add(item);
          }
        }
        setState(() {
          _currentItems = existing;
          if (_selectedFolderGroup != null &&
              !existing.any((e) => p.dirname(e.path) == _selectedFolderGroup!.folderPath)) {
            _selectedFolderGroup = null;
          }
        });
      }
    } else if (node.isImage) {
      final allImages = _displayItems.where((e) => e.isImage).toList();
      final index = allImages.indexWhere((e) => e.path == node.path);
      final deleted = await Navigator.push<bool>(
        context,
        CupertinoPageRoute(
          builder: (_) => ImageViewerScreen(
            images: allImages.isNotEmpty ? allImages : [node],
            initialIndex: index != -1 ? index : 0,
            vfs: widget.localVfs,
          ),
        ),
      );
      if (deleted == true && mounted) {
        final existing = <VfsNode>[];
        for (final item in _currentItems) {
          if (await File(item.path).exists()) {
            existing.add(item);
          }
        }
        setState(() {
          _currentItems = existing;
          if (_selectedFolderGroup != null &&
              !existing.any((e) => p.dirname(e.path) == _selectedFolderGroup!.folderPath)) {
            _selectedFolderGroup = null;
          }
        });
      }
    } else if (node.isAudio) {
      final audioItems = _displayItems.where((e) => e.isAudio).toList();
      final index = audioItems.indexWhere((e) => e.path == node.path);
      final deleted = await Navigator.push<bool>(
        context,
        CupertinoPageRoute(
          builder: (_) => UniversalAudioPlayerScreen(
            playlist: audioItems.isNotEmpty ? audioItems : [node],
            initialIndex: index != -1 ? index : 0,
            vfs: widget.localVfs,
          ),
        ),
      );
      if (deleted == true && mounted) {
        final existing = <VfsNode>[];
        for (final item in _currentItems) {
          if (await File(item.path).exists()) {
            existing.add(item);
          }
        }
        setState(() {
          _currentItems = existing;
          if (_selectedFolderGroup != null &&
              !existing.any((e) => p.dirname(e.path) == _selectedFolderGroup!.folderPath)) {
            _selectedFolderGroup = null;
          }
        });
      }
    } else {
      try {
        await OpenFilex.open(node.path);
      } catch (_) {}
    }
  }

  void _showSortMenu() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Arrange & Sort Items'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sort = CategorySort.newToOld);
              Navigator.pop(ctx);
            },
            child: Text('Date: Newest First ${_sort == CategorySort.newToOld ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sort = CategorySort.oldToNew);
              Navigator.pop(ctx);
            },
            child: Text('Date: Oldest First ${_sort == CategorySort.oldToNew ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sort = CategorySort.nameAsc);
              Navigator.pop(ctx);
            },
            child: Text('Name (A to Z) ${_sort == CategorySort.nameAsc ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sort = CategorySort.nameDesc);
              Navigator.pop(ctx);
            },
            child: Text('Name (Z to A) ${_sort == CategorySort.nameDesc ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sort = CategorySort.sizeDesc);
              Navigator.pop(ctx);
            },
            child: Text('Size: Largest First ${_sort == CategorySort.sizeDesc ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sort = CategorySort.sizeAsc);
              Navigator.pop(ctx);
            },
            child: Text('Size: Smallest First ${_sort == CategorySort.sizeAsc ? '✓' : ''}'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ),
    );
  }

  List<VfsNode> get _selectedNodes {
    final Map<String, VfsNode> itemMap = {for (final e in _currentItems) e.path: e};
    final List<VfsNode> ordered = [];
    for (final p in _selectedPaths) {
      final node = itemMap[p];
      if (node != null) ordered.add(node);
    }
    return ordered;
  }

  Future<void> _openTrimScreen(VfsNode node) async {
    final changed = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (ctx) => VideoTrimScreen(node: node, vfs: widget.localVfs),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _currentItems.removeWhere((item) => !File(item.path).existsSync() && !Directory(item.path).existsSync());
        _selectedPaths.clear();
        _isSelectionMode = false;
      });
    }
  }

  Future<void> _openMergeDialog(List<VfsNode> nodes) async {
    final changed = await VideoMergeDialog.show(
      context,
      orderedVideos: nodes,
    );
    if (changed && mounted) {
      setState(() {
        _currentItems.removeWhere((item) => !File(item.path).existsSync() && !Directory(item.path).existsSync());
        _selectedPaths.clear();
        _isSelectionMode = false;
      });
    }
  }

  Future<void> _handleBatchDelete() async {
    final selected = _selectedNodes;
    if (selected.isEmpty) return;

    final settings = SettingsService.instance;
    final behavior = settings.deleteBehavior;

    if (behavior == DeleteBehavior.recycleBin) {
      _executeBatchDelete(selected, moveToTrash: true);
      return;
    } else if (behavior == DeleteBehavior.permanent) {
      _confirmBatchPermanentDelete(selected);
      return;
    }

    bool moveToTrash = true;

    showCupertinoDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return CupertinoAlertDialog(
            title: Text('Delete ${selected.length} items?'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose how to delete the selected items:',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => setDialogState(() => moveToTrash = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: moveToTrash
                            ? (isDark ? AppleColors.systemBlue.withValues(alpha: 0.15) : AppleColors.systemBlueLight.withValues(alpha: 0.1))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: moveToTrash ? AppleColors.systemBlue : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.trash,
                            color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Move to Recycle Bin',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                  ),
                                ),
                                Text(
                                  'Can be restored later if needed',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (moveToTrash)
                            const Icon(CupertinoIcons.checkmark_circle_fill, color: AppleColors.systemBlue, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setDialogState(() => moveToTrash = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: !moveToTrash
                            ? (isDark ? AppleColors.systemRed.withValues(alpha: 0.15) : AppleColors.systemRed.withValues(alpha: 0.1))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: !moveToTrash ? AppleColors.systemRed : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.trash_fill, color: AppleColors.systemRed, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Permanently Delete',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                  ),
                                ),
                                Text(
                                  'Irreversible; immediately frees up storage',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!moveToTrash)
                            const Icon(CupertinoIcons.checkmark_circle_fill, color: AppleColors.systemRed, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(ctx),
              ),
              CupertinoDialogAction(
                isDestructiveAction: !moveToTrash,
                child: Text(moveToTrash ? 'Move to Bin' : 'Delete Forever'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _executeBatchDelete(selected, moveToTrash: moveToTrash);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmBatchPermanentDelete(List<VfsNode> selected) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Permanently delete ${selected.length} items?'),
        content: const Text('This cannot be undone and will permanently remove them from your storage.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete Permanently'),
            onPressed: () {
              Navigator.pop(ctx);
              _executeBatchDelete(selected, moveToTrash: false);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _executeBatchDelete(List<VfsNode> selected, {required bool moveToTrash}) async {
    for (final node in selected) {
      await widget.localVfs.delete(node.path, moveToTrash: moveToTrash);
    }
    setState(() {
      _currentItems.removeWhere((e) => _selectedPaths.contains(e.path));
      _selectedPaths.clear();
      _isSelectionMode = false;
      if (_selectedFolderGroup != null &&
          !_currentItems.any((e) => p.dirname(e.path) == _selectedFolderGroup!.folderPath)) {
        _selectedFolderGroup = null;
      }
    });

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      if (moveToTrash) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppleColors.darkCard,
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.down,
            duration: const Duration(seconds: 4),
            content: Text(
              '${selected.length} item${selected.length == 1 ? '' : 's'} moved to Recycle Bin',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            action: SnackBarAction(
              label: 'Undo',
              textColor: AppleColors.systemBlue,
              onPressed: () async {
                final restored = await RecycleBinService.instance.restoreRecentlyTrashed();
                if (mounted && restored > 0) {
                  final existing = <VfsNode>[];
                  for (final item in widget.items) {
                    if (await File(item.path).exists()) {
                      existing.add(item);
                    }
                  }
                  setState(() => _currentItems = existing);
                  if (!mounted) return;
                  final undoMessenger = ScaffoldMessenger.of(context);
                  undoMessenger.removeCurrentSnackBar();
                  undoMessenger.showSnackBar(
                    SnackBar(
                      backgroundColor: AppleColors.darkCard,
                      behavior: SnackBarBehavior.floating,
                      dismissDirection: DismissDirection.down,
                      content: Text(
                        'Restored $restored item${restored == 1 ? '' : 's'}',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
        );
        Timer(const Duration(seconds: 4), () {
          messenger.hideCurrentSnackBar();
        });
      } else {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppleColors.darkCard,
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.down,
            duration: const Duration(seconds: 4),
            content: Text(
              '${selected.length} items permanently deleted',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        );
        Timer(const Duration(seconds: 4), () {
          messenger.hideCurrentSnackBar();
        });
      }
    }
  }

  Future<void> _handleMoveToVault(List<VfsNode> nodes) async {
    if (nodes.isEmpty) return;

    if (!SafeVaultService.instance.isUnlocked) {
      final unlocked = await VaultPinDialog.show(
        context,
        mode: SafeVaultService.instance.hasPin ? VaultPinMode.unlock : VaultPinMode.setup,
      );
      if (!unlocked || !SafeVaultService.instance.isUnlocked) return;
    }

    if (!mounted) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Move to Safe Vault?'),
        content: Text(
          'Move ${nodes.length} ${nodes.length == 1 ? "file" : "files"} to Safe Vault? Files will be AES-256 encrypted and hidden from gallery and storage.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move to Vault'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await SafeVaultService.instance.moveToVault(nodes);
    if (mounted) {
      final movedPaths = nodes.map((e) => e.path).toSet();
      setState(() {
        _currentItems.removeWhere((e) => movedPaths.contains(e.path));
        _selectedPaths.clear();
        _isSelectionMode = false;
        if (_selectedFolderGroup != null &&
            !_currentItems.any((e) => p.dirname(e.path) == _selectedFolderGroup!.folderPath)) {
          _selectedFolderGroup = null;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Moved ${nodes.length} ${nodes.length == 1 ? "file" : "files"} to Safe Vault'
                : 'Some files could not be moved to Safe Vault',
          ),
          backgroundColor: AppleColors.darkElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleBatchTransfer({required bool isMove}) async {
    final selected = _selectedNodes;
    if (selected.isEmpty) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      CupertinoPageRoute(
        builder: (_) => DestinationPickerScreen(
          actionTitle: isMove ? 'Move to' : 'Copy to',
          itemsToTransfer: selected,
          localVfs: widget.localVfs,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final targetPath = (result['targetPath'] ?? result['path']) as String;
    final targetVfs = (result['targetVfs'] ?? result['vfs']) as VfsProvider;

    final resolvedItems = await FileOperationService.instance.resolveConflicts(
      context: context,
      items: selected,
      targetDirPath: targetPath,
      targetVfs: targetVfs,
    );

    if (resolvedItems == null || !mounted) {
      return; // Canceled by user
    }

    if (resolvedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Existing files skipped. Nothing to transfer.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final resolvedPaths = resolvedItems.map((e) => e.path).toSet();
    setState(() {
      if (isMove) {
        _currentItems.removeWhere((e) => resolvedPaths.contains(e.path));
      }
      _selectedPaths.clear();
      _isSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${isMove ? "Moving" : "Copying"} ${resolvedItems.length} items to ${targetVfs.displayName}...',
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    await TransferManagerService.instance.startTransfer(
      items: resolvedItems,
      targetDirPath: targetPath,
      targetVfs: targetVfs,
      sourceVfs: widget.localVfs,
      isMove: isMove,
    );
  }

  void _showSingleNodeOptions(VfsNode node) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        message: Text('${_formatBytes(node.size)} • ${p.dirname(node.path)}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              FileOperationService.instance.shareItems([node]);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.share, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Share File',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (!node.isDirectory)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                FileOperationService.instance.openWith(node);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.arrow_up_right_square, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Open with...',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (node.isVideo)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _openTrimScreen(node);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.scissors, size: 18, color: AppleColors.systemBlue),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Trim Video',
                      style: TextStyle(color: AppleColors.systemBlue),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _selectedPaths.clear();
                _selectedPaths.add(node.path);
              });
              _handleBatchTransfer(isMove: false);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.doc_on_doc, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Copy to...',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _selectedPaths.clear();
                _selectedPaths.add(node.path);
              });
              _handleBatchTransfer(isMove: true);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.arrow_right_arrow_left, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Move to...',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (SafeVaultService.instance.isVaultEnabled && !node.isDirectory)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _handleMoveToVault([node]);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.lock_shield_fill, size: 18, color: AppleColors.systemIndigo),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Move to Safe Vault',
                      style: TextStyle(color: AppleColors.systemIndigo),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _promptRename(node);
            },
            child: const Text('Rename'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _selectedPaths.clear();
                _selectedPaths.add(node.path);
              });
              _handleBatchDelete();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.trash, size: 18, color: AppleColors.systemRed),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: AppleColors.systemRed)),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _promptRename(VfsNode node) {
    final controller = TextEditingController(text: node.name);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Rename Item'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            child: const Text('Save'),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != node.name) {
                final parent = p.dirname(node.path);
                final newPath = p.join(parent, newName);
                final ok = await widget.localVfs.rename(node.path, newPath);
                if (ok && mounted) {
                  final idx = _currentItems.indexWhere((e) => e.path == node.path);
                  if (idx != -1) {
                    setState(() {
                      _currentItems[idx] = VfsNode(
                        path: newPath,
                        name: newName,
                        size: node.size,
                        isDirectory: node.isDirectory,
                        modified: DateTime.now(),
                      );
                    });
                  }
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackFolderIcon(VfsNode node) {
    Color iconColor = AppleColors.systemBlue;
    IconData iconData = CupertinoIcons.folder_fill;
    if (node.isVideo) {
      iconColor = AppleColors.catVideos;
      iconData = CupertinoIcons.play_rectangle_fill;
    } else if (node.isImage) {
      iconColor = AppleColors.catImages;
      iconData = CupertinoIcons.photo_fill;
    } else if (node.isAudio) {
      iconColor = AppleColors.catAudio;
      iconData = CupertinoIcons.music_note_2;
    } else if (node.isDocument) {
      iconColor = AppleColors.catDocs;
      iconData = CupertinoIcons.doc_text_fill;
    }
    return Container(
      color: iconColor.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(iconData, size: 36, color: iconColor),
    );
  }

  Widget _buildFolderThumbnail(MediaFolderGroup group) {
    final node = group.previewNode;
    if (node.isVideo) {
      return FutureBuilder<Uint8List?>(
        future: ThumbnailService.instance.getVideoThumbnail(node.path),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          }
          return _buildFallbackFolderIcon(node);
        },
      );
    } else if (node.isImage) {
      return Image.file(
        File(node.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (ctx, err, stack) => _buildFallbackFolderIcon(node),
      );
    }
    return _buildFallbackFolderIcon(node);
  }

  Widget _buildFolderGridCard(MediaFolderGroup folder, bool isDark) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selectedFolderGroup = folder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail Preview with overlay badge
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildFolderThumbnail(folder),
                    // Dark bottom gradient for readability
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 36,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Color(0x99000000)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    // Top-left Folder Pill Badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.folder_fill, size: 11, color: AppleColors.systemBlue),
                            const SizedBox(width: 4),
                            Text(
                              '${folder.items.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Top-right video badge if applicable
                    if (folder.previewNode.isVideo)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(CupertinoIcons.play_fill, size: 10, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Folder Details
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.folderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${folder.items.length} items • ${_formatBytes(folder.totalBytes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderListTile(MediaFolderGroup folder, bool isDark) {
    return AppleCard(
      onTap: () => setState(() => _selectedFolderGroup = folder),
      padding: const EdgeInsets.all(12),
      borderRadius: 14,
      child: Row(
        children: [
          // Preview Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildFolderThumbnail(folder),
                  if (folder.previewNode.isVideo)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.play_fill, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Folder info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${folder.items.length} items • ${_formatBytes(folder.totalBytes)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  folder.displayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
          ),
        ],
      ),
    );
  }

  Widget _buildFolderChipsBar(bool isDark) {
    final groups = _folderGroups;
    if (groups.length <= 1) return const SizedBox.shrink();

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length + 1,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final isSelected = isAll ? (_filterFolderChip == null) : (_filterFolderChip == groups[index - 1].folderPath);
          final label = isAll ? 'All (${_currentItems.length})' : '${groups[index - 1].folderName} (${groups[index - 1].items.length})';

          return Center(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    _filterFolderChip = isAll ? null : groups[index - 1].folderPath;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight)
                        : (isDark ? AppleColors.darkElevated : AppleColors.lightElevated),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : (isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? Colors.white : (isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayedItems = _displayItems;
    final folderGroups = _folderGroups;

    final isViewingFolderDetail = _selectedFolderGroup != null;
    final isFolderMode = _viewMode == CategoryViewMode.folders && !isViewingFolderDetail;

    return PopScope(
      canPop: !_isSelectionMode && !isViewingFolderDetail,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedPaths.clear();
          });
          return;
        }
        if (isViewingFolderDetail) {
          setState(() => _selectedFolderGroup = null);
          return;
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
        appBar: AppBar(
          title: Text(
            _isSelectionMode
                ? '${_selectedPaths.length} Selected'
                : isViewingFolderDetail
                    ? '${_selectedFolderGroup!.folderName} (${displayedItems.length})'
                    : isFolderMode
                        ? '${widget.title} (${folderGroups.length} folders)'
                        : '${widget.title} (${displayedItems.length})',
          ),
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => setState(() {
                    _isSelectionMode = false;
                    _selectedPaths.clear();
                  }),
                )
              : isViewingFolderDetail
                  ? IconButton(
                      icon: const Icon(CupertinoIcons.back),
                      tooltip: 'Back to Folders',
                      onPressed: () => setState(() => _selectedFolderGroup = null),
                    )
                  : null,
          actions: [
            if (_isSelectionMode) ...[
              TextButton(
                onPressed: _selectAll,
                child: Text(
                  _selectedPaths.length == displayedItems.length ? 'Deselect All' : 'Select All',
                  style: TextStyle(
                    color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...[
              IconButton(
                icon: Icon(_showSearch ? CupertinoIcons.search_circle_fill : CupertinoIcons.search),
                onPressed: () => setState(() => _showSearch = !_showSearch),
              ),
              IconButton(
                icon: Icon(_isGrid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2),
                onPressed: () {
                  final next = !_isGrid;
                  setState(() => _isGrid = next);
                  SettingsService.instance.setGridView(next);
                },
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.sort_down),
                onPressed: _showSortMenu,
              ),
              if (!isFolderMode)
                IconButton(
                  icon: const Icon(CupertinoIcons.checkmark_circle),
                  tooltip: 'Select items',
                  onPressed: () => setState(() => _isSelectionMode = true),
                ),
            ],
          ],
        ),
        body: Column(
          children: [
            // Search field
            if (_showSearch && !_isSelectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CupertinoSearchTextField(
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

            // Top Mode Switcher (Folders vs All Files) when not inside a folder detail
            if (!isViewingFolderDetail && !_isSelectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<CategoryViewMode>(
                    groupValue: _viewMode,
                    backgroundColor: isDark ? const Color(0xFF1E1E20) : const Color(0xFFE5E5EA),
                    thumbColor: isDark ? const Color(0xFF323236) : Colors.white,
                    children: {
                      CategoryViewMode.folders: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.folder_fill,
                              size: 14,
                              color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Folders (${folderGroups.length})',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      CategoryViewMode.allFiles: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.square_grid_2x2,
                              size: 14,
                              color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'All Files (${_currentItems.length})',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    },
                    onValueChanged: (val) {
                      if (val != null) setState(() => _viewMode = val);
                    },
                  ),
                ),
              ),

            // Filter chips bar in All Files mode
            if (!isViewingFolderDetail && _viewMode == CategoryViewMode.allFiles && !_isSelectionMode)
              _buildFolderChipsBar(isDark),

            // Main Content Area
            Expanded(
              child: isFolderMode
                  // FOLDERS VIEW (Cx File Explorer style)
                  ? (folderGroups.isEmpty
                      ? Center(
                          child: Text(
                            'No folders found',
                            style: TextStyle(
                              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                            ),
                          ),
                        )
                      : _isGrid
                          ? GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                childAspectRatio: 0.86,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: folderGroups.length,
                              itemBuilder: (context, index) {
                                return _buildFolderGridCard(folderGroups[index], isDark);
                              },
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: folderGroups.length,
                              separatorBuilder: (context, i) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                return _buildFolderListTile(folderGroups[index], isDark);
                              },
                            ))
                  // FILES VIEW (Inside a folder OR in All Files view)
                  : (displayedItems.isEmpty
                      ? Center(
                          child: Text(
                            'No files found',
                            style: TextStyle(
                              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                            ),
                          ),
                        )
                      : _isGrid
                          ? GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 130,
                                childAspectRatio: 0.82,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: displayedItems.length,
                              itemBuilder: (context, index) {
                                final node = displayedItems[index];
                                final isSelected = _selectedPaths.contains(node.path);

                                return FileTile(
                                  node: node,
                                  isGrid: true,
                                  isSelectable: _isSelectionMode,
                                  isSelected: isSelected,
                                  vfs: widget.localVfs,
                                  onTap: () => _handleNodeTap(node),
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    setState(() {
                                      if (!_isSelectionMode) {
                                        _isSelectionMode = true;
                                        _selectedPaths.add(node.path);
                                      } else {
                                        _toggleSelection(node);
                                      }
                                    });
                                  },
                                );
                              },
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: displayedItems.length,
                              itemBuilder: (context, index) {
                                final node = displayedItems[index];
                                final isSelected = _selectedPaths.contains(node.path);

                                return FileTile(
                                  node: node,
                                  isGrid: false,
                                  isSelectable: _isSelectionMode,
                                  isSelected: isSelected,
                                  vfs: widget.localVfs,
                                  onTap: () => _handleNodeTap(node),
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    setState(() {
                                      if (!_isSelectionMode) {
                                        _isSelectionMode = true;
                                        _selectedPaths.add(node.path);
                                      } else {
                                        _toggleSelection(node);
                                      }
                                    });
                                  },
                                  onMenuPressed: () => _showSingleNodeOptions(node),
                                );
                              },
                            )),
            ),

            // Multi-Select Bottom Action Toolbar
            if (_isSelectionMode)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                      width: 0.5,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _toolbarButton(
                        icon: CupertinoIcons.share,
                        label: 'Share',
                        enabled: _selectedPaths.isNotEmpty,
                        onTap: () => FileOperationService.instance.shareItems(_selectedNodes),
                        isDark: isDark,
                      ),
                      if (_selectedNodes.length == 1 && !_selectedNodes.first.isDirectory)
                        _toolbarButton(
                          icon: CupertinoIcons.arrow_up_right_square,
                          label: 'Open with',
                          enabled: true,
                          onTap: () => FileOperationService.instance.openWith(_selectedNodes.first),
                          isDark: isDark,
                        ),
                      if (_selectedNodes.length == 1 && _selectedNodes.first.isVideo)
                        _toolbarButton(
                          icon: CupertinoIcons.scissors,
                          label: 'Trim',
                          enabled: true,
                          onTap: () => _openTrimScreen(_selectedNodes.first),
                          isDark: isDark,
                        ),
                      if (_selectedNodes.length >= 2 && _selectedNodes.every((n) => n.isVideo))
                        _toolbarButton(
                          icon: CupertinoIcons.layers_alt,
                          label: 'Merge',
                          enabled: true,
                          onTap: () => _openMergeDialog(_selectedNodes),
                          isDark: isDark,
                        ),
                      _toolbarButton(
                        icon: CupertinoIcons.doc_on_doc,
                        label: 'Copy',
                        enabled: _selectedPaths.isNotEmpty,
                        onTap: () => _handleBatchTransfer(isMove: false),
                        isDark: isDark,
                      ),
                      _toolbarButton(
                        icon: CupertinoIcons.arrow_right_arrow_left,
                        label: 'Move',
                        enabled: _selectedPaths.isNotEmpty,
                        onTap: () => _handleBatchTransfer(isMove: true),
                        isDark: isDark,
                      ),
                      if (SafeVaultService.instance.isVaultEnabled)
                        _toolbarButton(
                          icon: CupertinoIcons.lock_shield_fill,
                          label: 'Vault',
                          enabled: _selectedPaths.isNotEmpty,
                          onTap: () => _handleMoveToVault(
                            _selectedNodes.where((n) => !n.isDirectory).toList(),
                          ),
                          isDark: isDark,
                        ),
                      _toolbarButton(
                        icon: CupertinoIcons.trash,
                        label: 'Delete',
                        isDestructive: true,
                        enabled: _selectedPaths.isNotEmpty,
                        onTap: _handleBatchDelete,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool enabled = true,
    bool isDestructive = false,
  }) {
    final color = !enabled
        ? (isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight)
        : isDestructive
            ? AppleColors.systemRed
            : (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight);

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      onPressed: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
