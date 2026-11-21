import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/home_shell.dart';
import 'services/settings_service.dart';
import 'theme/apple_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        );
      },
    );
  }
}
