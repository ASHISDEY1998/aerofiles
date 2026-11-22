import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../models/vfs_node.dart';
import '../../services/file_operation_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/file_tile.dart';
import '../common/destination_picker_screen.dart';
import '../player/image_viewer_screen.dart';
import '../player/universal_video_player_screen.dart';

enum CategorySort { newToOld, oldToNew, nameAsc, nameDesc, sizeDesc, sizeAsc }

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
  bool _isGrid = false;
  bool _showSearch = false;
  String _searchQuery = '';
  CategorySort _sort = CategorySort.newToOld;

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.items);
  }

  List<VfsNode> get _displayItems {
    var list = _currentItems;
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
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => UniversalVideoPlayerScreen(
            title: node.name,
            playbackUri: node.path,
            playlist: videoItems.isNotEmpty ? videoItems : [node],
            initialIndex: index != -1 ? index : 0,
            vfs: widget.localVfs,
          ),
        ),
      );
    } else if (node.isImage) {
      final allImages = _displayItems.where((e) => e.isImage).toList();
      final index = allImages.indexWhere((e) => e.path == node.path);
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => ImageViewerScreen(
            images: allImages.isNotEmpty ? allImages : [node],
            initialIndex: index != -1 ? index : 0,
            vfs: widget.localVfs,
          ),
        ),
      );
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

  List<VfsNode> get _selectedNodes =>
      _currentItems.where((e) => _selectedPaths.contains(e.path)).toList();

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

    // Otherwise behavior is DeleteBehavior.ask: show full delete prompt
    bool moveToTrash = true;
    bool rememberChoice = false;

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

                  // Option 1: Move to Recycle Bin
                  GestureDetector(
                    onTap: () => setDialogState(() => moveToTrash = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: moveToTrash
                            ? (isDark
                                ? AppleColors.systemBlue.withValues(alpha: 0.2)
                                : AppleColors.systemBlueLight.withValues(alpha: 0.15))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            moveToTrash ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            color: moveToTrash ? AppleColors.systemBlue : AppleColors.textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Move to Recycle Bin', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text('Can be restored anytime', style: TextStyle(fontSize: 11, color: AppleColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Option 2: Delete Permanently
                  GestureDetector(
                    onTap: () => setDialogState(() => moveToTrash = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: !moveToTrash
                            ? (isDark
                                ? AppleColors.systemRed.withValues(alpha: 0.2)
                                : AppleColors.systemRed.withValues(alpha: 0.15))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            !moveToTrash ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            color: !moveToTrash ? AppleColors.systemRed : AppleColors.textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text('Cannot be restored', style: TextStyle(fontSize: 11, color: AppleColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Remember choice
                  GestureDetector(
                    onTap: () => setDialogState(() => rememberChoice = !rememberChoice),
                    child: Row(
                      children: [
                        Icon(
                          rememberChoice ? CupertinoIcons.checkmark_square_fill : CupertinoIcons.square,
                          size: 18,
                          color: rememberChoice ? AppleColors.systemBlue : AppleColors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Make this the default choice',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
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
                child: Text(moveToTrash ? 'Move to Bin' : 'Delete'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (rememberChoice) {
                    await settings.setDeleteBehavior(
                      moveToTrash ? DeleteBehavior.recycleBin : DeleteBehavior.permanent,
                    );
                  }
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
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            moveToTrash
                ? '${selected.length} items moved to Recycle Bin'
                : '${selected.length} items permanently deleted',
          ),
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

    if (result != null && mounted) {
      final targetPath = result['targetPath'] as String;
      final targetVfs = result['targetVfs'] as VfsProvider;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${isMove ? "Moving" : "Copying"} ${selected.length} items to ${targetVfs.displayName}...',
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      final ops = FileOperationService.instance;
      if (isMove) {
        await ops.moveItems(
          items: selected,
          targetDirPath: targetPath,
          targetVfs: targetVfs,
          sourceVfs: widget.localVfs,
        );
        setState(() {
          _currentItems.removeWhere((e) => _selectedPaths.contains(e.path));
          _selectedPaths.clear();
          _isSelectionMode = false;
        });
      } else {
        await ops.copyItems(
          items: selected,
          targetDirPath: targetPath,
          targetVfs: targetVfs,
          sourceVfs: widget.localVfs,
        );
        setState(() {
          _selectedPaths.clear();
          _isSelectionMode = false;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selected.length} items successfully ${isMove ? "moved" : "copied"}!'),
          ),
        );
      }
    }
  }

  void _showSingleNodeOptions(VfsNode node) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(node.name),
        message: Text(node.formattedSize),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              FileOperationService.instance.showFileInfo(context, node);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.info_circle, size: 18),
                SizedBox(width: 8),
                Text('File Details'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              FileOperationService.instance.shareItems([node]);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.share, size: 18),
                SizedBox(width: 8),
                Text('Share File'),
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
              children: [
                Icon(CupertinoIcons.doc_on_doc, size: 18),
                SizedBox(width: 8),
                Text('Copy to...'),
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
              children: [
                Icon(CupertinoIcons.arrow_right_arrow_left, size: 18),
                SizedBox(width: 8),
                Text('Move to...'),
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
            child: const Text('Rename'),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != node.name) {
                Navigator.pop(ctx);
                final renamed = await widget.localVfs.rename(node.path, newName);
                if (renamed && mounted) {
                  setState(() {
                    final idx = _currentItems.indexWhere((e) => e.path == node.path);
                    if (idx != -1) {
                      _currentItems[idx] = VfsNode(
                        path: p.join(p.dirname(node.path), newName),
                        name: newName,
                        size: node.size,
                        isDirectory: node.isDirectory,
                        modified: DateTime.now(),
                      );
                    }
                  });
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayedItems = _displayItems;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${_selectedPaths.length} Selected'
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
              onPressed: () => setState(() => _isGrid = !_isGrid),
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.sort_down),
              onPressed: _showSortMenu,
            ),
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
          if (_showSearch && !_isSelectionMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CupertinoSearchTextField(
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),

          Expanded(
            child: displayedItems.isEmpty
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
                        padding: const EdgeInsets.all(16),
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
                              if (!_isSelectionMode) {
                                setState(() {
                                  _isSelectionMode = true;
                                  _selectedPaths.add(node.path);
                                });
                              }
                            },
                          );
                        },
                      )
                    : ListView.builder(
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
                              if (!_isSelectionMode) {
                                setState(() {
                                  _isSelectionMode = true;
                                  _selectedPaths.add(node.path);
                                });
                              }
                            },
                            onMenuPressed: () => _showSingleNodeOptions(node),
                          );
                        },
                      ),
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
