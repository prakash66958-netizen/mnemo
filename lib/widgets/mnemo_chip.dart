import 'package:flutter/material.dart';

import '../core/theme/design_tokens.dart';

/// A small pill used for tags, meta info ("#work", "Read Later", "Tue 9:00").
/// Mirrors `.tag` / `.tag.accent` / `.tag.bell` from the HTML mockup.
class MnemoChip extends StatelessWidget {
  const MnemoChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.tinted = false,
  });

  /// Variant that uses the primary color tint (like "Read Later" in the
  /// mockup).
  const MnemoChip.accent({
    super.key,
    required this.label,
    this.icon,
  })  : color = null,
        tinted = true;

  /// Reminder-style (red bell) chip.
  const MnemoChip.bell({
    super.key,
    required this.label,
  })  : icon = Icons.alarm_rounded,
        color = const Color(0xFFEF4444),
        tinted = true;

  final String label;
  final IconData? icon;
  final Color? color;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    Color bg;
    Color fg;
    if (tinted) {
      final base = color ?? scheme.primary;
      bg = DesignTokens.chipTint(base, brightness);
      fg = base;
    } else {
      bg = scheme.surfaceContainer;
      fg = scheme.onSurfaceVariant;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 7 : 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.rChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
