import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
      duration: const Duration(milliseconds: 300),
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

    _mgr.isTransferring.addListener(_onTransferStateChanged);
    if (_mgr.isTransferring.value) {
      _animController.forward();
    }
  }

  void _onTransferStateChanged() {
    if (_mgr.isTransferring.value) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _mgr.isTransferring.removeListener(_onTransferStateChanged);
    _animController.dispose();
    super.dispose();
  }

  void _openTransferScreen(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (_) => const TransferProgressScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([_animController, _mgr.isTransferring]),
      builder: (context, child) {
        if (_animController.isDismissed && !_mgr.isTransferring.value) {
          return const SizedBox.shrink();
        }

        return Positioned(
          bottom: 84, // Cleanly above HomeShell bottom nav bar
          right: 18,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: GestureDetector(
                onTap: () => _openTransferScreen(context),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.2),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight)
                            .withValues(alpha: 0.25),
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
                              .withValues(alpha: 0.88),
                          border: Border.all(
                            color: (isDark ? AppleColors.systemBlue : AppleColors.systemBlueLight)
                                .withValues(alpha: 0.35),
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
                                    value: progress > 0 ? progress : null,
                                    strokeWidth: 3.0,
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.black.withValues(alpha: 0.08),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDark
                                          ? AppleColors.systemBlue
                                          : AppleColors.systemBlueLight,
                                    ),
                                  ),
                                );
                              },
                            ),

                            // Center Sync / Upload Icon
                            Icon(
                              CupertinoIcons.arrow_up_arrow_down,
                              size: 20,
                              color: isDark
                                  ? AppleColors.systemBlue
                                  : AppleColors.systemBlueLight,
                            ),

                            // Small Active Item Count Badge (Top Right)
                            ValueListenableBuilder<List<TransferTask>>(
                              valueListenable: _mgr.tasks,
                              builder: (context, taskList, _) {
                                final activeCount = taskList
                                    .where(
                                      (t) =>
                                          t.status == TransferStatus.pending ||
                                          t.status == TransferStatus.transferring,
                                    )
                                    .length;
                                if (activeCount <= 0) return const SizedBox.shrink();

                                return Positioned(
                                  top: 3,
                                  right: 3,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppleColors.systemBlue,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                    child: Center(
                                      child: Text(
                                        activeCount > 99 ? '99+' : '$activeCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
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

