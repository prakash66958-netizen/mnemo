import 'package:flutter/material.dart';

import '../core/category.dart';
import '../core/theme/design_tokens.dart';

/// Rounded-square category icon used on the left of every memory card.
/// Mirrors `.badge` from the HTML mockup.
///
/// Accepts either a built-in [MemoryCategory] (legacy call sites) or a
/// resolved [CategoryDef] so custom categories render the same way.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({
    super.key,
    this.category,
    this.def,
    this.size = 38,
  }) : assert(category != null || def != null,
            'Provide either category or def');

  final MemoryCategory? category;
  final CategoryDef? def;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = def ?? category!.toDef();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: d.color,
        borderRadius: BorderRadius.circular(DesignTokens.rBadge),
      ),
      child: Icon(d.icon, size: size * 0.52, color: Colors.white),
    );
  }
}

/// Screenshot/image thumbnail placeholder when no image bytes are available.
/// Mirrors `.thumb` from the mockup.
class ThumbBadge extends StatelessWidget {
  const ThumbBadge({
    super.key,
    this.size = 56,
    this.icon = Icons.image_rounded,
  });

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: DesignTokens.thumbGradient(brightness),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        size: size * 0.46,
        color: DesignTokens.thumbIconColor(brightness),
      ),
    );
  }
}
