import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AegisTheme {
  // Deep OLED black and Neon Cyan
  static const Color oledBlack = Color(0xFF000000);
  static const Color neonCyan = Color(0xFF00FFFF);

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: oledBlack,
      primaryColor: neonCyan,
      colorScheme: const ColorScheme.dark(
        primary: neonCyan,
        surface: oledBlack,
      ),
      textTheme: GoogleFonts.jetBrainsMonoTextTheme(
        ThemeData.dark().textTheme.copyWith(
          bodyLarge: const TextStyle(color: neonCyan),
          bodyMedium: const TextStyle(color: neonCyan),
          displayLarge: const TextStyle(color: neonCyan),
          titleLarge: const TextStyle(color: neonCyan),
        ),
      ).apply(
        bodyColor: neonCyan,
        displayColor: neonCyan,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: oledBlack,
        foregroundColor: neonCyan,
        elevation: 0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: oledBlack,
        selectedItemColor: neonCyan,
        unselectedItemColor: Colors.white54,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: oledBlack,
          foregroundColor: neonCyan,
          side: const BorderSide(color: neonCyan, width: 2),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
