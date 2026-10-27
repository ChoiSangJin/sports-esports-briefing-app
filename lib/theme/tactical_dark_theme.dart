import 'package:flutter/material.dart';
import '../models/unified_match_model.dart';

abstract final class TacticalColors {
  static const background = Color(0xFF0B0C10);
  static const card = Color(0xFF161B22);
  static const elevated = Color(0xFF1F2833);
  static const border = Color(0xFF2D3748);
  static const secondary = Color(0xFF94A3B8);
  static const muted = Color(0xFF475569);
  static const violet = Color(0xFF8B5CF6);
  static Color league(League league) => switch (league) {
    League.f1 => const Color(0xFFFF1801),
    League.lol => const Color(0xFF00F0FF),
    League.nba => const Color(0xFFFF6B00),
    League.nfl => const Color(0xFF3B82F6),
    League.mlb => const Color(0xFF10B981),
    League.kbo => const Color(0xFF84CC16),
  };
}

const scoreStyle = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w800,
  fontFeatures: [FontFeature.tabularFigures()],
);

ThemeData tacticalDarkTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: TacticalColors.background,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF00F0FF),
    secondary: TacticalColors.violet,
    surface: TacticalColors.card,
  ),
  appBarTheme: const AppBarTheme(backgroundColor: TacticalColors.background),
  dividerColor: TacticalColors.border,
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: TacticalColors.elevated,
    showDragHandle: true,
  ),
);
