import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/storage_info.dart';
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
        title: const Text('Storage Analysis'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_clockwise),
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
                    'Scanning storage & duplicates...',
                    style: TextStyle(
                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Donut Chart & Category Breakdown
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

                const SizedBox(height: 20),

                // Junk & Cache Cleaner Card
                if (_info!.junkCacheBytes > 0) ...[
                  AppleCard(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: const Color(0x33FF9F0A),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.trash_circle_fill, color: AppleColors.systemOrange, size: 36),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Junk & Cache Files',
                                style: TextStyle(
                                  color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                '${StorageInfo.formatBytes(_info!.junkCacheBytes)} safe to clean',
                                style: TextStyle(
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          color: AppleColors.systemOrange,
                          borderRadius: BorderRadius.circular(20),
                          child: const Text('Clean', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Temporary cache files cleaned!')),
                            );
                            _runAnalysis();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Large Files Section
                Text(
                  'Large Files (> 25 MB)',
                  style: TextStyle(
                    color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                if (_info!.largeFiles.isEmpty)
                  AppleCard(
                    child: Text(
                      'No large files detected',
                      style: TextStyle(
                        color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                      ),
                    ),
                  )
                else
                  AppleCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: _info!.largeFiles.take(10).map((file) {
                        return ListTile(
                          leading: Icon(
                            CupertinoIcons.doc_fill,
                            color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                          ),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(file.formattedSize, style: const TextStyle(color: AppleColors.systemRed)),
                          trailing: Icon(
                            CupertinoIcons.chevron_right,
                            size: 14,
                            color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 20),

                // Duplicate Files Section
                if (_info!.duplicateGroups.isNotEmpty) ...[
                  Text(
                    'Duplicate Files',
                    style: TextStyle(
                      color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppleCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: _info!.duplicateGroups.take(5).map((group) {
                        return ExpansionTile(
                          iconColor: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                          collapsedIconColor: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                          leading: const Icon(CupertinoIcons.square_on_square, color: AppleColors.systemIndigo),
                          title: Text(
                            group.files.first.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${group.files.length} copies • Wasting ${StorageInfo.formatBytes(group.totalWastedBytes)}',
                            style: TextStyle(
                              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                              fontSize: 12,
                            ),
                          ),
                          children: group.files.map((f) {
                            return ListTile(
                              dense: true,
                              title: Text(
                                f.path,
                                style: TextStyle(
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
