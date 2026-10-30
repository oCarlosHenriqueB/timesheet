import 'package:flutter/material.dart';

/// Paleta corporativa: azul-marinho no menu, azul nas ações, cinzas no fundo e nas bordas.
/// Cores genéricas, sem a marca oficial da empresa (o logo entra quando houver autorização).
abstract final class AppColors {
  static const navy = Color(0xFF0E2A47);
  static const navyLight = Color(0xFF173A5E);
  static const primary = Color(0xFF1F5FAE);
  static const background = Color(0xFFF3F5F8);
  static const surface = Colors.white;
  static const border = Color(0xFFE1E5EB);
  static const textMuted = Color(0xFF5F6B7A);
  static const sidebarText = Color(0xFFC9D4E2);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
  );
  const radius = BorderRadius.all(Radius.circular(10));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.compact,
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.border)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
    ),
    dataTableTheme: const DataTableThemeData(
      headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted, fontSize: 12),
      dataTextStyle: TextStyle(fontSize: 13, color: Color(0xFF1F2933)),
      headingRowHeight: 40,
      dividerThickness: 0.6,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}
