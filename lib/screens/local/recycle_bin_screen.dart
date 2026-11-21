import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../services/recycle_bin_service.dart';
import '../../theme/apple_theme.dart';
import '../../widgets/apple_card.dart';

class RecycleBinScreen extends StatefulWidget {
  final RecycleBinService recycleBinService;

  const RecycleBinScreen({super.key, required this.recycleBinService});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = widget.recycleBinService.items;

    return Scaffold(
      backgroundColor: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        actions: [
          if (items.isNotEmpty)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onPressed: () {
                showCupertinoDialog(
                  context: context,
                  builder: (ctx) => CupertinoAlertDialog(
                    title: const Text('Empty Recycle Bin?'),
                    content: const Text('All items will be permanently deleted.'),
                    actions: [
                      CupertinoDialogAction(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        child: const Text('Empty'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await widget.recycleBinService.emptyTrash();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Empty', style: TextStyle(color: AppleColors.systemRed)),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.trash,
                    size: 64,
                    color: isDark ? AppleColors.darkTertiary : AppleColors.lightBorderStroke,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Recycle Bin is Empty',
                    style: TextStyle(
                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppleCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          item.isDirectory ? CupertinoIcons.folder_fill : CupertinoIcons.doc_fill,
                          color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                          size: 32,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Original: ${item.originalPath}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            CupertinoIcons.arrow_counterclockwise,
                            color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
                          ),
                          tooltip: 'Restore',
                          onPressed: () async {
                            final success = await widget.recycleBinService.restore(item);
                            if (!context.mounted) return;
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(success ? 'Restored to original location' : 'Failed to restore')),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.delete, color: AppleColors.systemRed),
                          tooltip: 'Delete Permanently',
                          onPressed: () async {
                            await widget.recycleBinService.permanentDelete(item);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
