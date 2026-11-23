import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../models/vfs_node.dart';
import '../../services/file_operation_service.dart';
import '../../services/recycle_bin_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/breadcrumb_bar.dart';
import '../../widgets/file_tile.dart';
import '../common/destination_picker_screen.dart';
import '../player/image_viewer_screen.dart';
import '../player/universal_video_player_screen.dart';

enum SortBy { name, date, size, type }

class DirectoryBrowserScreen extends StatefulWidget {
  final VfsProvider vfs;
  final String initialPath;
  final String title;

  const DirectoryBrowserScreen({
    super.key,
    required this.vfs,
    required this.initialPath,
    this.title = 'Files',
  });

  @override
  State<DirectoryBrowserScreen> createState() => _DirectoryBrowserScreenState();
}

class _DirectoryBrowserScreenState extends State<DirectoryBrowserScreen> {
  late String _currentPath;
  List<VfsNode> _items = [];
  bool _isLoading = true;
  late bool _isGrid;
  String _searchQuery = '';
  bool _showSearch = false;
  SortBy _sortBy = SortBy.name;
  bool _sortAscending = true;

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};

  // Subfolder navigation history
  final List<String> _navigationHistory = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isGrid = SettingsService.instance.isGridView;
    _currentPath = widget.initialPath;
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final list = await widget.vfs.listDirectory(_currentPath);
      if (mounted) {
        setState(() {
          _items = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _items = [];
          _isLoading = false;
        });
      }
    }
  }

  void _navigateTo(String path, {bool recordHistory = true}) {
    if (recordHistory && _currentPath != path) {
      _navigationHistory.add(_currentPath);
    }
    setState(() {
      _currentPath = path;
      _searchQuery = '';
      _showSearch = false;
      _selectedPaths.clear();
      _isSelectionMode = false;
    });
    _loadDirectory();
  }

  bool _navigateUp() {
    if (_isSelectionMode) {
      setState(() {
        _isSelectionMode = false;
        _selectedPaths.clear();
      });
      return false;
    }

    if (_navigationHistory.isNotEmpty) {
      final previousPath = _navigationHistory.removeLast();
      _navigateTo(previousPath, recordHistory: false);
      return false;
    }

    final root = widget.initialPath;
    if (_currentPath != root &&
        _currentPath.isNotEmpty &&
        _currentPath != '/' &&
        _currentPath != widget.vfs.rootPath) {
      final parent = p.dirname(_currentPath);
      final normalizedParent = (parent == '.' || parent == '/') ? '' : parent;
      _navigateTo(normalizedParent, recordHistory: false);
      return false;
    }

    return true; // Reached root, can exit screen
  }

  List<VfsNode> get _filteredAndSortedItems {
    var result = _items;
    if (!SettingsService.instance.showHiddenFiles) {
      result = result.where((e) => !e.name.startsWith('.')).toList();
    }

    if (_searchQuery.isNotEmpty) {
      result = result.where((e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    result.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;

      int comp = 0;
      switch (_sortBy) {
        case SortBy.name:
          comp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortBy.date:
          comp = a.modified.compareTo(b.modified);
          break;
        case SortBy.size:
          comp = a.size.compareTo(b.size);
          break;
        case SortBy.type:
          comp = a.extension.compareTo(b.extension);
          break;
      }
      return _sortAscending ? comp : -comp;
    });

    return result;
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
    final displayed = _filteredAndSortedItems;
    setState(() {
      if (_selectedPaths.length == displayed.length) {
        _selectedPaths.clear();
        _isSelectionMode = false;
      } else {
        _selectedPaths.addAll(displayed.map((e) => e.path));
      }
    });
  }

  List<VfsNode> get _selectedNodes =>
      _items.where((e) => _selectedPaths.contains(e.path)).toList();

  void _handleNodeTap(VfsNode node) async {
    if (_isSelectionMode) {
      _toggleSelection(node);
      return;
    }

    if (node.isDirectory) {
      _navigateTo(node.path, recordHistory: true);
    } else if (node.isVideo) {
      final videoItems = _filteredAndSortedItems.where((e) => e.isVideo).toList();
      final index = videoItems.indexWhere((e) => e.path == node.path);
      final playbackUri = await widget.vfs.getPlaybackUri(node.path);
      if (!mounted) return;
      final deleted = await Navigator.push<bool>(
        context,
        CupertinoPageRoute(
          builder: (_) => UniversalVideoPlayerScreen(
            title: node.name,
            playbackUri: playbackUri,
            playlist: videoItems.isNotEmpty ? videoItems : [node],
            initialIndex: index != -1 ? index : 0,
            vfs: widget.vfs,
          ),
        ),
      );
      if (deleted == true && mounted) {
        _loadDirectory();
      }
    } else if (node.isImage) {
      final allImages = _filteredAndSortedItems.where((e) => e.isImage).toList();
      final index = allImages.indexWhere((e) => e.path == node.path);
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => ImageViewerScreen(
            images: allImages.isNotEmpty ? allImages : [node],
            initialIndex: index != -1 ? index : 0,
            vfs: widget.vfs,
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
        title: const Text('Sort Items By'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sortBy = SortBy.name);
              Navigator.pop(ctx);
            },
            child: Text('Name ${_sortBy == SortBy.name ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sortBy = SortBy.date);
              Navigator.pop(ctx);
            },
            child: Text('Date Modified ${_sortBy == SortBy.date ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sortBy = SortBy.size);
              Navigator.pop(ctx);
            },
            child: Text('Size ${_sortBy == SortBy.size ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sortBy = SortBy.type);
              Navigator.pop(ctx);
            },
            child: Text('Type ${_sortBy == SortBy.type ? '✓' : ''}'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _sortAscending = !_sortAscending);
              Navigator.pop(ctx);
            },
            child: Text(_sortAscending ? 'Order: Ascending ↑' : 'Order: Descending ↓'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              final cur = SettingsService.instance.showHiddenFiles;
              SettingsService.instance.setShowHiddenFiles(!cur);
              setState(() {});
            },
            child: Text(
              SettingsService.instance.showHiddenFiles
                  ? 'Hide Hidden Files (dotfiles)'
                  : 'Show Hidden Files & Folders',
              style: TextStyle(
                color: SettingsService.instance.showHiddenFiles
                    ? AppleColors.systemOrange
                    : AppleColors.systemBlue,
              ),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ),
    );
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('New Folder'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Folder Name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            child: const Text('Create'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                await widget.vfs.createDirectory(_currentPath, name);
                _loadDirectory();
              }
            },
          ),
        ],
      ),
    );
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
    RecycleBinService.instance.clearRecentlyTrashed();
    for (final node in selected) {
      await widget.vfs.delete(node.path, moveToTrash: moveToTrash);
    }
    _loadDirectory();
    setState(() {
      _selectedPaths.clear();
      _isSelectionMode = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            moveToTrash
                ? (selected.length == 1
                    ? '"${selected.first.name}" moved to Recycle Bin'
                    : '${selected.length} items moved to Recycle Bin')
                : '${selected.length} items permanently deleted',
          ),
          action: moveToTrash
              ? SnackBarAction(
                  label: 'Undo',
                  textColor: AppleColors.systemBlue,
                  onPressed: () async {
                    final count = await RecycleBinService.instance.restoreRecentlyTrashed();
                    if (mounted) {
                      _loadDirectory();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          content: Text('$count item${count == 1 ? '' : 's'} restored'),
                        ),
                      );
                    }
                  },
                )
              : null,
        ),
      );
    }
  }

  void _handleKeyboardCopy() {
    if (_selectedNodes.isEmpty) return;
    final count = _selectedNodes.length;
    FileOperationService.instance.clipboardItems = List.from(_selectedNodes);
    FileOperationService.instance.isClipboardCut = false;
    FileOperationService.instance.clipboardSourceVfs = widget.vfs;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $count item${count == 1 ? '' : 's'} to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppleColors.darkCard
            : AppleColors.lightCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleKeyboardCut() {
    if (_selectedNodes.isEmpty) return;
    final count = _selectedNodes.length;
    FileOperationService.instance.clipboardItems = List.from(_selectedNodes);
    FileOperationService.instance.isClipboardCut = true;
    FileOperationService.instance.clipboardSourceVfs = widget.vfs;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cut $count item${count == 1 ? '' : 's'} to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppleColors.darkCard
            : AppleColors.lightCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleKeyboardPaste() async {
    final clip = FileOperationService.instance.clipboardItems;
    if (clip.isEmpty) return;

    final isCut = FileOperationService.instance.isClipboardCut;
    final sourceVfs = FileOperationService.instance.clipboardSourceVfs ?? widget.vfs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const CupertinoActivityIndicator(radius: 8),
            const SizedBox(width: 12),
            Text('Pasting ${clip.length} item${clip.length == 1 ? '' : 's'}...'),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: isDark ? AppleColors.darkCard : AppleColors.lightCard,
        behavior: SnackBarBehavior.floating,
      ),
    );

    bool ok = false;
    if (isCut) {
      ok = await FileOperationService.instance.moveItems(
        items: clip,
        targetDirPath: _currentPath,
        targetVfs: widget.vfs,
        sourceVfs: sourceVfs,
      );
      if (ok) {
        FileOperationService.instance.clipboardItems.clear();
      }
    } else {
      ok = await FileOperationService.instance.copyItems(
        items: clip,
        targetDirPath: _currentPath,
        targetVfs: widget.vfs,
        sourceVfs: sourceVfs,
      );
    }

    if (mounted) {
      _loadDirectory();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Successfully pasted ${clip.length} item${clip.length == 1 ? '' : 's'}'
              : 'Failed to paste some items'),
          duration: const Duration(seconds: 3),
          backgroundColor: isDark ? AppleColors.darkCard : AppleColors.lightCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleBatchTransfer({required bool isMove}) async {
    final selected = _selectedNodes;
    if (selected.isEmpty) return;

    final localVfs = widget.vfs is LocalVfs ? (widget.vfs as LocalVfs) : LocalVfs();

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      CupertinoPageRoute(
        builder: (_) => DestinationPickerScreen(
          actionTitle: isMove ? 'Move to' : 'Copy to',
          itemsToTransfer: selected,
          localVfs: localVfs,
        ),
      ),
    );

    if (result != null && mounted) {
      final targetPath = result['targetPath'] as String;
      final targetVfs = result['targetVfs'] as VfsProvider;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isMove ? "Moving" : "Copying"} ${selected.length} items to ${targetVfs.displayName}...'),
          duration: const Duration(seconds: 2),
        ),
      );

      final ops = FileOperationService.instance;
      if (isMove) {
        await ops.moveItems(
          items: selected,
          targetDirPath: targetPath,
          targetVfs: targetVfs,
          sourceVfs: widget.vfs,
        );
      } else {
        await ops.copyItems(
          items: selected,
          targetDirPath: targetPath,
          targetVfs: targetVfs,
          sourceVfs: widget.vfs,
        );
      }

      _loadDirectory();
      setState(() {
        _selectedPaths.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selected.length} items successfully ${isMove ? "moved" : "copied"}!'),
          ),
        );
      }
    }
  }

  void _showNodeOptions(VfsNode node) {
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
                await widget.vfs.rename(node.path, newName);
                _loadDirectory();
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
    final displayedItems = _filteredAndSortedItems;
    final bool isAtRoot = _navigationHistory.isEmpty &&
        (_currentPath == widget.initialPath ||
            _currentPath.isEmpty ||
            _currentPath == widget.vfs.rootPath ||
            _currentPath == '/');

    return PopScope(
      canPop: isAtRoot && !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final canExit = _navigateUp();
        if (canExit && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          final isCmdOrCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;

          // Cmd/Ctrl + A: Select All
          if (isCmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
            if (!_isSelectionMode) {
              setState(() => _isSelectionMode = true);
            }
            _selectAll();
            return KeyEventResult.handled;
          }

          // Cmd/Ctrl + C: Copy selected
          if (isCmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
            if (_selectedNodes.isNotEmpty) {
              _handleKeyboardCopy();
              return KeyEventResult.handled;
            }
          }

          // Cmd/Ctrl + X: Cut selected
          if (isCmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
            if (_selectedNodes.isNotEmpty) {
              _handleKeyboardCut();
              return KeyEventResult.handled;
            }
          }

          // Cmd/Ctrl + V: Paste clipboard
          if (isCmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
            if (FileOperationService.instance.clipboardItems.isNotEmpty) {
              _handleKeyboardPaste();
              return KeyEventResult.handled;
            }
          }

          // Delete or Backspace: Move to Recycle Bin
          if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_selectedNodes.isNotEmpty) {
              _handleBatchDelete();
              return KeyEventResult.handled;
            }
          }

          // Space: Quick Preview
          if (event.logicalKey == LogicalKeyboardKey.space) {
            if (_selectedNodes.length == 1) {
              _handleNodeTap(_selectedNodes.first);
              return KeyEventResult.handled;
            } else if (_filteredAndSortedItems.isNotEmpty && _selectedNodes.isEmpty) {
              _handleNodeTap(_filteredAndSortedItems.first);
              return KeyEventResult.handled;
            }
          }

          // Escape: Clear selection
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_isSelectionMode) {
              setState(() {
                _isSelectionMode = false;
                _selectedPaths.clear();
              });
              return KeyEventResult.handled;
            }
          }

          return KeyEventResult.ignored;
        },
        child: Scaffold(
        backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
        appBar: AppBar(
          title: Text(
            _isSelectionMode
                ? '${_selectedPaths.length} Selected'
                : (p.basename(_currentPath).isEmpty ? widget.title : p.basename(_currentPath)),
          ),
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(CupertinoIcons.xmark),
                  onPressed: () => setState(() {
                    _isSelectionMode = false;
                    _selectedPaths.clear();
                  }),
                )
              : IconButton(
                  icon: const Icon(CupertinoIcons.chevron_back),
                  onPressed: () {
                    final canExit = _navigateUp();
                    if (canExit) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
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
              IconButton(
                icon: const Icon(CupertinoIcons.folder_badge_plus),
                onPressed: _showCreateFolderDialog,
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
            // Search Bar
            if (_showSearch && !_isSelectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: CupertinoSearchTextField(
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

            // Breadcrumbs
            BreadcrumbBar(
              currentPath: _currentPath,
              rootPath: widget.vfs.rootPath,
              onPathSelected: (targetPath) => _navigateTo(targetPath, recordHistory: true),
            ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.wifi_exclamationmark,
                                size: 56,
                                color: AppleColors.systemOrange,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Connection Failed',
                                style: TextStyle(
                                  color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 20),
                              CupertinoButton.filled(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                onPressed: _loadDirectory,
                                child: const Text('Retry Connection', style: TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : displayedItems.isEmpty
                        ? Center(
                            child: Text(
                              'This folder is empty',
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
                                vfs: widget.vfs,
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
                            itemCount: displayedItems.length,
                            itemBuilder: (context, index) {
                              final node = displayedItems[index];
                              final isSelected = _selectedPaths.contains(node.path);

                              return FileTile(
                                node: node,
                                isGrid: false,
                                isSelectable: _isSelectionMode,
                                isSelected: isSelected,
                                vfs: widget.vfs,
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
                                onMenuPressed: () => _showNodeOptions(node),
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
