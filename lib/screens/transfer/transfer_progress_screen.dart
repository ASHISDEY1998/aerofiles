import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../services/transfer_manager_service.dart';
import '../../theme/apple_theme.dart';

class TransferProgressScreen extends StatelessWidget {
  const TransferProgressScreen({super.key});

  IconData _getFileIcon(String filename, bool isDirectory) {
    if (isDirectory) return CupertinoIcons.folder_fill;
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.mkv':
      case '.mov':
      case '.avi':
      case '.webm':
      case '.3gp':
        return CupertinoIcons.film_fill;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
      case '.bmp':
        return CupertinoIcons.photo_fill;
      case '.mp3':
      case '.m4a':
      case '.flac':
      case '.wav':
      case '.aac':
        return CupertinoIcons.music_note;
      case '.pdf':
      case '.doc':
      case '.docx':
      case '.txt':
        return CupertinoIcons.doc_text_fill;
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return CupertinoIcons.archivebox_fill;
      case '.apk':
        return CupertinoIcons.cube_box_fill;
      default:
        return CupertinoIcons.doc_fill;
    }
  }

  Color _getIconColor(String filename, bool isDirectory, bool isDark) {
    if (isDirectory) return isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight;
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.mp4':
      case '.mkv':
      case '.mov':
      case '.avi':
      case '.webm':
        return AppleColors.systemPurple;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
        return AppleColors.systemTeal;
      case '.mp3':
      case '.m4a':
      case '.flac':
        return AppleColors.systemPink;
      case '.pdf':
      case '.doc':
      case '.txt':
        return AppleColors.systemOrange;
      default:
        return isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mgr = TransferManagerService.instance;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      appBar: AppBar(
        title: const Text('File Transfers', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          ValueListenableBuilder<List<TransferTask>>(
            valueListenable: mgr.tasks,
            builder: (context, taskList, _) {
              final hasActive = taskList.any(
                (t) => t.status == TransferStatus.pending || t.status == TransferStatus.transferring,
              );
              final hasFailedOrPaused = taskList.any(
                (t) => t.isFailedOrPaused,
              );

              if (!hasActive) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasFailedOrPaused)
                      TextButton(
                        onPressed: () => mgr.resumeTransfers(),
                        child: const Text(
                          'Retry All',
                          style: TextStyle(color: AppleColors.systemBlue, fontWeight: FontWeight.w600),
                        ),
                      ),
                    TextButton(
                      onPressed: () {
                        mgr.clearFinished();
                      },
                      child: const Text('Clear', style: TextStyle(color: AppleColors.systemBlue)),
                    ),
                  ],
                );
              }
              return TextButton(
                onPressed: () {
                  showCupertinoDialog(
                    context: context,
                    builder: (ctx) => CupertinoAlertDialog(
                      title: const Text('Cancel Transfers?'),
                      content: const Text('Are you sure you want to cancel all remaining transfers?'),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('No'),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        CupertinoDialogAction(
                          isDestructiveAction: true,
                          child: const Text('Cancel All'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            mgr.cancelAll();
                          },
                        ),
                      ],
                    ),
                  );
                },
                child: const Text(
                  'Cancel All',
                  style: TextStyle(color: AppleColors.systemRed, fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Overall Progress Summary Card
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppleColors.darkCard : AppleColors.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                    width: 0.5,
                  ),
                ),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    mgr.overallProgress,
                    mgr.overallSpeed,
                    mgr.overallSummary,
                    mgr.isTransferring,
                    mgr.hasNetworkError,
                    mgr.tasks,
                  ]),
                  builder: (context, _) {
                    final progress = mgr.overallProgress.value;
                    final pct = (progress * 100).toInt();
                    final speed = mgr.overallSpeed.value;
                    final summary = mgr.overallSummary.value;
                    final active = mgr.isTransferring.value;
                    final hasNetErr = mgr.hasNetworkError.value;
                    final pausedCount = mgr.tasks.value.where((t) => t.status == TransferStatus.paused).length;
                    final failedCount = mgr.tasks.value.where((t) => t.status == TransferStatus.failed).length;

                    String headerTitle;
                    if (hasNetErr || pausedCount > 0) {
                      headerTitle = 'Transfers Paused';
                    } else if (failedCount > 0 && !active) {
                      headerTitle = 'Transfers Interrupted';
                    } else if (active) {
                      headerTitle = 'Transferring Files';
                    } else {
                      headerTitle = 'All Transfers Finished';
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              headerTitle,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: (hasNetErr || pausedCount > 0)
                                    ? AppleColors.systemOrange
                                    : (failedCount > 0 && !active)
                                        ? AppleColors.systemRed
                                        : (isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight),
                              ),
                            ),
                            Text(
                              '$pct%',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: isDark ? Colors.white12 : Colors.black12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              (hasNetErr || pausedCount > 0)
                                  ? AppleColors.systemOrange
                                  : (failedCount > 0 && !active)
                                      ? AppleColors.systemRed
                                      : (active
                                          ? (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight)
                                          : AppleColors.systemGreen),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              summary.isNotEmpty ? summary : '0 items',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                              ),
                            ),
                            if (speed.isNotEmpty)
                              Row(
                                children: [
                                  Icon(
                                    CupertinoIcons.speedometer,
                                    size: 14,
                                    color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    speed,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (hasNetErr || pausedCount > 0) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppleColors.systemOrange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppleColors.systemOrange.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.wifi_exclamationmark, color: AppleColors.systemOrange, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Network interrupted. Auto-reconnecting...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppleColors.systemOrange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  onPressed: () => mgr.resumeTransfers(),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(CupertinoIcons.arrow_clockwise, size: 14, color: AppleColors.systemOrange),
                                      SizedBox(width: 4),
                                      Text(
                                        'Resume',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppleColors.systemOrange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (failedCount > 0) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppleColors.systemRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppleColors.systemRed.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: AppleColors.systemRed, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$failedCount item${failedCount == 1 ? '' : 's'} failed.',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppleColors.systemRed,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  onPressed: () => mgr.resumeTransfers(),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(CupertinoIcons.arrow_clockwise, size: 14, color: AppleColors.systemRed),
                                      SizedBox(width: 4),
                                      Text(
                                        'Retry All',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppleColors.systemRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),

            // Item-by-item progress list
            Expanded(
              child: ValueListenableBuilder<List<TransferTask>>(
                valueListenable: mgr.tasks,
                builder: (context, taskList, _) {
                  if (taskList.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.arrow_up_arrow_down_circle,
                            size: 54,
                            color: isDark ? AppleColors.textTertiary : AppleColors.textSecondaryLight,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No active transfers',
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: taskList.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke,
                    ),
                    itemBuilder: (context, index) {
                      final task = taskList[index];
                      return _buildTaskTile(context, task, isDark);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(BuildContext context, TransferTask task, bool isDark) {
    final icon = _getFileIcon(task.name, task.isDirectory);
    final iconColor = _getIconColor(task.name, task.isDirectory, isDark);

    final mgr = TransferManagerService.instance;
    Widget trailingWidget;
    switch (task.status) {
      case TransferStatus.completed:
        trailingWidget = const Icon(
          CupertinoIcons.checkmark_circle_fill,
          color: AppleColors.systemGreen,
          size: 24,
        );
        break;
      case TransferStatus.transferring:
        trailingWidget = const SizedBox(
          width: 20,
          height: 20,
          child: CupertinoActivityIndicator(radius: 9),
        );
        break;
      case TransferStatus.paused:
        trailingWidget = IconButton(
          icon: const Icon(
            CupertinoIcons.arrow_clockwise_circle_fill,
            color: AppleColors.systemOrange,
            size: 24,
          ),
          onPressed: () => mgr.retryTask(task.id),
          tooltip: 'Resume',
        );
        break;
      case TransferStatus.failed:
        trailingWidget = IconButton(
          icon: const Icon(
            CupertinoIcons.arrow_clockwise_circle_fill,
            color: AppleColors.systemRed,
            size: 24,
          ),
          onPressed: () => mgr.retryTask(task.id),
          tooltip: 'Retry',
        );
        break;
      case TransferStatus.canceled:
        trailingWidget = const Icon(
          CupertinoIcons.minus_circle_fill,
          color: Colors.grey,
          size: 24,
        );
        break;
      case TransferStatus.pending:
        trailingWidget = const Icon(
          CupertinoIcons.clock,
          color: Colors.grey,
          size: 20,
        );
        break;
    }

    String subtitleText;
    switch (task.status) {
      case TransferStatus.transferring:
        final pct = (task.progress * 100).toInt();
        final spd = task.formattedSpeed;
        subtitleText = spd.isNotEmpty
            ? '${task.formattedTransferred} / ${task.formattedTotalSize} • $pct% • $spd'
            : '${task.formattedTransferred} / ${task.formattedTotalSize} • $pct%';
        break;
      case TransferStatus.completed:
        subtitleText = '${task.formattedTotalSize} • ${task.isMove ? "Moved" : "Copied"}';
        break;
      case TransferStatus.paused:
        subtitleText = task.errorMessage ?? 'Paused (network offline)';
        break;
      case TransferStatus.failed:
        subtitleText = task.errorMessage ?? 'Transfer failed';
        break;
      case TransferStatus.canceled:
        subtitleText = 'Transfer canceled';
        break;
      case TransferStatus.pending:
        subtitleText = 'Waiting in queue • ${task.formattedTotalSize}';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: task.status == TransferStatus.failed
                        ? AppleColors.systemRed
                        : (task.status == TransferStatus.paused
                            ? AppleColors.systemOrange
                            : (isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight)),
                  ),
                ),
                if (task.status == TransferStatus.transferring || task.status == TransferStatus.paused) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 4,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        task.status == TransferStatus.paused
                            ? AppleColors.systemOrange
                            : (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailingWidget,
        ],
      ),
    );
  }
}
