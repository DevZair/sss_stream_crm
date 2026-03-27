import 'package:flutter/cupertino.dart';

class AppColors {
  const AppColors._();

  // iOS system blue
  static const Color primary = Color(0xFF007AFF);
  // iOS system green
  static const Color accent = Color(0xFF34C759);
  // My-message bubble (iMessage blue)
  static const Color myBubble = Color(0xFF007AFF);
  // Their-message bubble
  static const Color theirBubble = Color(0xFF3A3A3C);
  static const Color theirBubbleLight = Color(0xFFE5E5EA);

  // --- Dark palette (iOS dark) ---
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceSecondary = Color(0xFF2C2C2E);
  static const Color surfaceTertiary = Color(0xFF3A3A3C);
  static const Color border = Color(0xFF38383A);
  static const Color separator = Color(0xFF38383A);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color error = Color(0xFFFF3B30);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);

  // --- Light palette (iOS light) ---
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = CupertinoColors.white;
  static const Color lightSurfaceSecondary = Color(0xFFE5E5EA);
  static const Color lightSurfaceTertiary = Color(0xFFD1D1D6);
  static const Color lightBorder = Color(0xFFC6C6C8);
  static const Color lightSeparator = Color(0xFFC6C6C8);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF8E8E93);
}
