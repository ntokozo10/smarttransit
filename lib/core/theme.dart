import 'package:flutter/material.dart';

const wsuBlue = Color(0xFF0B3D91);
const wsuGold = Color(0xFFF2A900);

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(
    seedColor: wsuBlue,
    secondary: wsuGold,
    brightness: b,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

const okColor = Color(0xFF1B8A3E);
const warnColor = Color(0xFFB26A00);
const badColor = Color(0xFFC62828);
