import 'package:flutter/material.dart';

/// Design tokens: Warm cream, deep forest green accents, tasteful terracotta highlights.
abstract class MMColors {
  // Brand greens (Deep Evergreen / Olive)
  static const deepOlive = Color(0xFF263A23);  // primary actions, headings, logo
  static const olive = Color(0xFF4A6242);      // secondary actions, icons
  static const oliveLight = Color(0xFF6B8462); // muted accents
  static const sage = Color(0xFFD2DEC9);       // chips, soft borders
  static const sageLight = Color(0xFFEFF5EC);  // soft highlights, success backgrounds

  // Warm cream & paper backgrounds
  static const paper = Color(0xFFFAF7F2);      // primary app canvas
  static const cream = Color(0xFFF3ECE0);      // container background, buttons, pills
  static const creamLight = Color(0xFFF9F5EE); // elevated cards on paper
  static const card = Color(0xFFFFFFFF);       // clean cards
  static const sand = Color(0xFFE7DFD0);       // subtle dividers

  // Warm Indian Accents (Terracotta & Marigold)
  static const terracotta = Color(0xFFC35634);      // tasteful highlights, badges, primary CTA alt
  static const terracottaDark = Color(0xFFA44122);  // active terracotta
  static const terracottaLight = Color(0xFFFBECE6); // soft terracotta badges
  static const marigold = Color(0xFFD98A18);        // ratings, stars, festive highlights
  static const marigoldLight = Color(0xFFFEF5E7);   // rating badges background

  // Text colors (accessible, high contrast)
  static const textPrimary = Color(0xFF1E281C);
  static const textSecondary = Color(0xFF4E5E4C);
  static const textMuted = Color(0xFF7A8A78);

  // Borders & Shadows
  static const border = Color(0xFFE3DCCE);
  static const borderLight = Color(0xFFEDE7DC);
  static const shadow = Color(0x0C1E281C);

  // Semantic UI aliases
  static const ink = textPrimary;
  static const muted = textMuted;
  static const surface = card;
}

const serifFamily = 'Georgia';

TextStyle serif(
  double size, {
  FontWeight weight = FontWeight.w600,
  Color color = MMColors.deepOlive,
  double? height,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamily: serifFamily,
      fontFamilyFallback: const ['Merriweather', 'Times New Roman', 'serif'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

TextStyle sans(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = MMColors.textPrimary,
  double? height,
  double? letterSpacing,
}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

/// Responsive layout breakpoints
abstract class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 960;
  static const double desktop = 1200;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= mobile && w < desktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;

  static int gridColumns(BuildContext context, {int min = 2, int max = 5}) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 480) return 2;
    if (w < 768) return 2;
    if (w < 1080) return 3;
    if (w < 1360) return 4;
    return max;
  }
}

abstract class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: MMColors.deepOlive,
      onPrimary: MMColors.cream,
      primaryContainer: MMColors.sageLight,
      onPrimaryContainer: MMColors.deepOlive,
      secondary: MMColors.olive,
      onSecondary: Colors.white,
      secondaryContainer: MMColors.sage,
      onSecondaryContainer: MMColors.deepOlive,
      tertiary: MMColors.terracotta,
      onTertiary: Colors.white,
      tertiaryContainer: MMColors.terracottaLight,
      onTertiaryContainer: MMColors.terracottaDark,
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: MMColors.card,
      onSurface: MMColors.textPrimary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: MMColors.creamLight,
      surfaceContainer: MMColors.cream,
      surfaceContainerHigh: MMColors.sand,
      outline: MMColors.border,
      outlineVariant: MMColors.borderLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: MMColors.paper,
      appBarTheme: AppBarTheme(
        backgroundColor: MMColors.paper,
        foregroundColor: MMColors.deepOlive,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: serif(20, weight: FontWeight.w700),
        iconTheme: const IconThemeData(color: MMColors.deepOlive),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: MMColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: MMColors.borderLight, width: 1.2),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MMColors.cream,
        selectedColor: MMColors.deepOlive,
        secondarySelectedColor: MMColors.deepOlive,
        labelStyle: sans(13, weight: FontWeight.w500, color: MMColors.textPrimary),
        secondaryLabelStyle: sans(13, weight: FontWeight.w600, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: MMColors.borderLight),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: MMColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        indicatorColor: MMColors.sageLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return sans(
            12,
            weight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? MMColors.deepOlive : MMColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? MMColors.deepOlive : MMColors.textMuted,
            size: 24,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MMColors.deepOlive,
          foregroundColor: MMColors.cream,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: sans(15, weight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MMColors.deepOlive,
          side: const BorderSide(color: MMColors.deepOlive, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: sans(15, weight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MMColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: sans(14, color: MMColors.textMuted),
        labelStyle: sans(14, color: MMColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MMColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MMColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MMColors.deepOlive, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: MMColors.borderLight,
        thickness: 1,
        space: 24,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MMColors.deepOlive,
        contentTextStyle: sans(14, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MMColors.olive,
          brightness: Brightness.dark,
        ),
      );
}
