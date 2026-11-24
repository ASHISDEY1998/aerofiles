import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/transfer/transfer_progress_screen.dart';
import '../services/transfer_manager_service.dart';
import '../theme/apple_theme.dart';

class TransferProgressBubble extends StatefulWidget {
  const TransferProgressBubble({super.key});

  @override
  State<TransferProgressBubble> createState() => _TransferProgressBubbleState();
}

class _TransferProgressBubbleState extends State<TransferProgressBubble>
    with SingleTickerProviderStateMixin {
  final _mgr = TransferManagerService.instance;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _mgr.isTransferring.addListener(_onStateChanged);
    _mgr.tasks.addListener(_onStateChanged);
    _mgr.hasNetworkError.addListener(_onStateChanged);

    if (_shouldShow) {
      _animController.forward();
    }
  }

  bool get _shouldShow {
    if (_mgr.isTransferring.value) return true;
    final taskList = _mgr.tasks.value;
    return taskList.any((t) => t.isActive || t.isFailedOrPaused);
  }

  void _onStateChanged() {
    if (_shouldShow) {
      if (!_animController.isCompleted && !_animController.isAnimating) {
        _animController.forward();
      }
    } else {
      if (!_animController.isDismissed && !_animController.isAnimating) {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _mgr.isTransferring.removeListener(_onStateChanged);
    _mgr.tasks.removeListener(_onStateChanged);
    _mgr.hasNetworkError.removeListener(_onStateChanged);
    _animController.dispose();
    super.dispose();
  }

  void _openTransferScreen([BuildContext? context]) {
    final nav = AeroFilesApp.navigatorKey.currentState;
    if (nav != null) {
      nav.push(
        CupertinoPageRoute(
          builder: (_) => const TransferProgressScreen(),
          fullscreenDialog: true,
        ),
      );
      return;
    }
    if (context != null) {
      Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => const TransferProgressScreen(),
          fullscreenDialog: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _animController,
        _mgr.isTransferring,
        _mgr.tasks,
        _mgr.hasNetworkError,
      ]),
      builder: (context, child) {
        if (_animController.isDismissed && !_shouldShow) {
          return const SizedBox.shrink();
        }

        final taskList = _mgr.tasks.value;
        final hasError = _mgr.hasNetworkError.value || taskList.any((t) => t.isFailedOrPaused);
        final activeCount = taskList.where((t) => t.isActive).length;
        final failedCount = taskList.where((t) => t.isFailedOrPaused).length;

        final Color primaryAccent = hasError
            ? AppleColors.systemOrange
            : (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight);

        return Positioned(
          bottom: 84, // Cleanly above HomeShell bottom navigation bar
          right: 18,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => _openTransferScreen(context),
                  borderRadius: BorderRadius.circular(32),
                  splashColor: primaryAccent.withValues(alpha: 0.2),
                  highlightColor: primaryAccent.withValues(alpha: 0.1),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Circular Blurred Glass Button
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.25),
                                blurRadius: 16,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: primaryAccent.withValues(alpha: 0.35),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (isDark ? const Color(0xFF1C1C1E) : Colors.white)
                                      .withValues(alpha: 0.90),
                                  border: Border.all(
                                    color: primaryAccent.withValues(alpha: 0.45),
                                    width: 1.5,
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Circular Progress Ring
                                    ValueListenableBuilder<double>(
                                      valueListenable: _mgr.overallProgress,
                                      builder: (context, progress, _) {
                                        return SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: CircularProgressIndicator(
                                            value: hasError ? 1.0 : (progress > 0 ? progress : null),
                                            strokeWidth: 3.2,
                                            backgroundColor: isDark
                                                ? Colors.white.withValues(alpha: 0.1)
                                                : Colors.black.withValues(alpha: 0.08),
                                            valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
                                          ),
                                        );
                                      },
                                    ),

                                    // Center Icon: Exclamation/Retry when error, or Upload/Sync when active
                                    Icon(
                                      hasError
                                          ? CupertinoIcons.exclamationmark_triangle_fill
                                          : CupertinoIcons.arrow_up_arrow_down,
                                      size: hasError ? 22 : 20,
                                      color: primaryAccent,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Unclipped Floating Badge (Positioned outside ClipOval so it is never cut off!)
                        if (failedCount > 0 || activeCount > 0)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: hasError ? AppleColors.systemRed : AppleColors.systemBlue,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                              child: Center(
                                child: Text(
                                  hasError
                                      ? '$failedCount!'
                                      : (activeCount > 99 ? '99+' : '$activeCount'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class TransferProgressOverlay extends StatelessWidget {
  final Widget child;

  const TransferProgressOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const TransferProgressBubble(),
      ],
    );
  }
}
