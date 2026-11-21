import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/vfs_node.dart';
import '../theme/apple_theme.dart';

class FileTile extends StatelessWidget {
  final VfsNode node;
  final bool isGrid;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenuPressed;
  final bool isSelectable;
  final bool isSelected;
  final ValueChanged<bool>? onSelectionChanged;

  const FileTile({
    super.key,
    required this.node,
    this.isGrid = false,
    required this.onTap,
    this.onLongPress,
    this.onMenuPressed,
    this.isSelectable = false,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  Widget _buildThumbnail({required double size, bool isGridMode = false, required bool isDark}) {
    if (node.isDirectory) {
      final isDisk = node.path.isEmpty || node.name.toLowerCase().contains('disk') || node.name.toLowerCase().contains('hdd');
      return Icon(
        isDisk ? CupertinoIcons.archivebox_fill : CupertinoIcons.folder_fill,
        color: isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight,
        size: size,
      );
    }

    // Local image thumbnail preview
    if (node.isImage && !node.path.startsWith('http')) {
      final file = File(node.path);
      return ClipRRect(
        borderRadius: BorderRadius.circular(isGridMode ? 12 : 8),
        child: Image.file(
          file,
          width: isGridMode ? double.infinity : size,
          height: isGridMode ? 80 : size,
          fit: BoxFit.cover,
          cacheWidth: 160,
          cacheHeight: 160,
          errorBuilder: (_, _, _) => Image.asset(
            'assets/icons/file_img.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    // Dedicated file type icons from asset pack
    final ext = node.extension.toLowerCase();
    String? assetIcon;

    if (ext == '.pdf') {
      assetIcon = 'assets/icons/file_pdf.png';
    } else if (ext == '.doc' || ext == '.docx') {
      assetIcon = 'assets/icons/file_doc.png';
    } else if (ext == '.xls' || ext == '.xlsx' || ext == '.csv') {
      assetIcon = 'assets/icons/file_xls.png';
    } else if (ext == '.txt' || ext == '.md' || ext == '.json' || ext == '.log') {
      assetIcon = 'assets/icons/file_txt.png';
    } else if (ext == '.zip' || ext == '.rar' || ext == '.7z' || ext == '.tar' || ext == '.gz') {
      assetIcon = 'assets/icons/file_zip.png';
    } else if (node.isVideo) {
      assetIcon = 'assets/icons/file_vid.png';
    } else if (ext == '.png') {
      assetIcon = 'assets/icons/file_png.png';
    } else if (node.isImage) {
      assetIcon = 'assets/icons/file_img.png';
    }

    if (assetIcon != null) {
      return Image.asset(
        assetIcon,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _fallbackIcon(size, isDark),
      );
    }

    return _fallbackIcon(size, isDark);
  }

  Widget _fallbackIcon(double size, bool isDark) {
    switch (node.category) {
      case FileCategory.video:
        return Icon(CupertinoIcons.play_rectangle_fill, color: AppleColors.catVideos, size: size);
      case FileCategory.audio:
        return Icon(CupertinoIcons.music_note_2, color: AppleColors.catAudio, size: size);
      case FileCategory.image:
        return Icon(CupertinoIcons.photo_fill, color: AppleColors.catImages, size: size);
      case FileCategory.document:
        return Icon(CupertinoIcons.doc_text_fill, color: AppleColors.catDocs, size: size);
      case FileCategory.archive:
        return Icon(CupertinoIcons.archivebox_fill, color: AppleColors.systemIndigo, size: size);
      case FileCategory.app:
        return Icon(CupertinoIcons.app_badge_fill, color: AppleColors.catApps, size: size);
      default:
        return Icon(
          CupertinoIcons.doc_fill,
          color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
          size: size,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isGrid) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppleColors.systemBlue.withValues(alpha: 0.25) : AppleColors.systemBlueLight.withValues(alpha: 0.15))
                : (isDark ? AppleColors.darkCard : AppleColors.lightCard),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppleColors.systemBlue
                  : (isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke),
              width: isSelected ? 1.5 : 0.5,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: _buildThumbnail(size: 44, isGridMode: true, isDark: isDark),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    node.isDirectory ? 'Folder' : node.formattedSize,
                    style: TextStyle(
                      color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              if (isSelectable)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Icon(
                    isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                    color: isSelected ? AppleColors.systemBlue : AppleColors.textTertiary,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // List Tile
    return Material(
      color: isSelected
          ? (isDark ? AppleColors.systemBlue.withValues(alpha: 0.18) : AppleColors.systemBlueLight.withValues(alpha: 0.12))
          : Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0x1AFFFFFF) : const Color(0x1A000000),
              width: 0.5,
            ),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelectable) ...[
                Icon(
                  isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                  color: isSelected ? AppleColors.systemBlue : AppleColors.textTertiary,
                  size: 22,
                ),
                const SizedBox(width: 10),
              ],
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? AppleColors.darkElevated : AppleColors.lightElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: _buildThumbnail(size: 28, isDark: isDark),
              ),
            ],
          ),
          title: Text(
            node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            node.isDirectory ? node.formattedDate : '${node.formattedSize} • ${node.formattedDate}',
            style: TextStyle(
              color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
              fontSize: 12,
            ),
          ),
          trailing: isSelectable
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                      onPressed: onMenuPressed,
                      child: Icon(
                        CupertinoIcons.ellipsis,
                        size: 18,
                        color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                      ),
                    ),
                    if (node.isDirectory)
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
                      ),
                  ],
                ),
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}
