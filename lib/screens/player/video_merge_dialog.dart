import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/vfs_node.dart';
import '../../services/media/video_editor_service.dart';
import '../../theme/apple_theme.dart';
import 'video_render_progress_dialog.dart';

class VideoMergeDialog extends StatefulWidget {
  final List<VfsNode> orderedVideos;

  const VideoMergeDialog({
    super.key,
    required this.orderedVideos,
  });

  static Future<bool> show(
    BuildContext context, {
    required List<VfsNode> orderedVideos,
  }) async {
    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => VideoMergeDialog(orderedVideos: orderedVideos),
    );
    return result ?? false;
  }

  @override
  State<VideoMergeDialog> createState() => _VideoMergeDialogState();
}

class _VideoMergeDialogState extends State<VideoMergeDialog> {
  late List<VfsNode> _videos;
  VideoSaveOption _saveOption = VideoSaveOption.keepOriginal;

  @override
  void initState() {
    super.initState();
    _videos = List.from(widget.orderedVideos);
  }

  Future<void> _handleStartMerge() async {
    final paths = _videos.map((n) => n.path).toList();
    Navigator.of(context).pop(false);

    final result = await VideoRenderProgressDialog.show(
      context,
      title: 'Merging Videos...',
      subtitle: 'Combining ${paths.length} clips into one video',
      icon: CupertinoIcons.layers_alt,
      task: (onProgress) => VideoEditorService.instance.mergeVideos(
        inputPaths: paths,
        saveOption: _saveOption,
        onProgressUpdated: onProgress,
      ),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Merged video saved: ${p.basename(result)}'),
          backgroundColor: AppleColors.darkElevated,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalBytes = _videos.fold<int>(0, (sum, v) => sum + v.size);

    return Material(
      color: Colors.transparent,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle pill
            Center(
              child: Container(
                width: 38,
                height: 5,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppleColors.systemBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(CupertinoIcons.layers_alt, color: AppleColors.systemBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Merge Videos (${_videos.length})',
                          style: TextStyle(
                            color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Will merge in selected order • ${_formatBytes(totalBytes)}',
                          style: TextStyle(
                            color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(color: AppleColors.systemBlue)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF2C2C2E)),

            // Ordered Videos List
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _videos.length,
                // ignore: deprecated_member_use
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _videos.removeAt(oldIndex);
                    _videos.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final video = _videos[index];
                  return Container(
                    key: ValueKey(video.path),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Sequence Order Number Pill
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppleColors.systemBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.name,
                                style: TextStyle(
                                  color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatBytes(video.size),
                                style: TextStyle(
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          CupertinoIcons.bars,
                          color: isDark ? AppleColors.textTertiary : const Color(0xFF8E8E93),
                          size: 20,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Save Option & Merge Button Panel
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161618) : const Color(0xFFF9F9F9),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    width: 0.6,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Save Option Segmented Control
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<VideoSaveOption>(
                      groupValue: _saveOption,
                      children: const {
                        VideoSaveOption.keepOriginal: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('Keep Originals', style: TextStyle(fontSize: 13)),
                        ),
                        VideoSaveOption.replaceOriginal: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('Replace Originals', style: TextStyle(fontSize: 13)),
                        ),
                      },
                      onValueChanged: (val) {
                        if (val != null) setState(() => _saveOption = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Start Merge Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      color: AppleColors.systemBlue,
                      borderRadius: BorderRadius.circular(16),
                      onPressed: _handleStartMerge,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.play_arrow_solid, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Merge ${_videos.length} Videos',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
