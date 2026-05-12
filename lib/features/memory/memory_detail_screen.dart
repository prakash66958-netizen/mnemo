import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/category.dart';
import '../../core/theme/design_tokens.dart';
import '../../models/memory_item.dart';
import '../../models/reminder.dart';
import '../../services/category_service.dart';
import '../../services/memory_repository.dart';
import '../../services/reminder_repository.dart';
import '../../services/share_out_service.dart';
import '../../widgets/mnemo_chip.dart';
import '../shared/providers.dart';

/// Memory detail. Matches screen #5 of the HTML mockup:
///  - category pill at the top
///  - large body text
///  - tag chips
///  - meta rows (captured from, created, reminder, category)
///  - two-button CTA (Edit reminder / Mark done)
class MemoryDetailScreen extends ConsumerWidget {
  const MemoryDetailScreen({super.key, required this.memoryId});

  final int memoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final inboxAsync = ref.watch(inboxStreamProvider);
    final remindersAsync = ref.watch(activeRemindersProvider);
    final archivedAsync = ref.watch(archivedStreamProvider);

    final inbox = inboxAsync.asData?.value ?? const <MemoryItem>[];
    final archived = archivedAsync.asData?.value ?? const <MemoryItem>[];
    final all = [...inbox, ...archived];
    MemoryItem? item;
    for (final m in all) {
      if (m.id == memoryId) {
        item = m;
        break;
      }
    }

    if (item == null) {
      return const _NotFound();
    }

