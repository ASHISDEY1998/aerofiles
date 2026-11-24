import 'dart:collection';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/vfs_node.dart';
import '../../services/settings_service.dart';
import '../../services/vfs/local_vfs.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import 'category_browser_screen.dart';

class LibraryTab extends StatefulWidget {
  final LocalVfs localVfs;

  const LibraryTab({super.key, required this.localVfs});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  final Map<FileCategory, List<VfsNode>> _categorizedFiles = {
    FileCategory.video: [],
    FileCategory.image: [],
    FileCategory.audio: [],
    FileCategory.document: [],
  };
  final List<VfsNode> _recentFiles = [];
  bool _isLoading = true;
  bool _isGrid = true;

  @override
  void initState() {
    super.initState();
    _isGrid = SettingsService.instance.isGridView;
    _scanLibrary();
  }

  Future<void> _scanLibrary() async {
    setState(() => _isLoading = true);
    final rootPath = widget.localVfs.rootPath;
    final now = DateTime.now();

    final Map<FileCategory, List<VfsNode>> freshCategorized = {
      FileCategory.video: [],
      FileCategory.image: [],
      FileCategory.audio: [],
      FileCategory.document: [],
    };
    final List<VfsNode> freshRecent = [];

    final queue = Queue<Directory>();
    final visited = <String>{};

    // Priority media folders
    final targetDirs = [
      'DCIM',
      'Download',
      'Pictures',
      'Movies',
      'Music',
      'Documents',
      'Recordings',
      'Podcasts',
      'WhatsApp/Media',
      'Android/media/com.whatsapp/WhatsApp/Media',
    ];

    for (final dirName in targetDirs) {
      final d = Directory(p.join(rootPath, dirName));
      if (d.existsSync()) queue.add(d);
    }
    queue.add(Directory(rootPath));

    int count = 0;
    while (queue.isNotEmpty && count < 8000) {
      final dir = queue.removeFirst();
      final path = dir.path;

      if (visited.contains(path)) continue;
      visited.add(path);

      if (path.contains('/Android/data') ||
          path.contains('/Android/obb') ||
          path.contains('/.aerofiles_trash') ||
          path.contains('/.aerofiles_vault')) {
        continue;
      }

      try {
        final list = dir.listSync(followLinks: false);
        for (final entity in list) {
          count++;
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (!name.startsWith('.') && name != 'Android') {
              queue.add(entity);
            }
          } else if (entity is File) {
            try {
              if (!entity.existsSync()) continue;
              final stat = entity.statSync();
              final node = VfsNode(
                path: entity.path,
                name: p.basename(entity.path),
                size: stat.size,
                isDirectory: false,
                modified: stat.modified,
              );

              if (freshCategorized.containsKey(node.category)) {
                freshCategorized[node.category]!.add(node);
              }

              if (now.difference(stat.modified).inDays <= 7) {
                freshRecent.add(node);
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    freshRecent.sort((a, b) => b.modified.compareTo(a.modified));
    for (final key in freshCategorized.keys) {
      freshCategorized[key]!.sort((a, b) => b.modified.compareTo(a.modified));
    }

    if (mounted) {
      setState(() {
        _recentFiles.clear();
        _recentFiles.addAll(freshRecent);
        for (final entry in freshCategorized.entries) {
          _categorizedFiles[entry.key] = entry.value;
        }
        _isLoading = false;
      });
    }
  }

  void _openCategory(String title, List<VfsNode> items) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => CategoryBrowserScreen(
          title: title,
          items: items,
          localVfs: widget.localVfs,
        ),
      ),
    ).then((_) => _scanLibrary());
  }

  Widget _buildLibraryCard({
    required IconData icon,
    required Color color,
    required String title,
    required List<VfsNode> items,
  }) {
    int totalBytes = 0;
    for (final i in items) {
      totalBytes += i.size;
    }
    String sizeStr = '';
    if (totalBytes < 1024 * 1024) {
      sizeStr = '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else if (totalBytes < 1024 * 1024 * 1024) {
      sizeStr = '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      sizeStr = '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    final folderCount = items.map((e) => p.dirname(e.path)).toSet().length;
    final countLabel = folderCount > 1
        ? '${items.length} files in $folderCount folders • $sizeStr'
        : '${items.length} files • $sizeStr';

    return AppleCard(
      onTap: () => _openCategory(title, items),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppleColors.textPrimary
                        : AppleColors.textPrimaryLight,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  countLabel,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppleColors.textSecondary
                        : AppleColors.textSecondaryLight,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppleColors.textTertiary
                : AppleColors.textTertiaryLight,
          ),
        ],
      ),
    );
  }

