import 'package:flutter/material.dart';

/// Central palette for Sketchify. Most widgets should read colors from
/// [ThemeData.colorScheme]; these constants are used for brand moments and
/// status colors that must stay recognizable in both themes.
abstract final class AppColors {
  static const Color ink = Color(0xFF080B10);
  static const Color surface = Color(0xFF11161F);
  static const Color surfaceHigh = Color(0xFF1A212D);
  static const Color surfaceHighest = Color(0xFF242D3C);

  static const Color primary = Color(0xFFFF7A45);
  static const Color primaryDeep = Color(0xFFE85A24);
  static const Color primarySoft = Color(0xFFFFB48F);
  static const Color secondary = Color(0xFF8B7CFF);
  static const Color accent = Color(0xFF4CC9F0);

  static const Color success = Color(0xFF38D996);
  static const Color warning = Color(0xFFF7C948);
  static const Color danger = Color(0xFFFF6B6B);

  static const Color textPrimary = Color(0xFFF4F6FA);
  static const Color textSecondary = Color(0xFF98A4B7);
  static const Color outline = Color(0xFF33405A);

  static const Color paper = Color(0xFFF7F3EC);
  static const Color paperInk = Color(0xFF1A1C22);
}
