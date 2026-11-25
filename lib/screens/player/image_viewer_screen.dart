import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/vfs_node.dart';
import '../../services/file_operation_service.dart';
import '../../services/log_service.dart';
import '../../services/recycle_bin_service.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/aerolink_vfs.dart';
import '../../services/vfs/local_vfs.dart';
import '../../services/vfs/vfs_provider.dart';
import '../../theme/apple_theme.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<VfsNode> images;
  final int initialIndex;
  final VfsProvider? vfs;

  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
    this.vfs,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  late List<VfsNode> _imageList;
  bool _showBars = true;
  bool _hasDeletedAny = false;
  final Map<int, TransformationController> _transformControllers = {};

  bool get _isReadOnly {
    if (widget.vfs is AeroLinkVfs) return true;
    if (_imageList.isNotEmpty && _currentIndex < _imageList.length) {
      final cur = _imageList[_currentIndex];
      if (cur.path.contains('/aerolink/stream') || cur.path.startsWith('http://') || cur.path.startsWith('https://')) {
        return true;
      }
    }
    return false;
  }

  void _confirmDeleteCurrentImage() {
    if (_imageList.isEmpty || _currentIndex >= _imageList.length) return;
    final currentImage = _imageList[_currentIndex];

    if (_isReadOnly) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppleColors.darkCard,
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
          duration: const Duration(seconds: 4),
          content: const Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_circle, color: AppleColors.systemOrange, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cannot modify remote files. AeroLink storage is read-only.',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
      Timer(const Duration(seconds: 4), () {
        messenger.hideCurrentSnackBar();
      });
      return;
    }

    final settings = SettingsService.instance;
    final behavior = settings.deleteBehavior;

    if (behavior == DeleteBehavior.recycleBin) {
      _executeDeleteCurrentImage(currentImage, moveToTrash: true);
      return;
    } else if (behavior == DeleteBehavior.permanent) {
      _confirmPermanentDelete(currentImage);
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
            title: Text('Delete "${currentImage.name}"?'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose how to delete this image:',
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Move to Recycle Bin',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Text(
                                  'Safely restore anytime from Trash',
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
                  ),
                  const SizedBox(height: 8),

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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delete Permanently',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                Text(
                                  'Cannot be undone. Space is freed now.',
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
                  ),

                  const SizedBox(height: 14),

                  // Remember choice checkbox
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
                  _executeDeleteCurrentImage(currentImage, moveToTrash: moveToTrash);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmPermanentDelete(VfsNode node) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Permanently delete "${node.name}"?'),
        content: const Text('This cannot be undone and will permanently remove this image from your storage.'),
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
              _executeDeleteCurrentImage(node, moveToTrash: false);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _executeDeleteCurrentImage(VfsNode node, {required bool moveToTrash}) async {
    LogService.instance.info('IMAGE', 'Delete requested for "${node.name}" (moveToTrash: $moveToTrash)');
    _hasDeletedAny = true;

    try {
      final vfsProvider = widget.vfs ?? LocalVfs();
      await vfsProvider.delete(node.path, moveToTrash: moveToTrash);
      await RecycleBinService.notifyMediaScanner(node.path);
      LogService.instance.info('IMAGE', 'Successfully deleted "${node.name}" from storage');

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.removeCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppleColors.darkCard,
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.down,
            duration: const Duration(seconds: 4),
            content: Text(
              moveToTrash
                  ? '"${node.name}" moved to Recycle Bin'
                  : '"${node.name}" permanently deleted',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        );
        Timer(const Duration(seconds: 4), () {
          messenger.hideCurrentSnackBar();
        });
      }

      setState(() {
        _imageList.removeAt(_currentIndex);
        if (_imageList.isEmpty) {
          Navigator.pop(context, true);
        } else {
          _currentIndex = _currentIndex.clamp(0, _imageList.length - 1);
          _pageController.jumpToPage(_currentIndex);
        }
      });
    } catch (e) {
      LogService.instance.error('IMAGE', 'Failed to delete image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleColors.darkCard,
            content: Text('Error deleting image: $e'),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _imageList = List.from(widget.images);
    _currentIndex = widget.initialIndex.clamp(0, _imageList.isEmpty ? 0 : _imageList.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TransformationController _getController(int index) {
    return _transformControllers.putIfAbsent(index, () => TransformationController());
  }

  void _toggleBars() {
    setState(() => _showBars = !_showBars);
  }

  void _handleDoubleTap(int index) {
    final controller = _getController(index);
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
    } else {
      // ignore: deprecated_member_use
      controller.value = Matrix4.identity()..scale(2.5, 2.5, 1.0);
    }
    setState(() {});
  }

  Widget _buildImageWidget(VfsNode node) {
    if (node.path.startsWith('http://') || node.path.startsWith('https://')) {
      return Image.network(
        node.path,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    }

    if (node.remoteStorageId != null && widget.vfs != null) {
      // Remote image on SMB / WebDAV / SFTP: resolve streaming URI
      return FutureBuilder<String>(
        future: widget.vfs!.getPlaybackUri(node.path),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CupertinoActivityIndicator(radius: 14, color: Colors.white),
            );
          }
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return Image.network(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _buildFallback(),
            );
          }
          return _buildFallback();
        },
      );
    }

    // Local device image
    return Image.file(
      File(node.path),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.photo, color: Colors.white24, size: 80),
        SizedBox(height: 12),
        Text(
          'Could not render image preview',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_imageList.isEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.pop(context, _hasDeletedAny);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: CupertinoNavigationBar(
            backgroundColor: Colors.transparent,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context, _hasDeletedAny),
              child: const Icon(CupertinoIcons.chevron_back, color: Colors.white, size: 28),
            ),
          ),
          body: const Center(
            child: Text('No images to view', style: TextStyle(color: Colors.white70)),
          ),
        ),
      );
    }

    final currentImage = _imageList[_currentIndex];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _hasDeletedAny);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Image PageView with Zoom and Smooth Horizontal Paging
            PageView.builder(
              controller: _pageController,
              itemCount: _imageList.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final node = _imageList[index];
                final controller = _getController(index);

                return GestureDetector(
                  onTap: _toggleBars,
                  onDoubleTap: () => _handleDoubleTap(index),
                  child: Center(
                    child: InteractiveViewer(
                      transformationController: controller,
                      minScale: 1.0,
                      maxScale: 4.5,
                      panEnabled: true,
                      scaleEnabled: true,
                      clipBehavior: Clip.none,
                      child: _buildImageWidget(node),
                    ),
                  ),
                );
              },
            ),

            // Top Apple Navigation Bar
            if (_showBars)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 6,
                    bottom: 14,
                    left: 12,
                    right: 16,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xEE000000), Colors.transparent],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context, _hasDeletedAny),
                        child: const Icon(CupertinoIcons.chevron_back, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentImage.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${_currentIndex + 1} of ${_imageList.length} • ${currentImage.formattedSize}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom Action Bar (Share, Details, Delete)
            if (_showBars)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: 14,
                    bottom: MediaQuery.of(context).padding.bottom + 12,
                    left: 24,
                    right: 24,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color(0xEE000000)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          FileOperationService.instance.shareItems([currentImage]);
                        },
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.share, color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Share', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          FileOperationService.instance.showFileInfo(context, currentImage);
                        },
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.info_circle, color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Details', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _confirmDeleteCurrentImage,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.trash, color: AppleColors.systemRed, size: 22),
                            SizedBox(height: 4),
                            Text('Delete', style: TextStyle(color: AppleColors.systemRed, fontSize: 11)),
                          ],
                        ),
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
}