  Widget _buildGridCategoryItem({
    required IconData icon,
    required Color color,
    required String title,
    required List<VfsNode> items,
    required bool isDark,
  }) {
    int totalBytes = 0;
    for (final i in items) {
      totalBytes += i.size;
    }
    String sizeStr = '';
    if (totalBytes < 1024 * 1024) {
      sizeStr = '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else if (totalBytes < 1024 * 1024 * 1024) {
      sizeStr = '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      sizeStr = '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    final countStr = '${items.length} files • $sizeStr';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openCategory(title, items),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Borderless Logo / Icon Squircle
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                countStr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(
              'Media Library',
              style: TextStyle(color: isDark ? Colors.white : AppleColors.textPrimaryLight),
            ),
            backgroundColor: isDark ? const Color(0xCC000000) : const Color(0xCCF2F2F7),
            border: null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() {
                      _isGrid = !_isGrid;
                    });
                    SettingsService.instance.setGridView(_isGrid);
                  },
                  child: Icon(
                    _isGrid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
                    size: 20,
                    color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _scanLibrary,
                  child: Icon(
                    CupertinoIcons.arrow_clockwise,
                    size: 20,
                    color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            sliver: _isLoading
                ? const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoActivityIndicator(radius: 14),
                          SizedBox(height: 12),
                          Text('Scanning media library...', style: TextStyle(color: AppleColors.textSecondary)),
                        ],
                      ),
                    ),
                  )
                : _isGrid
                    ? SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.96,
                        ),
                        delegate: SliverChildListDelegate([
                          _buildGridCategoryItem(
                            icon: CupertinoIcons.play_rectangle_fill,
                            color: AppleColors.catVideos,
                            title: 'Videos',
                            items: _categorizedFiles[FileCategory.video]!,
                            isDark: isDark,
                          ),
                          _buildGridCategoryItem(
                            icon: CupertinoIcons.photo_fill,
                            color: AppleColors.catImages,
                            title: 'Images',
                            items: _categorizedFiles[FileCategory.image]!,
                            isDark: isDark,
                          ),
                          _buildGridCategoryItem(
                            icon: CupertinoIcons.music_note_2,
                            color: AppleColors.catAudio,
                            title: 'Audio',
                            items: _categorizedFiles[FileCategory.audio]!,
                            isDark: isDark,
                          ),
                          _buildGridCategoryItem(
                            icon: CupertinoIcons.doc_text_fill,
                            color: AppleColors.catDocs,
                            title: 'Documents',
                            items: _categorizedFiles[FileCategory.document]!,
                            isDark: isDark,
                          ),
                          _buildGridCategoryItem(
                            icon: CupertinoIcons.clock_fill,
                            color: AppleColors.systemPurple,
                            title: 'Recent Files',
                            items: _recentFiles,
                            isDark: isDark,
                          ),
                        ]),
                      )
                    : SliverList(
                        delegate: SliverChildListDelegate([
                          _buildLibraryCard(
                            icon: CupertinoIcons.play_rectangle_fill,
                            color: AppleColors.catVideos,
                            title: 'Videos',
                            items: _categorizedFiles[FileCategory.video]!,
                          ),
                          const SizedBox(height: 10),
                          _buildLibraryCard(
                            icon: CupertinoIcons.photo_fill,
                            color: AppleColors.catImages,
                            title: 'Images',
                            items: _categorizedFiles[FileCategory.image]!,
                          ),
                          const SizedBox(height: 10),
                          _buildLibraryCard(
                            icon: CupertinoIcons.music_note_2,
                            color: AppleColors.catAudio,
                            title: 'Audio',
                            items: _categorizedFiles[FileCategory.audio]!,
                          ),
                          const SizedBox(height: 10),
                          _buildLibraryCard(
                            icon: CupertinoIcons.doc_text_fill,
                            color: AppleColors.catDocs,
                            title: 'Documents',
                            items: _categorizedFiles[FileCategory.document]!,
                          ),
                          const SizedBox(height: 10),
                          _buildLibraryCard(
                            icon: CupertinoIcons.clock_fill,
                            color: AppleColors.systemPurple,
                            title: 'Recent Files',
                            items: _recentFiles,
                          ),
                          const SizedBox(height: 24),
                        ]),
                      ),
          ),
        ],
      ),
    );
  }
}


