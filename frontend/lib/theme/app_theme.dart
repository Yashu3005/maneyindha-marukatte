import 'package:flutter/material.dart';

/// Figma olive system: olive canvas for onboarding, warm paper for the app,
/// cream cards/buttons, serif display type.
abstract class MMColors {
  static const olive = Color(0xFF75845C);      // Figma canvas green
  static const deepOlive = Color(0xFF3E4A22);  // headings / primary actions
  static const sage = Color(0xFFD9DFC4);       // chips / containers
  static const cream = Color(0xFFEDEBDD);      // Figma buttons & cards
  static const marigold = Color(0xFFD9922E);   // rating accent
  static const paper = Color(0xFFFAF8F1);      // app background
  static const card = Color(0xFFFFFFFF);
  static const clay = Color(0xFFC8693B);       // warm accent for highlights / badges
  static const blush = Color(0xFFF6E7DA);      // soft warm tint for banners
  static const moss = Color(0xFF5B6B3F);       // mid olive for gradients

  /// Olive canvas gradient used behind onboarding screens (was a flat colour).
  static const oliveGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF8A9A6E), olive, Color(0xFF5E6E44)],
  );
  /// Hero banner gradient for the customer home.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [deepOlive, moss, olive],
  );
}

const serifFamily = 'Georgia';

TextStyle serif(double size,
        {FontWeight weight = FontWeight.w600, Color color = MMColors.deepOlive}) =>
    TextStyle(
      fontFamily: serifFamily,
      fontFamilyFallback: const ['Times New Roman', 'serif'],
      fontSize: size,
      fontWeight: weight,
      color: color,
    );

abstract class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: MMColors.olive,
      primary: MMColors.deepOlive,
      secondary: MMColors.olive,
      secondaryContainer: MMColors.sage,
      tertiary: MMColors.marigold,
      surface: MMColors.card,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MMColors.paper,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      }),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MMColors.deepOlive,
        contentTextStyle: const TextStyle(color: MMColors.cream, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MMColors.paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MMColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: serif(20),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: MMColors.paper,
        foregroundColor: MMColors.deepOlive,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: serif(20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: MMColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: MMColors.sage),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: MMColors.sage,
        side: BorderSide(color: Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MMColors.cream,
        indicatorColor: MMColors.sage,
        labelTextStyle:
            WidgetStatePropertyAll(serif(12, weight: FontWeight.w600)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MMColors.deepOlive,
          foregroundColor: MMColors.cream,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MMColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MMColors.sage),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MMColors.sage),
        ),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: MMColors.olive, brightness: Brightness.dark),
      );
}
