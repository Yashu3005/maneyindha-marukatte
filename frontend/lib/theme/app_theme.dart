import 'package:flutter/material.dart';

/// Brand palette (section 16 of the spec).
abstract class MMColors {
  static const primary = Color(0xFFE91E63);
  static const secondary = Color(0xFFF8BBD0);
  static const accent = Color(0xFFFF9800);
  static const background = Color(0xFFFAFAFA);
  static const card = Color(0xFFFFFFFF);
}

abstract class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MMColors.primary,
          primary: MMColors.primary,
          secondary: MMColors.secondary,
          tertiary: MMColors.accent,
          surface: MMColors.card,
        ),
        scaffoldBackgroundColor: MMColors.background,
        cardTheme: CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MMColors.primary,
          brightness: Brightness.dark,
        ),
      );
}
