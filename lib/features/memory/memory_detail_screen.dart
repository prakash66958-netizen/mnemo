import 'dart:convert';
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
import 'link_picker_sheet.dart';

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
                  // Body content. For checklist-mode memories we render
                  // the interactive checklist instead of the comma-joined
                  // summary stored in `item.content` (Req 4.2).
                  if (!item.checklistMode) ...[
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
                  ] else ...[
                    // Checklist display
                    if (item.checklistData.isNotEmpty) ...[
                      _ChecklistView(item: item),
                    ],
                  ],
                  // Location display
                  if (item.locationName != null &&
                      item.locationName!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _LocationRow(
                      name: item.locationName!,
                      url: item.locationUrl,
                    ),
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
                  // Linked entries section
                  _LinkedEntriesSection(item: item),
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

/// Interactive checklist view shown in the detail screen.
/// Users can check/uncheck items directly here.
class _ChecklistView extends StatefulWidget {
  const _ChecklistView({required this.item});
  final MemoryItem item;

  @override
  State<_ChecklistView> createState() => _ChecklistViewState();
}

class _ChecklistViewState extends State<_ChecklistView> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final decoded = jsonDecode(widget.item.checklistData) as List;
      _items = decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      _items = [];
    }
  }

  Future<void> _toggle(int index) async {
    setState(() {
      _items[index]['checked'] = !(_items[index]['checked'] as bool? ?? false);
    });
    widget.item.checklistData = jsonEncode(_items);
    await MemoryRepository.instance.update(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHECKLIST',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: GestureDetector(
                onTap: () => _toggle(i),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_items[i]['checked'] as bool? ?? false)
                            ? scheme.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: (_items[i]['checked'] as bool? ?? false)
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: (_items[i]['checked'] as bool? ?? false)
                          ? const Icon(Icons.check_rounded,
                              size: 13, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _items[i]['text'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          decoration: (_items[i]['checked'] as bool? ?? false)
                              ? TextDecoration.lineThrough
                              : null,
                          color: (_items[i]['checked'] as bool? ?? false)
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows linked entries and lets the user add/remove links.
class _LinkedEntriesSection extends StatefulWidget {
  const _LinkedEntriesSection({required this.item});
  final MemoryItem item;

  @override
  State<_LinkedEntriesSection> createState() => _LinkedEntriesSectionState();
}

class _LinkedEntriesSectionState extends State<_LinkedEntriesSection> {
  List<MemoryItem> _linked = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await MemoryRepository.instance.getLinked(widget.item);
    if (!mounted) return;
    setState(() {
      _linked = items;
      _loading = false;
    });
  }

  Future<void> _addLink(BuildContext context) async {
    final result = await showModalBottomSheet<LinkPickerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LinkPickerSheet(
        excludeId: widget.item.id,
        alreadyLinked: widget.item.linkedIds,
      ),
    );
    if (result == null) return;
    switch (result) {
      case LinkPickerExisting(:final item):
        await MemoryRepository.instance.linkEntries(widget.item, item);
      case LinkPickerCreateNew(:final title):
        // Persist a stub Memory so we have an id to link to. The empty
        // body matches the design contract for inline-created links.
        final stub = await MemoryRepository.instance.createTextMemory(
          title: title,
          content: '',
        );
        await MemoryRepository.instance.linkEntries(widget.item, stub);
    }
    _load();
  }

  Future<void> _removeLink(MemoryItem other) async {
    await MemoryRepository.instance.unlinkEntries(widget.item, other);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RELATED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => _addLink(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_link_rounded,
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Link entry',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_linked.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Text(
              'No linked entries yet. Tap "Link entry" to connect related memories.',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          )
        else
          for (final linked in _linked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LinkedCard(
                item: linked,
                onRemove: () => _removeLink(linked),
              ),
            ),
      ],
    );
  }
}

class _LinkedCard extends StatelessWidget {
  const _LinkedCard({required this.item, required this.onRemove});
  final MemoryItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/memory/${item.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.link_rounded,
                  size: 16, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.title != null && item.title!.isNotEmpty)
                      Text(
                        item.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      item.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.link_off_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
                onPressed: onRemove,
                tooltip: 'Remove link',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tappable location row that opens Google Maps.
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.name, this.url});
  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: url != null ? () => _openMaps(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.location_on_rounded,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (url != null)
                      Text(
                        'Tap to open in Google Maps',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              if (url != null)
                Icon(Icons.open_in_new_rounded,
                    size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMaps(BuildContext context) async {
    final uri = Uri.tryParse(url!);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Maps')),
        );
      }
    }
  }
}
