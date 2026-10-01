import 'package:flutter/material.dart';

abstract final class StrivoColors {
  static const navy = Color(0xFF102B5C);
  static const deepNavy = Color(0xFF0B2047);
  static const coral = Color(0xFFF34B5B);
  static const canvas = Color(0xFFF5F7FA);
  static const muted = Color(0xFF7B879A);
}

ThemeData buildStrivoTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: StrivoColors.navy,
    primary: StrivoColors.navy,
    secondary: StrivoColors.coral,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: StrivoColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: StrivoColors.deepNavy,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE5E9EF)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFE0E5EC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFE0E5EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: StrivoColors.navy, width: 1.5),
      ),
    ),
  );
}