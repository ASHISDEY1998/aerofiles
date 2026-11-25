import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../log_service.dart';

enum AppLockTimeout {
  immediately,
  thirtySeconds,
  oneMinute,
  fiveMinutes,
}

class BiometricService {
  static final BiometricService instance = BiometricService._();
  BiometricService._();

  static const String _keyAppLock = 'aerofiles_app_lock_enabled';
  static const String _keyAppLockTimeout = 'aerofiles_app_lock_timeout';

  final LocalAuthentication _auth = LocalAuthentication();
  SharedPreferences? _prefs;

  final ValueNotifier<bool> isAppLocked = ValueNotifier<bool>(false);
  bool _isLockEnabled = false;
  AppLockTimeout _lockTimeout = AppLockTimeout.immediately;

  bool get isAppLockEnabled => _isLockEnabled;
  AppLockTimeout get lockTimeout => _lockTimeout;

  int get timeoutInSeconds {
    switch (_lockTimeout) {
      case AppLockTimeout.immediately:
        return 0;
      case AppLockTimeout.thirtySeconds:
        return 30;
      case AppLockTimeout.oneMinute:
        return 60;
      case AppLockTimeout.fiveMinutes:
        return 300;
    }
  }

  Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _isLockEnabled = _prefs?.getBool(_keyAppLock) ?? false;
      final timeoutStr = _prefs?.getString(_keyAppLockTimeout);
      if (timeoutStr != null) {
        _lockTimeout = AppLockTimeout.values.firstWhere(
          (e) => e.name == timeoutStr,
          orElse: () => AppLockTimeout.immediately,
        );
      }
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

  /// Sets the inactivity timeout before App Lock engages.
  Future<void> setLockTimeout(AppLockTimeout timeout) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_keyAppLockTimeout, timeout.name);
      _lockTimeout = timeout;
      LogService.instance.info('BIOMETRIC', 'App lock timeout set to: ${timeout.name}');
    } catch (e) {
      LogService.instance.error('BIOMETRIC', 'Failed to update app lock timeout: $e');
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
