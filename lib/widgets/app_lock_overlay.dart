import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/security/biometric_service.dart';
import '../theme/apple_theme.dart';

class AppLockOverlay extends StatefulWidget {
  final Widget child;

  const AppLockOverlay({super.key, required this.child});

  @override
  State<AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends State<AppLockOverlay> with WidgetsBindingObserver {
  final _biometricService = BiometricService.instance;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_biometricService.isAppLocked.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attemptUnlock();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _biometricService.lock();
    } else if (state == AppLifecycleState.resumed) {
      if (_biometricService.isAppLocked.value && !_isAuthenticating) {
        _attemptUnlock();
      }
    }
  }

  Future<void> _attemptUnlock() async {
    if (_isAuthenticating) return;
    setState(() => _isAuthenticating = true);

    try {
      final success = await _biometricService.authenticate(
        reason: 'Unlock AeroFiles to access your files',
      ).timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (!success && mounted) {
        // Remain on lock screen
      }
    } catch (_) {
      // Ignored - will reset _isAuthenticating in finally
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _biometricService.isAppLocked,
      builder: (context, isLocked, _) {
        return Stack(
          children: [
            widget.child,
            if (isLocked)
              Positioned.fill(
                child: Material(
                  color: Colors.black,
                  child: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: AppleColors.systemBlue.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppleColors.systemBlue.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                CupertinoIcons.lock_shield_fill,
                                size: 52,
                                color: AppleColors.systemBlue,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'AeroFiles Locked',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Touch fingerprint sensor or enter PIN to continue',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppleColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 36),
                            SizedBox(
                              width: 230,
                              height: 50,
                              child: CupertinoButton(
                                padding: EdgeInsets.zero,
                                color: AppleColors.systemBlue,
                                disabledColor: AppleColors.systemBlue.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(25),
                                onPressed: _isAuthenticating ? null : _attemptUnlock,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isAuthenticating) ...[
                                      const CupertinoActivityIndicator(color: Colors.white, radius: 9),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Authenticating...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ] else ...[
                                      const Icon(CupertinoIcons.lock_open_fill, size: 20, color: Colors.white),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Unlock AeroFiles',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ],
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
          ],
        );
      },
    );
  }
}
