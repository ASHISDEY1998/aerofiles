import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/storage_info.dart';
import '../theme/apple_theme.dart';

class StorageDonutChart extends StatelessWidget {
  final StorageInfo storageInfo;
  final double size;
  final bool isMultiCategory;
  final VoidCallback? onTap;

  const StorageDonutChart({
    super.key,
    required this.storageInfo,
    this.size = 180,
    this.isMultiCategory = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final usedPercent = (storageInfo.usedPercentage * 100).round();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _AppleDonutPainter(
                storageInfo: storageInfo,
                isMultiCategory: isMultiCategory,
                isDark: isDark,
                strokeWidth: size * 0.13,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$usedPercent%',
                  style: TextStyle(
                    color: isDark ? AppleColors.textPrimary : AppleColors.textPrimaryLight,
                    fontSize: size * 0.22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${storageInfo.formattedUsed} used',
                  style: TextStyle(
                    color: isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight,
                    fontSize: size * 0.09,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppleDonutPainter extends CustomPainter {
  final StorageInfo storageInfo;
  final bool isMultiCategory;
  final bool isDark;
  final double strokeWidth;

  _AppleDonutPainter({
    required this.storageInfo,
    required this.isMultiCategory,
    required this.isDark,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // 1. Background Track Ring
    final trackPaint = Paint()
      ..color = isDark ? AppleColors.darkElevated : AppleColors.lightElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius, trackPaint);

    if (storageInfo.totalBytes <= 0 || storageInfo.usedBytes <= 0) return;

    if (!isMultiCategory) {
      // Single vibrant Apple Blue/Indigo progress arc for Home Screen
      final sweepAngle = (storageInfo.usedPercentage * 2 * math.pi).clamp(0.0, 2 * math.pi);
      if (sweepAngle > 0) {
        final progressPaint = Paint()
          ..shader = const LinearGradient(
            colors: [AppleColors.systemBlue, AppleColors.systemIndigo],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2, // Start at 12 o'clock
          sweepAngle,
          false,
          progressPaint,
        );
      }
    } else {
      // Multi-category colorful segregated segments for Storage Analysis Screen
      final categories = [
        MapEntry(AppleColors.catVideos, storageInfo.videoBytes),
        MapEntry(AppleColors.catImages, storageInfo.imageBytes),
        MapEntry(AppleColors.catAudio, storageInfo.audioBytes),
        MapEntry(AppleColors.catDocs, storageInfo.docBytes),
        MapEntry(AppleColors.catApps, storageInfo.appBytes),
        MapEntry(AppleColors.systemIndigo, storageInfo.otherBytes),
      ];

      // Total sweep angle available based on used storage percentage of full circle
      final totalSweep = (storageInfo.usedPercentage * 2 * math.pi).clamp(0.0, 2 * math.pi);
      final activeCategories = categories.where((e) => e.value > 0).toList();

      if (activeCategories.isEmpty) return;

      const double gapAngle = 0.025; // 1.5 degree gap between segments
      const double minSweep = 0.08;  // Guaranteed minimum visible segment (~4.6 degrees)

      // Calculate raw sweeps proportional to usedBytes
      final totalUsed = storageInfo.usedBytes.toDouble();
      List<double> sweeps = [];

      for (final entry in activeCategories) {
        final rawSweep = (entry.value / totalUsed) * totalSweep;
        sweeps.add(math.max(rawSweep, minSweep));
      }

      // Normalize sweeps if the sum of minimums exceeds totalSweep
      final sumSweeps = sweeps.reduce((a, b) => a + b);
      if (sumSweeps > totalSweep) {
        final factor = totalSweep / sumSweeps;
        sweeps = sweeps.map((s) => s * factor).toList();
      }

      double startAngle = -math.pi / 2;

      for (int i = 0; i < activeCategories.length; i++) {
        final entry = activeCategories[i];
        final sweep = sweeps[i];
        final effectiveSweep = math.max(0.01, sweep - (activeCategories.length > 1 ? gapAngle : 0));

        final segmentPaint = Paint()
          ..color = entry.key
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          effectiveSweep,
          false,
          segmentPaint,
        );

        startAngle += sweep;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AppleDonutPainter oldDelegate) {
    return oldDelegate.storageInfo != storageInfo ||
        oldDelegate.isMultiCategory != isMultiCategory ||
        oldDelegate.isDark != isDark;
  }
}
