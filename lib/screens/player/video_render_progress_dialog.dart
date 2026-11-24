import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../services/media/video_editor_service.dart';
import '../../theme/apple_theme.dart';

class VideoRenderProgressDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Future<String> Function(void Function(int progress) onProgress) task;

  const VideoRenderProgressDialog({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = CupertinoIcons.film,
    required this.task,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    IconData icon = CupertinoIcons.film,
    required Future<String> Function(void Function(int progress) onProgress) task,
  }) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => VideoRenderProgressDialog(
        title: title,
        subtitle: subtitle,
        icon: icon,
        task: task,
      ),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  State<VideoRenderProgressDialog> createState() => _VideoRenderProgressDialogState();
}

class _VideoRenderProgressDialogState extends State<VideoRenderProgressDialog> {
  int _progress = 0;
  bool _isCancelling = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startTask();
  }

  Future<void> _startTask() async {
    try {
      final outputPath = await widget.task((progress) {
        if (mounted) {
          setState(() => _progress = progress.clamp(0, 100));
        }
      });
      if (mounted) {
        Navigator.of(context).pop(outputPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _handleCancel() async {
    setState(() => _isCancelling = true);
    await VideoEditorService.instance.cancel();
    if (mounted) {
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isCancelling) {
          _handleCancel();
        }
      },
      child: Center(
        child: Container(
          width: 320,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon Header
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppleColors.systemBlue,
                            AppleColors.systemTeal,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppleColors.systemBlue.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    Text(
                      _errorMessage != null ? 'Rendering Error' : widget.title,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppleColors.textPrimaryLight,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),

                    // Subtitle / Status
                    Text(
                      _errorMessage ?? (_isCancelling ? 'Cancelling operation...' : widget.subtitle),
                      style: TextStyle(
                        color: _errorMessage != null
                            ? AppleColors.systemRed
                            : (isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight),
                        fontSize: 13,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 22),

                    if (_errorMessage == null) ...[
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          children: [
                            Container(
                              height: 8,
                              width: double.infinity,
                              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutCubic,
                              height: 8,
                              width: (320 - 48) * (_progress / 100.0),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppleColors.systemBlue,
                                    AppleColors.systemTeal,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Progress Percentage & Hardware Accel Label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Hardware Accelerated',
                            style: TextStyle(
                              color: isDark ? AppleColors.textTertiary : const Color(0xFF8E8E93),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$_progress%',
                            style: TextStyle(
                              color: AppleColors.systemBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Cancel Button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(12),
                          onPressed: _isCancelling ? null : _handleCancel,
                          child: Text(
                            _isCancelling ? 'Cancelling...' : 'Cancel',
                            style: TextStyle(
                              color: _isCancelling
                                  ? (isDark ? Colors.grey : Colors.black45)
                                  : (isDark ? Colors.white : Colors.black87),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Dismiss Button on Error
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          color: AppleColors.systemRed,
                          borderRadius: BorderRadius.circular(12),
                          onPressed: () => Navigator.of(context).pop(null),
                          child: const Text(
                            'Dismiss',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
