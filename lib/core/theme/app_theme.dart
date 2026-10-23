import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — the same values as the web app's `src/styles/tokens.css`.
/// Keep them in sync with that file (and the Claude Design project), not edited here alone.
class AppColors {
  AppColors._();

  static const navy900 = Color(0xFF0D1832);
  static const navy800 = Color(0xFF14244B);
  static const navy700 = Color(0xFF1D356D);
  static const navy600 = Color(0xFF2A4788);
  static const navy500 = Color(0xFF3C5DA3);
  static const navy300 = Color(0xFF8EA1C9);
  static const navy200 = Color(0xFFC3CFE6);
  static const navy100 = Color(0xFFE4EAF5);
  static const navy050 = Color(0xFFF2F5FB);

  static const white = Color(0xFFFFFFFF);
  static const grey050 = Color(0xFFF7F8FA);
  static const grey100 = Color(0xFFEEF0F4);
  static const grey200 = Color(0xFFE1E4EA);
  static const grey300 = Color(0xFFC8CCD6);
  static const grey400 = Color(0xFF9AA1B0);
  static const grey500 = Color(0xFF6D7484);
  static const grey600 = Color(0xFF4D5462);
  static const grey700 = Color(0xFF343A46);
  static const grey900 = Color(0xFF14171D);

  static const teal700 = Color(0xFF0F6F62);
  static const teal600 = Color(0xFF157F6E);
  static const teal100 = Color(0xFFDCEFEB);
  static const green600 = Color(0xFF1F7A4D);
  static const green100 = Color(0xFFE2F2E9);
  static const amber600 = Color(0xFFA1650A);
  static const amber100 = Color(0xFFFBEED3);
  static const red600 = Color(0xFFB3271F);
  static const red100 = Color(0xFFFBE4E2);

  static const hairline = grey200;
  static const strong = grey300;

  /// Chart series colours, in order (matches the web dashboards' palette).
  static const series = [
    Color(0xFF1E90FF), Color(0xFF00D68F), Color(0xFFFFA51F), Color(0xFF6B45B4), //
    Color(0xFFB83C56), Color(0xFF4CA383), Color(0xFF9D7C2E), Color(0xFF2E4A6B),
  ];

  /// Pie / donut slices (same as the web dashboard's PIE_COLORS).
  static const pie = [
    Color(0xFF4CA383), Color(0xFF9D7C2E), Color(0xFF6B45B4), Color(0xFFB83C56), //
    Color(0xFF2E4A6B), Color(0xFF1E90FF), Color(0xFF00D68F), Color(0xFFFFA51F),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy700,
        primary: AppColors.navy700,
        onPrimary: AppColors.white,
        secondary: AppColors.teal600,
        error: AppColors.red600,
        surface: AppColors.white,
      ),
      scaffoldBackgroundColor: AppColors.grey050,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: GoogleFonts.poppins().fontFamily,
        bodyColor: AppColors.navy900,
        displayColor: AppColors.navy900,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.navy900,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy900),
        shape: const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(side: BorderSide(color: AppColors.hairline)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.hairline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.strong)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.strong)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.navy700, width: 1.5)),
        labelStyle: const TextStyle(color: AppColors.grey600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy700,
          foregroundColor: AppColors.white,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy700,
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: AppColors.strong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: AppColors.navy900),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  /// Small uppercase label used above section titles ("DEVICE ALERTS", "CANVAS"…).
  static TextStyle eyebrow() =>
      GoogleFonts.poppins(fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w500, color: AppColors.grey500);
}
