import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/category.dart';
import '../models/memory_item.dart';
import '../services/category_service.dart';
import '../services/memory_repository.dart';
import '../services/share_out_service.dart';

/// Shows a bottom sheet with all available actions for a memory item.
/// Reusable from inbox, category detail, search results, etc.
void showMemoryActionsSheet(BuildContext context, MemoryItem m) {
  final category = CategoryService.instance.resolveSync(m.categoryId);

  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(category.icon, size: 18, color: category.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.title ?? m.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: const Text('Open'),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/memory/${m.id}');
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Edit'),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/save', extra: {'editMemoryId': m.id});
            },
          ),
          ListTile(
            leading: const Icon(Icons.category_rounded),
            title: const Text('Change category'),
            onTap: () {
              Navigator.pop(ctx);
              _showCategoryPicker(context, m);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share'),
            onTap: () {
              Navigator.pop(ctx);
              ShareOutService.instance.shareMemory(m);
            },
          ),
          ListTile(
            leading: Icon(
              m.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
            ),
            title: Text(m.pinned ? 'Unpin' : 'Pin'),
            onTap: () {
              Navigator.pop(ctx);
              MemoryRepository.instance.togglePinned(m);
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_rounded),
            title: Text(m.archived ? 'Restore from archive' : 'Archive'),
            onTap: () {
              Navigator.pop(ctx);
              MemoryRepository.instance.toggleArchived(m);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(ctx).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Delete this memory?'),
                  content: const Text(
                    'This also removes any linked reminders.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await MemoryRepository.instance.delete(m);
              }
            },
          ),
        ],
      ),
    ),
  );
}

void _showCategoryPicker(BuildContext context, MemoryItem m) async {
  final categories = await CategoryService.instance.loadAllBrowsable();
  if (!context.mounted) return;
  final picked = await showModalBottomSheet<CategoryDef>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Change category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  InkWell(
                    onTap: () => Navigator.of(ctx).pop(c),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.id == m.categoryId
                            ? c.color.withValues(alpha: 0.22)
                            : Theme.of(ctx).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: c.id == m.categoryId
                              ? c.color
                              : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon, size: 16, color: c.color),
                          const SizedBox(width: 6),
                          Text(
                            c.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.id == m.categoryId
                                  ? c.color
                                  : Theme.of(ctx).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || picked.id == m.categoryId) return;
  m.categoryId = picked.id;
  await MemoryRepository.instance.update(m);
}
