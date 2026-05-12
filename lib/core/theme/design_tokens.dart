import 'package:flutter/material.dart';

import '../category.dart';

/// Design tokens that mirror the HTML mockup in `design_preview/mnemo_ui.html`.
///
/// Kept separate from `AppTheme` so widgets can reach for spacing, radii and
/// category-tinted surfaces without going through ThemeData. If you change a
/// value here, every screen updates consistently.
class DesignTokens {
  DesignTokens._();

  // Radii (match --r-card / --r-input / --r-btn / --r-chip in the mockup).
  static const double rCard = 20;
  static const double rInput = 16;
  static const double rBtn = 14;
  static const double rChip = 10;
  static const double rFab = 20;
  static const double rBadge = 12;

  // Spacing.
  static const double screenPadH = 16;
  static const double gap = 10;
  static const double gapLg = 14;
  static const double gapXl = 18;

  // Pinned card (amber gradient from the mockup).
  static const LinearGradient pinnedGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
  );
  static const LinearGradient pinnedGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3F2A0C), Color(0xFF4A3312)],
  );
  static const Color pinnedBorderLight = Color(0x40F59E0B);
  static const Color pinnedBorderDark = Color(0x40F59E0B);
  static const Color pinnedTextLight = Color(0xFF422006);
  static const Color pinnedTextDark = Color(0xFFFDE68A);
  static const Color pinnedLabelLight = Color(0xFF92400E);
  static const Color pinnedLabelDark = Color(0xFFFCD34D);

  /// Thumbnail background used by screenshot cards (gradient indigo).
  static LinearGradient thumbGradient(Brightness b) => b == Brightness.light
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC7D2FE), Color(0xFFE0E7FF)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF312E81), Color(0xFF4338CA)],
        );
  static Color thumbIconColor(Brightness b) => b == Brightness.light
      ? const Color(0xFF4338CA)
      : const Color(0xFFC7D2FE);

  /// Soft tint over a category color, used as the faint background behind
  /// Browse tiles.
  static Color categoryTint(MemoryCategory c, Brightness b) {
    final base = c.color;
    return base.withValues(alpha: b == Brightness.light ? 0.10 : 0.16);
  }

  /// Chip-style pill that echoes the "Read Later" accent chip in the mockup.
  static Color chipTint(Color base, Brightness b) =>
      base.withValues(alpha: b == Brightness.light ? 0.12 : 0.20);

  static Color chipInk(Color base, Brightness b) =>
      b == Brightness.light
          ? _darken(base, 0.15)
          : _lighten(base, 0.15);

  static Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  static Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}
