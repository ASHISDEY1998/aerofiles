import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/vfs_node.dart';
import '../../services/file_operation_service.dart';
import '../../services/recycle_bin_service.dart';
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
  final Map<int, TransformationController> _transformControllers = {};

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
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No images to view', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final currentImage = _imageList[_currentIndex];

    return Scaffold(
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
                      onPressed: () => Navigator.pop(context),
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
                      onPressed: () {
                        showCupertinoDialog(
                          context: context,
                          builder: (ctx) => CupertinoAlertDialog(
                            title: const Text('Delete Image?'),
                            content: Text('Are you sure you want to delete ${currentImage.name}?'),
                            actions: [
                              CupertinoDialogAction(
                                child: const Text('Cancel'),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                              CupertinoDialogAction(
                                isDestructiveAction: true,
                                child: const Text('Delete'),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  if (widget.vfs != null) {
                                    await widget.vfs!.delete(currentImage.path);
                                  } else {
                                    try {
                                      final f = File(currentImage.path);
                                      if (await f.exists()) await f.delete();
                                    } catch (_) {}
                                  }
                                  await RecycleBinService.notifyMediaScanner(currentImage.path);
                                  setState(() {
                                    _imageList.removeAt(_currentIndex);
                                    if (_imageList.isEmpty) {
                                      Navigator.pop(context);
                                    } else {
                                      _currentIndex = _currentIndex.clamp(0, _imageList.length - 1);
                                      _pageController.jumpToPage(_currentIndex);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      },
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
    );
  }
}
