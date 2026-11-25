import 'package:flutter/material.dart';

/// Tema gamer/tech: fundo escuro, azul escuro principal, roxo e ciano.
class AppTheme {
  static const bg = Color(0xFF080D1C);
  static const surface = Color(0xFF0E1630);
  static const card = Color(0xFF131D3B);
  static const blue = Color(0xFF2B4BD6);
  static const purple = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF22D3EE);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF4C6FFF),
      secondary: purple,
      tertiary: cyan,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withAlpha(14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// Mantido por compatibilidade com telas antigas.
  static ThemeData get light => dark;
}
