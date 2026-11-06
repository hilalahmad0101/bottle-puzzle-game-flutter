import 'package:flutter/material.dart';

/// Brand palette. Liquid colours for gameplay are defined later in the
/// rendering module; these are UI-chrome colours only.
abstract final class AppColors {
  // Dark "alchemy lab" surfaces.
  static const inkDeep = Color(0xFF0B0F1E);
  static const ink = Color(0xFF131A30);
  static const inkRaised = Color(0xFF1B2440);

  // Light surfaces.
  static const parchment = Color(0xFFF7F4EE);
  static const parchmentRaised = Color(0xFFFFFFFF);

  // Midnight laboratory scene.
  static const midnightTop = Color(0xFF070B1C);
  static const midnightMid = Color(0xFF111738);
  static const midnightBottom = Color(0xFF1D1244);

  // Metals and light.
  static const gold = Color(0xFFFFC25A);
  static const goldDeep = Color(0xFFE0A93E);
  static const goldLight = Color(0xFFFFEFB8);
  static const cyanGlow = Color(0xFF58F0FF);
  static const rose = Color(0xFFFF6BE0);

  // Glass surfaces.
  static const glassFill = Color(0x14FFFFFF);
  static const glassFillStrong = Color(0x24FFFFFF);
  static const glassBorder = Color(0x33FFFFFF);

  // Text on the dark scene.
  static const textPrimary = Color(0xFFF2F4FF);
  static const textSecondary = Color(0xFFA9B0D6);

  // Accents.
  static const prism = Color(0xFF7C5CFF);
  static const aqua = Color(0xFF3DDCFF);
  static const ember = Color(0xFFFFB347);
}
