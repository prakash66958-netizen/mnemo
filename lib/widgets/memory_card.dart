import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/category.dart';
import '../core/theme/design_tokens.dart';
import '../models/memory_item.dart';
import '../services/category_service.dart';
import 'category_badge.dart';
import 'mnemo_chip.dart';

/// Inbox list card. Mirrors `.card` from the HTML mockup:
///
///   [ badge ]  Label          time
///              url (optional)
///              content text (2 lines)
///              [chip] [chip] [chip]
///
/// Screenshot items swap the solid colored badge for a gradient
/// [ThumbBadge] (or the actual image if small enough).
class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.onSwipeArchive,
    this.onSwipePin,
    this.dense = false,
    this.trailingChips = const [],
  });

  final MemoryItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSwipeArchive;
  final VoidCallback? onSwipePin;
  final bool dense;

  /// Optional chips appended to the bottom row (e.g. reminder bell).
  final List<Widget> trailingChips;

  @override
  Widget build(BuildContext context) {
    final category = CategoryService.instance.resolveSync(item.categoryId);
    final scheme = Theme.of(context).colorScheme;
    final preview = item.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    final timeStr = _formatTime(item.createdAt);
    final isScreenshot = item.imagePath != null;

    final card = Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(DesignTokens.rCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => context.push('/memory/${item.id}'),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _leading(isScreenshot, category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _labelFor(item, category),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (item.pinned) ...[
                          Icon(Icons.push_pin_rounded,
                              size: 12, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (item.rawUrl != null) ...[
                      Text(
                        _shortUrl(item.rawUrl!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    if (item.title != null && item.title!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          item.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (preview.isNotEmpty && preview != '[Screenshot]')
                      Text(
                        isScreenshot ? 'OCR: "$preview"' : preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                          color: scheme.onSurface,
                        ),
                      ),
                    if (_chips().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _chips(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onSwipeArchive == null && onSwipePin == null) return card;
    return Dismissible(
      key: ValueKey('memory_${item.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart &&
            onSwipeArchive != null) {
          onSwipeArchive!();
        } else if (direction == DismissDirection.startToEnd &&
            onSwipePin != null) {
          onSwipePin!();
        }
        return false;
      },
      background: _swipeBg(
        alignment: Alignment.centerLeft,
        color: const Color(0xFFF59E0B),
        icon: item.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        label: item.pinned ? 'Unpin' : 'Pin',
      ),
      secondaryBackground: _swipeBg(
        alignment: Alignment.centerRight,
        color: const Color(0xFF64748B),
        icon: Icons.archive_rounded,
        label: item.archived ? 'Restore' : 'Archive',
      ),
      child: card,
    );
  }

  Widget _leading(bool isScreenshot, CategoryDef category) {
    if (!isScreenshot) return CategoryBadge(def: category);
    final path = item.imagePath!;
    final file = File(path);
    // When the image exists we show a tiny thumbnail; otherwise fall back to
    // the gradient placeholder from the mockup.
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: file.existsSync()
          ? Image.file(
              file,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ThumbBadge(),
            )
          : const ThumbBadge(),
    );
  }

  String _labelFor(MemoryItem m, CategoryDef c) {
    if (m.sourceType == 'photo') return 'Photo';
    if (m.imagePath != null) return 'Screenshot';
    if (m.rawUrl != null && c.builtin == MemoryCategory.link) return 'Link';
    return c.label;
  }

  String _shortUrl(String url) {
    final u = url.replaceFirst(RegExp(r'^https?:\/\/(www\.)?'), '');
    return u.length > 60 ? '${u.substring(0, 57)}…' : u;
  }

  List<Widget> _chips() {
    final chips = <Widget>[];
    final category = CategoryService.instance.resolveSync(item.categoryId);

    // "Read Later" style accent chip — only when the chosen category has a
    // user-facing reading/collection label (watch/read later, shopping,
    // important). Custom categories also get the accent chip so they feel
    // first-class.
    final builtin = category.builtin;
    if (!category.isBuiltin ||
        builtin == MemoryCategory.readLater ||
        builtin == MemoryCategory.watchLater ||
        builtin == MemoryCategory.shopping ||
        builtin == MemoryCategory.important) {
      chips.add(MnemoChip.accent(label: category.label));
    }

    // User tags (skip the category-id that classifier auto-adds).
    for (final tag in item.tags) {
      if (tag == category.id) continue;
      chips.add(MnemoChip(label: '#$tag'));
    }

    // Location chip
    if (item.locationName != null && item.locationName!.isNotEmpty) {
      chips.add(MnemoChip(label: '📍 ${item.locationName!}'));
    }

    // Checklist progress chip
    if (item.checklistMode && item.checklistData.isNotEmpty) {
      try {
        final decoded = jsonDecode(item.checklistData) as List;
        final total = decoded.length;
        final done = decoded
            .where((e) => (e as Map)['checked'] == true)
            .length;
        chips.add(MnemoChip(label: '✓ $done/$total'));
      } catch (_) {}
    }

    chips.addAll(trailingChips);
    return chips;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isSameDay =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    if (isSameDay) return DateFormat('h:mm a').format(dt);
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    if (DateTime(dt.year, dt.month, dt.day) == yesterday) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('MMM d').format(dt);
  }

  Widget _swipeBg({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(DesignTokens.rCard),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
