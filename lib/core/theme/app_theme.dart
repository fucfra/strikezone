import 'package:flutter/material.dart';

import 'app_spacing.dart';

export 'app_spacing.dart';

class AppTheme {
  // Colori di base (UI scura + verde neon più acceso)
  static const Color backgroundColor = Color(0xFF131D10);
  static const Color surfaceColor = Color(0xFF0C1426);
  static const Color inputFillColor = Color(0xFF060D18);
  static const Color primaryText = Color(0xFFF1F5F9);
  static const Color secondaryText = Color(0xFF94A3B8);
  /// Verde neon principale (accenti, selezioni, KPI).
  static const Color accentGreen = Color(0xFF4CFF00);
  static const Color accentRed = Color(0xFFFF4D4D);
  static const Color panelBorderMuted = Color(0xFF334155);

  /// Bagliore leggero su testo accent (titoli / numeri evidenziati).
  static List<Shadow> neonTextGlow({
    Color color = accentGreen,
    double blurInner = 10,
    double blurOuter = 22,
  }) {
    return [
      Shadow(color: color.withValues(alpha: 0.78), blurRadius: blurInner),
      Shadow(color: color.withValues(alpha: 0.38), blurRadius: blurOuter),
    ];
  }

  // Colori pulsanti
  static const Color buttonPrimaryBg = Color(0xFF008000); // Verde scuro
  static const Color buttonPrimaryText = Color(0xFFFFFFFF); // Bianco assoluto
  static const Color buttonSecondaryBg = Color(0xFF1E293B); // Slate navy
  static const Color buttonSecondaryBorder = Color(0xFF334155);

  static ThemeData darkTheme() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      primaryColor: accentGreen,
      colorScheme: const ColorScheme.dark(
        primary: accentGreen,
        secondary: accentGreen,
        surface: surfaceColor,
        error: accentRed,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: primaryText,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: TextStyle(color: primaryText),
        bodyMedium: TextStyle(color: secondaryText),
        labelSmall: TextStyle(color: secondaryText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        contentPadding: AppSpacing.inputTouch,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentGreen, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accentRed, width: 1.5),
        ),
        labelStyle: const TextStyle(color: secondaryText),
        hintStyle: const TextStyle(color: secondaryText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonPrimaryBg,
          foregroundColor: buttonPrimaryText,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentGreen),
      ),
    );
  }
}
