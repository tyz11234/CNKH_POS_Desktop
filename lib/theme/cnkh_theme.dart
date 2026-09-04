import 'package:flutter/material.dart';

/// CNKH Hardware POS design tokens (aligned with desktop app.qss).
class CnkhColors {
  static const navy = Color(0xFF102E64);
  static const deepNavy = Color(0xFF071B36);
  static const topBar = Color(0xFF081F3D);
  static const primary = Color(0xFF1769E0);
  static const primaryHover = Color(0xFF0F5CCB);
  static const success = Color(0xFF16A34A);
  static const successDeep = Color(0xFF12833D);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFE5484D);
  static const canvas = Color(0xFFF3F6FA);
  static const ink = Color(0xFF10213A);
  static const muted = Color(0xFF68768A);
  static const border = Color(0xFFDCE3EC);
  static const card = Colors.white;
  static const softBlue = Color(0xFFEEF3FA);
}

ThemeData buildCnkhTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: CnkhColors.primary,
    primary: CnkhColors.primary,
    secondary: CnkhColors.navy,
    surface: CnkhColors.card,
    error: CnkhColors.danger,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: CnkhColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: CnkhColors.topBar,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: CnkhColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: CnkhColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CnkhColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CnkhColors.navy,
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: CnkhColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFC9D3E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFC9D3E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CnkhColors.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: CnkhColors.softBlue,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? CnkhColors.primary : CnkhColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? CnkhColors.primary : CnkhColors.muted,
          size: 26,
        );
      }),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        color: CnkhColors.ink,
        fontWeight: FontWeight.w800,
        fontSize: 24,
      ),
      titleLarge: TextStyle(
        color: CnkhColors.ink,
        fontWeight: FontWeight.w800,
        fontSize: 20,
      ),
      titleMedium: TextStyle(
        color: CnkhColors.ink,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      bodyLarge: TextStyle(color: CnkhColors.ink, fontSize: 16),
      bodyMedium: TextStyle(color: CnkhColors.ink, fontSize: 14),
      bodySmall: TextStyle(color: CnkhColors.muted, fontSize: 12),
    ),
  );
}
