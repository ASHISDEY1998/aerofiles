import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import '../../models/vfs_node.dart';
import '../../services/log_service.dart';
import '../../services/security/safe_vault_service.dart';
import '../../theme/apple_theme.dart';
import '../player/image_viewer_screen.dart';
import '../player/universal_audio_player_screen.dart';
import '../player/universal_video_player_screen.dart';
import 'vault_pin_dialog.dart';

class SafeVaultScreen extends StatefulWidget {
  const SafeVaultScreen({super.key});

  @override
  State<SafeVaultScreen> createState() => _SafeVaultScreenState();
}

class _SafeVaultScreenState extends State<SafeVaultScreen> {
  final _vaultService = SafeVaultService.instance;
  bool _isLoading = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyUnlock();
    });
  }

  @override
  void dispose() {
    // Purge temporary decrypted files when exiting the Safe Vault screen
    _vaultService.clearPreviewCache();
    super.dispose();
  }

  Future<void> _verifyUnlock() async {
    if (_vaultService.isUnlocked) {
      setState(() {});
      return;
    }

    if (!_vaultService.hasPin) {
      final created = await VaultPinDialog.show(
        context,
        mode: VaultPinMode.setup,
      );
      if (!created || !_vaultService.isUnlocked) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
    } else {
      final unlocked = await VaultPinDialog.show(
        context,
        mode: VaultPinMode.unlock,
      );
      if (!unlocked || !_vaultService.isUnlocked) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _lockVault() async {
    HapticFeedback.mediumImpact();
    _vaultService.lock();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openItem(VaultItem item) async {
    if (_isSelectionMode) {
      _toggleSelection(item.id);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Decrypting ${item.fileName}...';
    });

    try {
      final file = await _vaultService.getDecryptedPreviewFile(item);
      if (file == null || !await file.exists()) {
        _showToast('Failed to decrypt file');
        return;
      }

      if (!mounted) return;

      if (item.isVideo) {
        await Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => UniversalVideoPlayerScreen(
              title: item.fileName,
              playbackUri: file.path,
            ),
          ),
        );
      } else if (item.isImage) {
        final vNode = VfsNode(
          path: file.path,
          name: item.fileName,
          size: item.size,
          modified: item.dateAdded,
          isDirectory: false,
        );
        final deleted = await Navigator.push<bool>(
          context,
          CupertinoPageRoute(
            builder: (_) => ImageViewerScreen(
              images: [vNode],
              initialIndex: 0,
            ),
          ),
        );
        if (deleted == true && mounted) {
          setState(() {});
        }
      } else if (item.isAudio) {
        final vNode = VfsNode(
          path: file.path,
          name: item.fileName,
          size: item.size,
          modified: item.dateAdded,
          isDirectory: false,
        );
        final deleted = await Navigator.push<bool>(
          context,
          CupertinoPageRoute(
            builder: (_) => UniversalAudioPlayerScreen(
              playlist: [vNode],
              initialIndex: 0,
            ),
          ),
        );
        if (deleted == true && mounted) {
          setState(() {});
        }
      } else {
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted) {
          _showToast('No app found to open ${item.fileName}');
        }
      }
    } catch (e) {
      LogService.instance.error('VAULT', 'Error previewing item: $e');
      _showToast('Error opening item: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  void _toggleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.length == _vaultService.items.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(_vaultService.items.map((e) => e.id));
      }
    });
  }

  Future<void> _restoreItems(List<VaultItem> items) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Restore Files?'),
        content: Text(
          'Restore ${items.length} ${items.length == 1 ? "file" : "files"} back to original location and notify Android MediaScanner?',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: false,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Restoring and decrypting files...';
    });

    final success = await _vaultService.restoreFromVault(items);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
        _selectedIds.clear();
        _isSelectionMode = false;
      });

      if (success) {
        _showToast('Restored ${items.length} ${items.length == 1 ? "file" : "files"}');
      } else {
        _showToast('Some files could not be restored');
      }
    }
  }

  Future<void> _deletePermanently(List<VaultItem> items) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Permanently Delete?'),
        content: Text(
          'Delete ${items.length} ${items.length == 1 ? "file" : "files"} permanently? This action cannot be undone and files will NOT go to Recycle Bin.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Permanently deleting...';
    });

    await _vaultService.deletePermanently(items);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusMessage = null;
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      _showToast('Permanently deleted');
    }
  }

  void _showItemOptions(VaultItem item) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          item.fileName,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        message: Text('Original: ${item.originalPath}'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _openItem(item);
            },
            child: const Text('Open / View'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _restoreItems([item]);
            },
            child: const Text('Restore to Original Location'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _deletePermanently([item]);
            },
            child: const Text('Delete Permanently'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppleColors.darkElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  IconData _getIconForItem(VaultItem item) {
    if (item.isVideo) return CupertinoIcons.film_fill;
    if (item.isImage) return CupertinoIcons.photo_fill;
    if (item.isAudio) return CupertinoIcons.music_note_2;
    if (item.isDocument) return CupertinoIcons.doc_text_fill;
    return CupertinoIcons.doc_fill;
  }

  Color _getColorForItem(VaultItem item) {
    if (item.isVideo) return AppleColors.catVideos;
    if (item.isImage) return AppleColors.catImages;
    if (item.isAudio) return AppleColors.catAudio;
    if (item.isDocument) return AppleColors.catDocs;
    return AppleColors.catOther;
  }

  @override
  Widget build(BuildContext context) {
    final items = _vaultService.items;

    return Scaffold(
      backgroundColor: AppleColors.pureBlack,
      appBar: AppBar(
        backgroundColor: AppleColors.pureBlack,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Safe Vault',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppleColors.textPrimary,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppleColors.systemGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'AES-256 Encrypted',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppleColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (items.isNotEmpty) ...[
            if (_isSelectionMode)
              IconButton(
                icon: Icon(
                  _selectedIds.length == items.length
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  color: AppleColors.systemBlue,
                ),
                tooltip: 'Select All',
                onPressed: _selectAll,
              )
            else
              IconButton(
                icon: const Icon(
                  CupertinoIcons.checkmark_circle,
                  color: AppleColors.systemBlue,
                ),
                tooltip: 'Select',
                onPressed: () {
                  setState(() => _isSelectionMode = true);
                },
              ),
          ],
          IconButton(
            icon: const Icon(
              CupertinoIcons.lock_fill,
              color: AppleColors.systemBlue,
            ),
            tooltip: 'Lock Vault',
            onPressed: _lockVault,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          if (!_vaultService.isUnlocked)
            const SizedBox.shrink()
          else if (items.isEmpty)
            _buildEmptyState()
          else
            _buildItemsList(items),

          // Loading overlay
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: AppleColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppleColors.borderStroke),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(radius: 14),
                        const SizedBox(height: 14),
                        Text(
                          _statusMessage ?? 'Processing...',
                          style: const TextStyle(
                            color: AppleColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _isSelectionMode ? _buildSelectionBottomBar() : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppleColors.systemBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppleColors.systemBlue.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                CupertinoIcons.lock_shield_fill,
                size: 54,
                color: AppleColors.systemBlue,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Safe Vault is Empty',
              style: TextStyle(
                color: AppleColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Files moved into the Safe Vault are encrypted with AES-256, shielded behind your custom PIN & fingerprint, and completely hidden from Android MediaScanner and gallery apps.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppleColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppleColors.darkCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppleColors.borderStroke),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.info_circle_fill,
                    color: AppleColors.systemBlue,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'To protect files: Select any file in your storage and choose "Move to Safe Vault"',
                      style: TextStyle(
                        color: AppleColors.textSecondary,
                        fontSize: 12,
                      ),
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

  Widget _buildItemsList(List<VaultItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedIds.contains(item.id);
        final color = _getColorForItem(item);
        final icon = _getIconForItem(item);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openItem(item),
            onLongPress: () {
              if (!_isSelectionMode) {
                setState(() {
                  _isSelectionMode = true;
                  _selectedIds.add(item.id);
                });
                HapticFeedback.heavyImpact();
              } else {
                _showItemOptions(item);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppleColors.systemBlue.withValues(alpha: 0.15)
                    : AppleColors.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppleColors.systemBlue
                      : AppleColors.borderStroke,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  if (_isSelectionMode) ...[
                    Icon(
                      isSelected
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      color: isSelected
                          ? AppleColors.systemBlue
                          : AppleColors.textTertiary,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Category icon
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 14),

                  // File details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          style: const TextStyle(
                            color: AppleColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _formatSize(item.size),
                              style: const TextStyle(
                                color: AppleColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const Text(
                              ' • ',
                              style: TextStyle(
                                color: AppleColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _formatDate(item.dateAdded),
                              style: const TextStyle(
                                color: AppleColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Overflow actions
                  if (!_isSelectionMode)
                    IconButton(
                      icon: const Icon(
                        CupertinoIcons.ellipsis_vertical,
                        color: AppleColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => _showItemOptions(item),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectionBottomBar() {
    final selectedItems = _vaultService.items
        .where((e) => _selectedIds.contains(e.id))
        .toList();

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: const BoxDecoration(
        color: AppleColors.darkCard,
        border: Border(top: BorderSide(color: AppleColors.borderStroke)),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedIds.length} Selected',
            style: const TextStyle(
              color: AppleColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),

          // Cancel
          TextButton(
            onPressed: () {
              setState(() {
                _selectedIds.clear();
                _isSelectionMode = false;
              });
            },
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),

          // Restore
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppleColors.systemBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(CupertinoIcons.arrow_counterclockwise, size: 16),
            label: const Text('Restore'),
            onPressed: selectedItems.isEmpty
                ? null
                : () => _restoreItems(selectedItems),
          ),
          const SizedBox(width: 8),

          // Delete Permanently
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppleColors.systemRed.withValues(alpha: 0.2),
              foregroundColor: AppleColors.systemRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(CupertinoIcons.trash, size: 16),
            label: const Text('Delete'),
            onPressed: selectedItems.isEmpty
                ? null
                : () => _deletePermanently(selectedItems),
          ),
        ],
      ),
    );
  }
}