    final category = CategoryService.instance.resolveSync(item.categoryId);
    final reminders = remindersAsync.asData?.value ?? const <Reminder>[];
    Reminder? linkedReminder;
    for (final r in reminders) {
      if (r.memoryId == memoryId) {
        linkedReminder = r;
        break;
      }
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _DetailAppBar(
              item: item,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Row(
                    children: [
                      _CategoryPill(category: category),
                    ],
                  ),
                  if (item.imagePath != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(DesignTokens.rCard),
                      child: Image.file(
                        File(item.imagePath!),
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          height: 140,
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (item.title != null && item.title!.trim().isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        item.title!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                  SelectableText(
                    item.content,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      letterSpacing: -0.2,
                    ),
                    contextMenuBuilder: (ctx, state) =>
                        AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: state.contextMenuAnchors,
                      buttonItems: [
                        ...state.contextMenuButtonItems,
                        ContextMenuButtonItem(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: item!.content));
                            if (ctx.mounted) {
                              ContextMenuController.removeAny();
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied all text'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          label: 'Copy all',
                        ),
                      ],
                    ),
                  ),
                  // For screenshot/OCR memories, surface a dedicated "Copy
                  // text" button so the user doesn't have to long-press-select
                  // a possibly-long OCR result.
                  if (item.imagePath != null &&
                      item.content.trim().isNotEmpty &&
                      item.content.trim() != '[Screenshot]') ...[
                    const SizedBox(height: 10),
                    _CopyTextButton(text: item.content),
                  ],
                  if (item.rawUrl != null) ...[
                    const SizedBox(height: 8),
                    _OpenLinkRow(url: item.rawUrl!),
                  ],
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in item.tags)
                          if (t != category.id)
                            MnemoChip.accent(label: '#$t'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  _MetaRows(
                    item: item,
                    reminder: linkedReminder,
                    category: category,
                  ),
                  const SizedBox(height: 18),
                  _CTARow(item: item, reminder: linkedReminder),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar({required this.item, required this.onBack});
  final MemoryItem item;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              child: Icon(Icons.arrow_back_rounded,
                  size: 22, color: scheme.onSurface),
            ),
          ),
          const Spacer(),
          _AppBarIcon(
            icon: item.pinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            onTap: () => MemoryRepository.instance.togglePinned(item),
          ),
          _AppBarIcon(
            icon: Icons.share_outlined,
            onTap: () => ShareOutService.instance.shareMemory(item),
          ),
          _AppBarIcon(
            icon: Icons.alarm_add_rounded,
            onTap: () => context.push('/reminder/new', extra: {
              'memoryId': item.id,
              'text': item.content,
            }),
          ),
          _AppBarIcon(
            icon: Icons.more_horiz_rounded,
            onTap: () => _showMore(context, item),
          ),
        ],
      ),
    );
  }

  void _showMore(BuildContext context, MemoryItem m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                context.push('/save', extra: {
                  'editMemoryId': m.id,
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.category_rounded),
              title: const Text('Change category'),
              onTap: () {
                Navigator.pop(context);
                _showCategoryPicker(context, m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_rounded),
              title: Text(m.archived ? 'Restore' : 'Archive'),
              onTap: () {
                Navigator.pop(context);
                MemoryRepository.instance.toggleArchived(m);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(context);
                await MemoryRepository.instance.delete(m);
                if (context.mounted) context.pop();
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
                              : Theme.of(ctx)
                                  .colorScheme
                                  .surfaceContainer,
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
                                    : Theme.of(ctx)
                                        .colorScheme
                                        .onSurface,
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
}

class _AppBarIcon extends StatelessWidget {
  const _AppBarIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        child: Icon(icon, size: 22, color: scheme.onSurface),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category});
  final CategoryDef category;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bg = DesignTokens.chipTint(category.color, brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 14, color: category.color),
          const SizedBox(width: 6),
          Text(
            category.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: category.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRows extends StatelessWidget {
  const _MetaRows({
    required this.item,
    required this.reminder,
    required this.category,
  });

  final MemoryItem item;
  final Reminder? reminder;
  final CategoryDef category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <_MetaRow>[
      _MetaRow('Captured from', _sourceLabel(item.sourceType)),
      _MetaRow('Created',
          DateFormat('MMM d, y · h:mm a').format(item.createdAt)),
      if (reminder != null)
        _MetaRow('Reminder',
            DateFormat('EEE MMM d · h:mm a').format(reminder!.remindAt),
            valueColor: const Color(0xFFEF4444)),
      _MetaRow('Category',
          '${category.label}${item.hasPromise ? " (auto)" : ""}'),
      if (item.pinned) const _MetaRow('Pinned', 'Yes'),
      if (item.archived) const _MetaRow('Archived', 'Yes'),
    ];

    return Column(
      children: [
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                  width: 0.6,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  r.k,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  r.v,
                  style: TextStyle(
                    fontSize: 13,
                    color: r.valueColor ?? scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _sourceLabel(String raw) {
    switch (raw) {
      case 'text':
        return 'Manual · Text';
      case 'link':
        return 'Manual · Link';
      case 'clipboard':
        return 'Clipboard';
      case 'share':
        return 'Share sheet';
      case 'screenshot':
        return 'Screenshot';
      case 'photo':
        return 'Photo';
      default:
        return raw;
    }
  }
}

class _MetaRow {
  const _MetaRow(this.k, this.v, {this.valueColor});
  final String k;
  final String v;
  final Color? valueColor;
}

class _CTARow extends StatelessWidget {
  const _CTARow({required this.item, required this.reminder});
  final MemoryItem item;
  final Reminder? reminder;

  @override
  Widget build(BuildContext context) {
    final hasReminder = reminder != null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              if (hasReminder) {
                context.push('/reminder/edit/${reminder!.id}');
              } else {
                context.push('/reminder/new', extra: {
                  'memoryId': item.id,
                  'text': item.content,
                });
              }
            },
            child:
                Text(hasReminder ? 'Edit reminder' : 'Add reminder'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: () async {
              if (hasReminder) {
                await ReminderRepository.instance.complete(reminder!);
              } else {
                await MemoryRepository.instance.toggleArchived(item);
              }
              if (context.mounted) context.pop();
            },
            child: Text(hasReminder ? 'Mark done' : 'Archive'),
          ),
        ),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory')),
      body: const Center(child: Text('This memory is no longer available.')),
    );
  }
}

/// Tappable "open link" row. Uses [url_launcher] to hand off to the user's
/// default browser / app for the URL scheme. Falls back to copying when no
/// handler is available.
class _OpenLinkRow extends StatelessWidget {
  const _OpenLinkRow({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        onLongPress: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.link_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded,
                  size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final uri = _parse(url);
    if (uri == null) {
      _notify(context, 'Invalid link');
      return;
    }
    final canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      // Fall back to copying so the user still has a way forward.
      if (!context.mounted) return;
      await _copy(context, silent: true);
      if (!context.mounted) return;
      _notify(context, 'No app to open link · copied');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _notify(context, "Couldn't open link");
    } catch (_) {
      if (context.mounted) _notify(context, "Couldn't open link");
    }
  }

  Future<void> _copy(BuildContext context, {bool silent = false}) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (silent || !context.mounted) return;
    _notify(context, 'Link copied');
  }

  /// Allowed URL schemes for outbound taps. Anything else (including the
  /// dangerous `intent:`, `javascript:`, `file:`, `content:`, `data:`) is
  /// rejected — a malicious share could otherwise hand the user a crafted
  /// `intent://…#Intent;…end` URL that launches arbitrary activities.
  static const _safeSchemes = {'http', 'https', 'mailto', 'tel', 'sms'};

  Uri? _parse(String raw) {
    var s = raw.trim();
    // Users often save links without a scheme ("example.com/foo"); add one
    // so url_launcher doesn't reject them.
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*:').hasMatch(s)) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !_safeSchemes.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri;
  }

  void _notify(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}

/// Tappable "Copy text" row shown under screenshot/OCR memories.
class _CopyTextButton extends StatelessWidget {
  const _CopyTextButton({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied scanned text'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.content_copy_rounded,
                  size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Copy scanned text',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
