import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/theme/design_tokens.dart';
import '../models/memory_item.dart';
import '../models/reminder.dart';
import '../services/category_service.dart';
import 'mnemo_chip.dart';

/// Amber-gradient pinned memory card from the mockup.
class PinnedCard extends StatelessWidget {
  const PinnedCard({
    super.key,
    required this.item,
    this.reminder,
  });

  final MemoryItem item;
  final Reminder? reminder;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;

    final gradient = isLight
        ? DesignTokens.pinnedGradientLight
        : DesignTokens.pinnedGradientDark;
    final textColor = isLight
        ? DesignTokens.pinnedTextLight
        : DesignTokens.pinnedTextDark;
    final labelColor = isLight
        ? DesignTokens.pinnedLabelLight
        : DesignTokens.pinnedLabelDark;

    final category = CategoryService.instance.resolveSync(item.categoryId);
    final timeStr = _formatRelative(item.createdAt);

    return InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.rCard),
      onTap: () => context.push('/memory/${item.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(DesignTokens.rCard),
          border: Border.all(
            color: isLight
                ? DesignTokens.pinnedBorderLight
                : DesignTokens.pinnedBorderDark,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(category.icon, size: 16, color: labelColor),
                const SizedBox(width: 6),
                Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: labelColor,
                  ),
                ),
                const Spacer(),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.content.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
                height: 1.35,
              ),
            ),
            if (item.tags.isNotEmpty || reminder != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in item.tags.take(3))
                    _amberTag('#$t', labelColor),
                  if (reminder != null)
                    MnemoChip.bell(label: _formatReminder(reminder!.remindAt)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _amberTag(String label, Color labelColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: labelColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.rChip),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: labelColor,
        ),
      ),
    );
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  String _formatReminder(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = day.difference(today).inDays;
    final hm = DateFormat('H:mm').format(dt);
    if (diff == 0) return 'Today $hm';
    if (diff == 1) return 'Tomorrow $hm';
    if (diff > 1 && diff < 7) return '${DateFormat('EEE').format(dt)} $hm';
    return '${DateFormat('MMM d').format(dt)} $hm';
  }
}
