import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/apple_theme.dart';

class AppleCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final bool enableGlass;
  final Color? backgroundColor;

  const AppleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.borderRadius = 18.0,
    this.enableGlass = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark
        ? (enableGlass ? const Color(0x991C1C1E) : AppleColors.darkCard)
        : (enableGlass ? const Color(0xCCFFFFFF) : AppleColors.lightCard);
    final effectiveBg = backgroundColor ?? defaultBg;
    final effectiveBorder = isDark ? AppleColors.borderStroke : AppleColors.lightBorderStroke;

    Widget content = Container(
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: effectiveBorder, width: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );

    if (enableGlass) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: content,
        ),
      );
    }

    if (onTap != null || onLongPress != null) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        pressedOpacity: 0.75,
        onPressed: onTap,
        child: content,
      );
    }

    return content;
  }
}
