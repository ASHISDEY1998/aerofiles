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
  bool _isSuccess = false;
  String? _outputPath;
  bool _hasPopped = false;

  @override
  void initState() {
    super.initState();
    _startTask();
  }

  void _finishSuccess(String? path) {
    if (_hasPopped || !mounted) return;
    _hasPopped = true;
    Navigator.of(context).pop(path);
  }

  Future<void> _startTask() async {
    try {
      final outputPath = await widget.task((progress) {
        if (mounted) {
          setState(() => _progress = progress.clamp(0, 100));
        }
      });
      _outputPath = outputPath;
      if (mounted) {
        setState(() {
          _progress = 100;
          _isSuccess = true;
        });
        // Allow user to clearly see the animated green success checkmark and alert
        await Future.delayed(const Duration(milliseconds: 1300));
        _finishSuccess(outputPath);
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
    if (_isSuccess) {
      _finishSuccess(_outputPath);
      return;
    }
    setState(() => _isCancelling = true);
    await VideoEditorService.instance.cancel();
    if (mounted && !_hasPopped) {
      _hasPopped = true;
      Navigator.of(context).pop(null);
    }
  }

  String get _displayTitle {
    if (_errorMessage != null) return 'Rendering Error';
    if (_isSuccess) {
      if (widget.title.toLowerCase().contains('trim')) return 'Trim Complete!';
      if (widget.title.toLowerCase().contains('merge')) return 'Merge Complete!';
      return 'Complete!';
    }
    return widget.title;
  }

  String get _displaySubtitle {
    if (_errorMessage != null) return _errorMessage!;
    if (_isSuccess) return 'Saved successfully to folder';
    if (_isCancelling) return 'Cancelling operation...';
    return widget.subtitle;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSuccess) {
          _finishSuccess(_outputPath);
        } else if (!_isCancelling) {
          _handleCancel();
        }
      },
      child: Material(
        type: MaterialType.transparency,
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
                    // Icon Header with Animated Transition to Success Checkmark
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _errorMessage != null
                              ? [AppleColors.systemRed, const Color(0xFFFF453A)]
                              : _isSuccess
                                  ? [AppleColors.systemGreen, const Color(0xFF30D158)]
                                  : [AppleColors.systemBlue, AppleColors.systemTeal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: (_errorMessage != null
                                    ? AppleColors.systemRed
                                    : _isSuccess
                                        ? AppleColors.systemGreen
                                        : AppleColors.systemBlue)
                                .withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: Icon(
                          _errorMessage != null
                              ? CupertinoIcons.exclamationmark_triangle_fill
                              : _isSuccess
                                  ? CupertinoIcons.checkmark_alt
                                  : widget.icon,
                          key: ValueKey<String>(
                            _errorMessage != null
                                ? 'icon_err'
                                : (_isSuccess ? 'icon_success' : 'icon_running'),
                          ),
                          color: Colors.white,
                          size: _isSuccess ? 32 : 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    Text(
                      _displayTitle,
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
                      _displaySubtitle,
                      style: TextStyle(
                        color: _errorMessage != null
                            ? AppleColors.systemRed
                            : _isSuccess
                                ? AppleColors.systemGreen
                                : (isDark ? AppleColors.textSecondary : AppleColors.textSecondaryLight),
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: _isSuccess ? FontWeight.w500 : FontWeight.normal,
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
                                  colors: _isSuccess
                                      ? [AppleColors.systemGreen, const Color(0xFF30D158)]
                                      : [AppleColors.systemBlue, AppleColors.systemTeal],
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
                            _isSuccess ? 'Saved' : 'Hardware Accelerated',
                            style: TextStyle(
                              color: _isSuccess
                                  ? AppleColors.systemGreen
                                  : (isDark ? AppleColors.textTertiary : const Color(0xFF8E8E93)),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$_progress%',
                            style: TextStyle(
                              color: _isSuccess ? AppleColors.systemGreen : AppleColors.systemBlue,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Action Button: Cancel during progress, or Done on success
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: _isSuccess
                            ? CupertinoButton(
                                padding: EdgeInsets.zero,
                                color: AppleColors.systemGreen,
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () => _finishSuccess(_outputPath),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(CupertinoIcons.checkmark_alt, color: Colors.white, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Done',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : CupertinoButton(
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
    ),
  );
}
}
