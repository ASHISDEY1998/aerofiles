import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/home_shell.dart';
import 'services/log_service.dart';
import 'services/security/biometric_service.dart';
import 'services/security/safe_vault_service.dart';
import 'services/settings_service.dart';
import 'theme/apple_theme.dart';
import 'widgets/app_lock_overlay.dart';
import 'widgets/transfer_progress_bubble.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize diagnostics logging
  await LogService.instance.init();

  // Initialize biometric & app lock service
  await BiometricService.instance.init();

  // Initialize safe vault service
  await SafeVaultService.instance.init();

  // Global uncaught error hooks
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    LogService.instance.error('FLUTTER', details.exceptionAsString(), details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    LogService.instance.error('PLATFORM', error.toString(), error, stack);
    return false;
  };

  // Initialize universal video engine (libmpv)
  MediaKit.ensureInitialized();

  // Initialize persistent user settings
  await SettingsService.instance.init();

  runApp(const AeroFilesApp());
}

class AeroFilesApp extends StatelessWidget {
  const AeroFilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final mode = SettingsService.instance.themeMode;
        final isDark = mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);

        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: isDark ? AppleColors.darkCard : AppleColors.lightCard,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ),
        );

        return MaterialApp(
          title: 'AeroFiles',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: AppleTheme.lightTheme,
          darkTheme: AppleTheme.darkTheme,
          home: const HomeShell(),
          builder: (context, child) => AppLockOverlay(
            child: TransferProgressOverlay(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
