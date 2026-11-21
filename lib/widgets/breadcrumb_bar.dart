import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../theme/apple_theme.dart';

class BreadcrumbBar extends StatelessWidget {
  final String currentPath;
  final String rootPath;
  final ValueChanged<String> onPathSelected;

  const BreadcrumbBar({
    super.key,
    required this.currentPath,
    required this.rootPath,
    required this.onPathSelected,
  });

  List<_BreadcrumbItem> _generateBreadcrumbs() {
    final List<_BreadcrumbItem> items = [];
    items.add(_BreadcrumbItem(name: 'Main', path: rootPath));

    if (currentPath == rootPath || currentPath.isEmpty) {
      return items;
    }

    String rel = currentPath;
    if (currentPath.startsWith(rootPath)) {
      rel = currentPath.substring(rootPath.length);
      if (rel.startsWith('/')) rel = rel.substring(1);
    }

    final segments = rel.split('/').where((s) => s.isNotEmpty).toList();
    String accumulated = rootPath;

    for (final seg in segments) {
      accumulated = p.join(accumulated, seg);
      items.add(_BreadcrumbItem(name: seg, path: accumulated));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final crumbs = _generateBreadcrumbs();

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: isDark ? AppleColors.pureBlack : AppleColors.lightBackground,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: crumbs.length,
        separatorBuilder: (_, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            CupertinoIcons.chevron_right,
            size: 14,
            color: isDark ? AppleColors.textTertiary : AppleColors.textTertiaryLight,
          ),
        ),
        itemBuilder: (context, index) {
          final isLast = index == crumbs.length - 1;
          final item = crumbs[index];

          return Center(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              minimumSize: Size.zero,
              onPressed: isLast ? null : () => onPathSelected(item.path),
              child: Text(
                item.name,
                style: TextStyle(
                  color: isLast
                      ? (isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight)
                      : (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight),
                  fontSize: 14,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BreadcrumbItem {
  final String name;
  final String path;
  const _BreadcrumbItem({required this.name, required this.path});
}
