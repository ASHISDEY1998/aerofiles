import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/storage_info.dart';
import '../../models/vfs_node.dart';
import '../../services/recycle_bin_service.dart';
import '../../services/storage_analyzer_service.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';
import '../../widgets/storage_donut_chart.dart';

class StorageAnalysisScreen extends StatefulWidget {
  final String rootPath;

  const StorageAnalysisScreen({super.key, required this.rootPath});

  @override
  State<StorageAnalysisScreen> createState() => _StorageAnalysisScreenState();
}

class _StorageAnalysisScreenState extends State<StorageAnalysisScreen> {
  final _analyzer = StorageAnalyzerService();
  StorageInfo? _info;
  bool _isLoading = true;
  int _selectedTabIndex = 0; // 0: Overview, 1: Large Files, 2: Duplicates

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    setState(() => _isLoading = true);
    final result = await _analyzer.analyze(widget.rootPath);
    if (mounted) {
      setState(() {
        _info = result;
        _isLoading = false;
      });
    }
  }

  int get _totalWastedDuplicateBytes {
    if (_info == null) return 0;
    return _info!.duplicateGroups.fold<int>(0, (sum, g) => sum + g.totalWastedBytes);
  }

  Future<void> _cleanDuplicateGroup(DuplicateGroup group) async {
    RecycleBinService.instance.clearRecentlyTrashed();
    // Keep first file as original, remove the rest
    final copies = group.files.skip(1).toList();
    int freed = 0;

    for (final node in copies) {
      final ok = await RecycleBinService.instance.moveToTrash(node.path);
      if (ok) freed += node.size;
    }

    if (mounted) {
      setState(() {
        _info!.duplicateGroups.remove(group);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('Freed ${StorageInfo.formatBytes(freed)} by removing ${copies.length} duplicate copies'),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppleColors.systemBlue,
            onPressed: () async {
              await RecycleBinService.instance.restoreRecentlyTrashed();
              _runAnalysis();
            },
          ),
        ),
      );
    }
  }

  Future<void> _cleanAllDuplicates() async {
    if (_info == null || _info!.duplicateGroups.isEmpty) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clean All Duplicates?'),
        content: Text(
          'This will keep the first original copy of each file and move all ${_info!.duplicateGroups.length} duplicate copies to the Recycle Bin (${StorageInfo.formatBytes(_totalWastedDuplicateBytes)}). You can undo this action.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Clean Duplicates'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    RecycleBinService.instance.clearRecentlyTrashed();
    int totalFreed = 0;
    int totalCopies = 0;

    final groups = List<DuplicateGroup>.from(_info!.duplicateGroups);
    for (final group in groups) {
      final copies = group.files.skip(1).toList();
      for (final node in copies) {
        final ok = await RecycleBinService.instance.moveToTrash(node.path);
        if (ok) {
          totalFreed += node.size;
          totalCopies++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _info!.duplicateGroups.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('Freed ${StorageInfo.formatBytes(totalFreed)} by removing $totalCopies duplicate copies'),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppleColors.systemBlue,
            onPressed: () async {
              await RecycleBinService.instance.restoreRecentlyTrashed();
              _runAnalysis();
            },
          ),
        ),
      );
    }
  }

  Future<void> _deleteLargeFile(VfsNode file) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Delete "${file.name}"?'),
        content: Text('Size: ${file.formattedSize}\nThis will move the file to the Recycle Bin.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Move to Bin'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    RecycleBinService.instance.clearRecentlyTrashed();
    final ok = await RecycleBinService.instance.moveToTrash(file.path);
    if (ok && mounted) {
      setState(() {
        _info!.largeFiles.remove(file);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('"${file.name}" moved to Recycle Bin'),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppleColors.systemBlue,
            onPressed: () async {
              await RecycleBinService.instance.restoreRecentlyTrashed();
              _runAnalysis();
            },
          ),
        ),
      );
    }
  }

  Widget _buildLegendItem(String label, int bytes, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            StorageInfo.formatBytes(bytes),
            style: TextStyle(
              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      appBar: AppBar(
        title: const Text('Storage Analyzer'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_clockwise),
            tooltip: 'Rescan Storage',
            onPressed: _runAnalysis,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(radius: 16),
                  const SizedBox(height: 16),
                  Text(
                    'Scanning storage, large files & duplicates...',
                    style: TextStyle(
                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Top Tab Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSegmentedControl<int>(
                      groupValue: _selectedTabIndex,
                      selectedColor: AppleColors.systemBlue,
                      unselectedColor: isDark ? AppleColors.pureBlack : Colors.white,
                      borderColor: AppleColors.systemBlue.withValues(alpha: 0.5),
                      children: {
                        0: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text('Overview', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        1: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text('Large (${_info?.largeFiles.length ?? 0})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        2: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text('Duplicates (${_info?.duplicateGroups.length ?? 0})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      },
                      onValueChanged: (val) => setState(() => _selectedTabIndex = val),
                    ),
                  ),
                ),

                // Content Area
                Expanded(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: [
                      // Tab 0: Overview
                      _buildOverviewTab(isDark),

                      // Tab 1: Large Files
                      _buildLargeFilesTab(isDark),

                      // Tab 2: Duplicate Cleaner
                      _buildDuplicatesTab(isDark),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildOverviewTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppleCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              StorageDonutChart(storageInfo: _info!, size: 190, isMultiCategory: true),
              const SizedBox(height: 24),
              _buildLegendItem('Videos', _info!.videoBytes, AppleColors.catVideos, isDark),
              _buildLegendItem('Images', _info!.imageBytes, AppleColors.catImages, isDark),
              _buildLegendItem('Audio', _info!.audioBytes, AppleColors.catAudio, isDark),
              _buildLegendItem('Documents', _info!.docBytes, AppleColors.catDocs, isDark),
              _buildLegendItem('Apps & APKs', _info!.appBytes, AppleColors.catApps, isDark),
              _buildLegendItem('System & Other', _info!.otherBytes, AppleColors.systemIndigo, isDark),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Quick Action Cards
        if (_info!.duplicateGroups.isNotEmpty)
          AppleCard(
            onTap: () => setState(() => _selectedTabIndex = 2),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppleColors.systemIndigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(CupertinoIcons.square_on_square, color: AppleColors.systemIndigo, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Duplicate Cleaner',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_info!.duplicateGroups.length} duplicate groups wasting ${StorageInfo.formatBytes(_totalWastedDuplicateBytes)}',
                        style: const TextStyle(color: AppleColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_right, size: 14, color: AppleColors.textTertiary),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLargeFilesTab(bool isDark) {
    if (_info!.largeFiles.isEmpty) {
      return const Center(
        child: Text('No large files (> 25 MB) detected.', style: TextStyle(color: AppleColors.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _info!.largeFiles.length,
      itemBuilder: (context, index) {
        final file = _info!.largeFiles[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppleCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  file.category == FileCategory.video
                      ? CupertinoIcons.play_rectangle_fill
                      : CupertinoIcons.doc_fill,
                  color: file.category == FileCategory.video ? AppleColors.catVideos : AppleColors.systemBlue,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${file.formattedSize} • ${file.path}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppleColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.trash, color: AppleColors.systemRed, size: 20),
                  tooltip: 'Delete Large File',
                  onPressed: () => _deleteLargeFile(file),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDuplicatesTab(bool isDark) {
    if (_info!.duplicateGroups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.checkmark_shield_fill, color: AppleColors.systemGreen, size: 48),
            SizedBox(height: 12),
            Text(
              'No duplicate files found!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Your storage is clean and optimized.',
              style: TextStyle(color: AppleColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Clean All Duplicates Card
        AppleCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppleColors.systemIndigo.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.sparkles, color: AppleColors.systemIndigo, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wasted Space: ${StorageInfo.formatBytes(_totalWastedDuplicateBytes)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppleColors.systemIndigo),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_info!.duplicateGroups.length} groups of identical duplicate files',
                      style: const TextStyle(color: AppleColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: AppleColors.systemIndigo,
                borderRadius: BorderRadius.circular(16),
                onPressed: _cleanAllDuplicates,
                child: const Text('Clean All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // List of Duplicate Groups
        ..._info!.duplicateGroups.map((group) {
          final original = group.files.first;
          final copies = group.files.skip(1).toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppleCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          original.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        color: AppleColors.systemRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        onPressed: () => _cleanDuplicateGroup(group),
                        child: Text(
                          'Clean ${copies.length} ${copies.length == 1 ? 'Copy' : 'Copies'}',
                          style: const TextStyle(color: AppleColors.systemRed, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${group.files.length} copies • Each ${StorageInfo.formatBytes(group.fileSize)} • Wasting ${StorageInfo.formatBytes(group.totalWastedBytes)}',
                    style: const TextStyle(color: AppleColors.textSecondary, fontSize: 12),
                  ),
                  const Divider(height: 16),

                  // Original File Badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppleColors.systemGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('ORIGINAL', style: TextStyle(color: AppleColors.systemGreen, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          original.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppleColors.textSecondary, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Duplicate Copies
                  ...copies.map((copy) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppleColors.systemRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('DUPLICATE', style: TextStyle(color: AppleColors.systemRed, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            copy.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppleColors.textSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
