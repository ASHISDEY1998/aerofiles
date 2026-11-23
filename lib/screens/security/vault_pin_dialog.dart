import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/security/safe_vault_service.dart';
import '../../theme/apple_theme.dart';

enum VaultPinMode { setup, unlock, change }

class VaultPinDialog extends StatefulWidget {
  final VaultPinMode mode;

  const VaultPinDialog({
    super.key,
    required this.mode,
  });

  static Future<bool> show(BuildContext context, {VaultPinMode mode = VaultPinMode.unlock}) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: mode == VaultPinMode.unlock,
      barrierLabel: 'Safe Vault',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) => VaultPinDialog(mode: mode),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
    return result ?? false;
  }

  @override
  State<VaultPinDialog> createState() => _VaultPinDialogState();
}

class _VaultPinDialogState extends State<VaultPinDialog> with SingleTickerProviderStateMixin {
  final _vaultService = SafeVaultService.instance;
  late AnimationController _shakeController;

  // Stages:
  // Setup: 0 = enter pin, 1 = confirm pin
  // Unlock: 0 = enter pin
  // Change: 0 = enter current pin, 1 = enter new pin, 2 = confirm new pin
  int _stage = 0;
  String _currentInput = '';
  String _stagedNewPin = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // Auto-prompt biometrics if in unlock mode
    if (widget.mode == VaultPinMode.unlock && _vaultService.isBiometricsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryBiometricUnlock();
      });
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometricUnlock() async {
    final success = await _vaultService.authenticateBiometrics();
    if (success && mounted) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    }
  }

  void _onDigitPressed(String digit) {
    if (_currentInput.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _currentInput += digit;
      _errorMessage = null;
    });

    if (_currentInput.length == 4) {
      _processInput(_currentInput);
    }
  }

  void _onDeletePressed() {
    if (_currentInput.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentInput = _currentInput.substring(0, _currentInput.length - 1);
      _errorMessage = null;
    });
  }

  void _shakeAndReset({String? error}) {
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0.0);
    setState(() {
      _currentInput = '';
      _errorMessage = error;
    });
  }

  Future<void> _processInput(String pin) async {
    if (widget.mode == VaultPinMode.unlock) {
      if (_vaultService.verifyPin(pin)) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
      } else {
        _shakeAndReset(error: 'Incorrect Vault PIN');
      }
    } else if (widget.mode == VaultPinMode.setup) {
      if (_stage == 0) {
        _stagedNewPin = pin;
        setState(() {
          _stage = 1;
          _currentInput = '';
        });
      } else if (_stage == 1) {
        if (pin == _stagedNewPin) {
          final ok = await _vaultService.setVaultPin(pin);
          if (ok && mounted) {
            HapticFeedback.mediumImpact();
            Navigator.of(context).pop(true);
          } else {
            _shakeAndReset(error: 'Failed to save PIN. Try again.');
          }
        } else {
          _shakeAndReset(error: 'PINs do not match. Re-enter PIN.');
          setState(() {
            _stage = 0;
            _stagedNewPin = '';
          });
        }
      }
    } else if (widget.mode == VaultPinMode.change) {
      if (_stage == 0) {
        if (_vaultService.verifyPin(pin)) {
          setState(() {
            _stage = 1;
            _currentInput = '';
          });
        } else {
          _shakeAndReset(error: 'Current PIN is incorrect');
        }
      } else if (_stage == 1) {
        _stagedNewPin = pin;
        setState(() {
          _stage = 2;
          _currentInput = '';
        });
      } else if (_stage == 2) {
        if (pin == _stagedNewPin) {
          final ok = await _vaultService.setVaultPin(pin);
          if (ok && mounted) {
            HapticFeedback.mediumImpact();
            Navigator.of(context).pop(true);
          } else {
            _shakeAndReset(error: 'Failed to update PIN');
          }
        } else {
          _shakeAndReset(error: 'PINs do not match. Re-enter new PIN.');
          setState(() {
            _stage = 1;
            _stagedNewPin = '';
          });
        }
      }
    }
  }

  String get _title {
    if (widget.mode == VaultPinMode.unlock) {
      return 'Safe Vault';
    } else if (widget.mode == VaultPinMode.setup) {
      return _stage == 0 ? 'Create Vault PIN' : 'Confirm Vault PIN';
    } else {
      if (_stage == 0) return 'Enter Current PIN';
      if (_stage == 1) return 'Enter New PIN';
      return 'Confirm New PIN';
    }
  }

  String get _subtitle {
    if (widget.mode == VaultPinMode.unlock) {
      return 'Enter your Safe Vault PIN to decrypt and access hidden files';
    } else if (widget.mode == VaultPinMode.setup) {
      return _stage == 0
          ? 'Set a custom 4-digit PIN separate from your device lock'
          : 'Repeat your 4-digit PIN to confirm';
    } else {
      if (_stage == 0) return 'Verify your current Vault PIN first';
      if (_stage == 1) return 'Choose a new 4-digit PIN';
      return 'Repeat your new 4-digit PIN to confirm';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: AppleColors.darkCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppleColors.borderStroke,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 36,
                    spreadRadius: 8,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Close button if dismissible
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppleColors.systemBlue.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.lock_shield_fill,
                          color: AppleColors.systemBlue,
                          size: 26,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          CupertinoIcons.xmark_circle_fill,
                          color: AppleColors.textTertiary,
                          size: 26,
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Title & Subtitle
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppleColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppleColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // PIN Dots with shake animation
                  AnimatedBuilder(
                    animation: _shakeController,
                    builder: (context, child) {
                      final offset = 16 *
                          (1 - _shakeController.value) *
                          (Curves.elasticIn.transform(_shakeController.value) * 2 - 1);
                      return Transform.translate(
                        offset: Offset(offset.isNaN ? 0.0 : offset, 0),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final isFilled = index < _currentInput.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFilled
                                ? AppleColors.systemBlue
                                : AppleColors.darkElevated,
                            border: Border.all(
                              color: isFilled
                                  ? AppleColors.systemBlue
                                  : AppleColors.borderStroke,
                              width: 1.5,
                            ),
                            boxShadow: isFilled
                                ? [
                                    BoxShadow(
                                      color: AppleColors.systemBlue.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        );
                      }),
                    ),
                  ),

                  // Error message
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: _errorMessage != null
                          ? Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppleColors.systemRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : null,
                    ),
                  ),

                  // Keypad
                  _buildKeypad(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        _buildKeyRow(['1', '2', '3']),
        const SizedBox(height: 14),
        _buildKeyRow(['4', '5', '6']),
        const SizedBox(height: 14),
        _buildKeyRow(['7', '8', '9']),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Biometric or empty
            widget.mode == VaultPinMode.unlock
                ? _buildActionButton(
                    icon: CupertinoIcons.viewfinder,
                    onTap: _tryBiometricUnlock,
                    tooltip: 'Fingerprint / Biometric',
                  )
                : const SizedBox(width: 72, height: 72),
            _buildDigitButton('0'),
            _buildActionButton(
              icon: CupertinoIcons.delete_left_fill,
              onTap: _onDeletePressed,
              tooltip: 'Delete',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _buildDigitButton(d)).toList(),
    );
  }

  Widget _buildDigitButton(String digit) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onDigitPressed(digit),
        borderRadius: BorderRadius.circular(36),
        splashColor: AppleColors.systemBlue.withValues(alpha: 0.2),
        highlightColor: AppleColors.darkElevated,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppleColors.darkElevated.withValues(alpha: 0.6),
            border: Border.all(
              color: AppleColors.borderStroke,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            digit,
            style: const TextStyle(
              color: AppleColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(36),
        splashColor: AppleColors.systemBlue.withValues(alpha: 0.2),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(
            icon,
            color: AppleColors.textSecondary,
            size: 26,
          ),
        ),
      ),
    );
  }
}
