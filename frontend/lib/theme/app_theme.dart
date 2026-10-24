import 'package:flutter/material.dart';

/// Figma olive system: olive canvas for onboarding, warm paper for the app,
/// cream cards/buttons, serif display type.
abstract class MMColors {
  static const primaryGreen = Color(0xFF365B1F);  // Deep Leaf Green (#365B1F)
  static const secondaryGreen = Color(0xFF6E8A2F); // Olive Green (#6E8A2F)
  static const accentGold = Color(0xFFE9B949);    // Golden Yellow (#E9B949)
  static const softYellow = Color(0xFFFFF3A6);    // Soft Yellow (#FFF3A6)
  static const warmIvory = Color(0xFFFFFDF5);     // Background (#FFFDF5)
  static const textPrimary = Color(0xFF2F2F2F);   // Primary Text (#2F2F2F)
  static const textSecondary = Color(0xFF555555); // Secondary Text (#555555)

  // Backward compatibility aliases
  static const olive = Color(0xFF6E8A2F);
  static const deepOlive = Color(0xFF365B1F);
  static const sage = Color(0xFFD9DFC4);
  static const cream = Color(0xFFEDEBDD);
  static const marigold = Color(0xFFE9B949);
  static const paper = Color(0xFFFFFDF5);
  static const card = Color(0xFFFFFFFF);
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
