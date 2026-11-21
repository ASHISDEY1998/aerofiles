import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppleColors {
  // Dark Surface Colors
  static const Color pureBlack = Color(0xFF000000);
  static const Color darkCard = Color(0xFF1C1C1E);
  static const Color darkElevated = Color(0xFF2C2C2E);
  static const Color darkTertiary = Color(0xFF3A3A3C);
  static const Color borderStroke = Color(0x1FFFFFFF);

  // Light Surface Colors
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFE5E5EA);
  static const Color lightBorderStroke = Color(0x1F000000);

  // Accent Colors
  static const Color systemBlue = Color(0xFF0A84FF);
  static const Color systemBlueLight = Color(0xFF007AFF);
  static const Color systemBlueSubtle = Color(0x260A84FF);
  static const Color systemIndigo = Color(0xFF5E5CE6);
  static const Color systemTeal = Color(0xFF64D2FF);
  static const Color systemGreen = Color(0xFF30D158);
  static const Color systemOrange = Color(0xFFFF9F0A);
  static const Color systemRed = Color(0xFFFF453A);
  static const Color systemPurple = Color(0xFFBF5AF2);
  static const Color systemPink = Color(0xFFFF375F);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF636366);

  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textSecondaryLight = Color(0xFF6C6C70);
  static const Color textTertiaryLight = Color(0xFFC7C7CC);

  // Category Colors
  static const Color catVideos = Color(0xFF0A84FF);   // Blue
  static const Color catImages = Color(0xFFFF375F);   // Pink
  static const Color catAudio = Color(0xFFFF9F0A);    // Orange
  static const Color catDocs = Color(0xFF30D158);     // Green
  static const Color catApps = Color(0xFFBF5AF2);     // Purple
  static const Color catSystem = Color(0xFF636366);   // Dark Gray
  static const Color catOther = Color(0xFF64D2FF);    // Teal
}

class AppleTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppleColors.pureBlack,
      primaryColor: AppleColors.systemBlue,
      canvasColor: AppleColors.pureBlack,
      cardColor: AppleColors.darkCard,
      dividerColor: AppleColors.borderStroke,
      colorScheme: const ColorScheme.dark(
        primary: AppleColors.systemBlue,
        secondary: AppleColors.systemIndigo,
        surface: AppleColors.darkCard,
        error: AppleColors.systemRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppleColors.pureBlack,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppleColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: AppleColors.systemBlue),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppleColors.darkCard,
        selectedItemColor: AppleColors.systemBlue,
        unselectedItemColor: AppleColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: AppleColors.systemBlue,
        barBackgroundColor: Color(0xCC1C1C1E),
        scaffoldBackgroundColor: AppleColors.pureBlack,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppleColors.lightBackground,
      primaryColor: AppleColors.systemBlueLight,
      canvasColor: AppleColors.lightBackground,
      cardColor: AppleColors.lightCard,
      dividerColor: AppleColors.lightBorderStroke,
      colorScheme: const ColorScheme.light(
        primary: AppleColors.systemBlueLight,
        secondary: AppleColors.systemIndigo,
        surface: AppleColors.lightCard,
        error: AppleColors.systemRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppleColors.lightBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppleColors.textPrimaryLight,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: AppleColors.systemBlueLight),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppleColors.lightCard,
        selectedItemColor: AppleColors.systemBlueLight,
        unselectedItemColor: AppleColors.textSecondaryLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: AppleColors.systemBlueLight,
        barBackgroundColor: Color(0xCCFFFFFF),
        scaffoldBackgroundColor: AppleColors.lightBackground,
      ),
    );
  }
}
