import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../log_service.dart';

class BiometricService {
  static final BiometricService instance = BiometricService._();
  BiometricService._();

  static const String _keyAppLock = 'aerofiles_app_lock_enabled';

  final LocalAuthentication _auth = LocalAuthentication();
  SharedPreferences? _prefs;

  final ValueNotifier<bool> isAppLocked = ValueNotifier<bool>(false);
  bool _isLockEnabled = false;

  bool get isAppLockEnabled => _isLockEnabled;

  Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _isLockEnabled = _prefs?.getBool(_keyAppLock) ?? false;
      if (_isLockEnabled) {
        isAppLocked.value = true;
      }
    } catch (e) {
      LogService.instance.error('BIOMETRIC', 'Failed to initialize BiometricService: $e');
    }
  }

  /// Checks whether biometric authentication or device credentials (PIN/pattern) are available.
  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException catch (e) {
      LogService.instance.warn('BIOMETRIC', 'canAuthenticate exception: $e');
      return false;
    }
  }

  /// Prompts user to authenticate using Fingerprint, Face ID, or Device PIN.
  Future<bool> authenticate({String reason = 'Authenticate to access AeroFiles'}) async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (authenticated) {
        isAppLocked.value = false;
        LogService.instance.info('BIOMETRIC', 'Authentication successful, app unlocked');
      }
      return authenticated;
    } on PlatformException catch (e) {
      LogService.instance.error('BIOMETRIC', 'Authentication failed with error: $e');
      return false;
    }
  }

  /// Enables or disables App Lock in SharedPreferences.
  Future<bool> setAppLockEnabled(bool enabled) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_keyAppLock, enabled);
      _isLockEnabled = enabled;
      if (!enabled) {
        isAppLocked.value = false;
      }
      LogService.instance.info('BIOMETRIC', 'App lock set to: $enabled');
      return true;
    } catch (e) {
      LogService.instance.error('BIOMETRIC', 'Failed to update app lock setting: $e');
      return false;
    }
  }

  /// Locks the app (e.g. when app goes to background).
  void lock() {
    if (_isLockEnabled) {
      isAppLocked.value = true;
    }
  }

  /// Force unlock (only used when lock is disabled).
  void forceUnlock() {
    isAppLocked.value = false;
  }
}
