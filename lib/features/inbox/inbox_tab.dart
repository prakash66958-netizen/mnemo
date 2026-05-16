import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/category.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/design_tokens.dart';
import '../../models/memory_item.dart';
import '../../models/reminder.dart';
import '../../services/category_service.dart';
import '../../services/memory_repository.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/memory_card.dart';
import '../../widgets/memory_actions_sheet.dart';
import '../../widgets/mnemo_chip.dart';
import '../../widgets/pinned_card.dart';
import '../../widgets/section_label.dart';
import '../shared/providers.dart';

/// Inbox screen. Matches screen #1 of the HTML mockup.
class InboxTab extends ConsumerWidget {
  const InboxTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(inboxStreamProvider);
    final archivedAsync = ref.watch(archivedStreamProvider);
    final remindersAsync = ref.watch(activeRemindersProvider);
    final filter = ref.watch(inboxFilterProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AppBar(
              remindersCount: remindersAsync.maybeWhen(
                data: (v) => v.length,
                orElse: () => 0,
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Failed to load: $e')),
                data: (items) {
                  final archived =
                      archivedAsync.asData?.value ?? const <MemoryItem>[];
                  final reminders =
                      remindersAsync.asData?.value ?? const <Reminder>[];

                  // Auto-delete items that have been done long enough
                  final deleteAfterMinutes = ref.read(inboxDeleteAfterHoursProvider);
                  if (deleteAfterMinutes > 0) {
                    final cutoff = DateTime.now().subtract(Duration(minutes: deleteAfterMinutes));
                    for (final item in items) {
                      if (item.doneInInbox && item.doneAt != null && item.doneAt!.isBefore(cutoff)) {
                        MemoryRepository.instance.delete(item);
                      }
                    }
                  }

                  return _InboxBody(
                    items: items,
                    archived: archived,
                    reminders: reminders,
                    filter: filter,
                    onFilterChanged: (f) =>
                        ref.read(inboxFilterProvider.notifier).state = f,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar({required this.remindersCount});

  final int remindersCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, color: scheme.primary, size: 24),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  AppConstants.appTagline,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _IconBtn(
            icon: Icons.search_rounded,
            onTap: () => _openSearch(context),
          ),
          _IconBtn(
            icon: Icons.tune_rounded,
            badge: remindersCount > 0 ? '$remindersCount' : null,
            onTap: () => _openFilter(context),
          ),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    showSearch<MemoryItem?>(
      context: context,
      delegate: _InboxSearchDelegate(),
    );
  }

  void _openFilter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _FilterSheet(),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.badge});
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

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
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 22, color: scheme.onSurface),
            if (badge != null)
              Positioned(
                top: -2,
                right: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InboxBody extends StatelessWidget {
  const _InboxBody({
    required this.items,
    required this.archived,
    required this.reminders,
    required this.filter,
    required this.onFilterChanged,
  });

  final List<MemoryItem> items;
  final List<MemoryItem> archived;
  final List<Reminder> reminders;
  final InboxFilter filter;
  final ValueChanged<InboxFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    List<MemoryItem> filtered;
    switch (filter) {
      case InboxFilter.all:
        filtered = items;
      case InboxFilter.today:
        filtered = items
            .where((m) => !m.createdAt.isBefore(today))
            .toList(growable: false);
      case InboxFilter.pinned:
        filtered = items.where((m) => m.pinned).toList(growable: false);
      case InboxFilter.archive:
        filtered = archived;
    }

    final pinned = filtered.where((m) => m.pinned).toList();
    final rest = filtered.where((m) => !m.pinned).toList();

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _InlineFilterRow(
              filter: filter,
              onChanged: onFilterChanged,
            ),
            const Expanded(
              child: EmptyState(
                icon: Icons.inbox_rounded,
                title: 'Your inbox is empty',
                subtitle:
                    'Tap + below to capture a note or link. You '
                    'can also share anything from another app into Mnemo.',
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _InlineFilterRow(
          filter: filter,
          onChanged: onFilterChanged,
        ),
        if (pinned.isNotEmpty && filter != InboxFilter.pinned) ...[
          const SectionLabel(
              label: 'Pinned', icon: Icons.push_pin_rounded),
          for (final m in pinned)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PinnedCard(
                item: m,
                reminder: _reminderFor(m),
              ),
            ),
        ],
        ..._groupedCards(rest, filter == InboxFilter.pinned
            ? pinned
            : const <MemoryItem>[]),
      ],
    );
  }

  Iterable<Widget> _groupedCards(
    List<MemoryItem> rest,
    List<MemoryItem> pinnedSection,
  ) sync* {
    // When the Pinned segment is active, show all pinned as regular cards
    // (no amber gradient), since the whole tab is already "pinned".
    final all = [...pinnedSection, ...rest];

    // Sort so that within each day group, unchecked items float to the top
    // and checked (done) items sink to the bottom. Between groups the
    // existing newest-first order is preserved.
    all.sort((a, b) {
      final keyA = _dayKey(a.createdAt);
      final keyB = _dayKey(b.createdAt);
      // Different day groups — keep original newest-first order.
      if (keyA != keyB) return keyB.compareTo(keyA);
      // Same day group — done items go after undone items.
      final doneA = a.doneInInbox ? 1 : 0;
      final doneB = b.doneInInbox ? 1 : 0;
      if (doneA != doneB) return doneA.compareTo(doneB);
      // Within the same done-state, keep newest first.
      return b.createdAt.compareTo(a.createdAt);
    });

    String? lastKey;
    for (final m in all) {
      final key = _dayKey(m.createdAt);
      if (key != lastKey) {
        yield SectionLabel(label: _dayLabel(m.createdAt));
        lastKey = key;
      }
      yield Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _SwipeableCard(
          item: m,
          reminder: _reminderFor(m),
        ),
      );
    }
  }

  Reminder? _reminderFor(MemoryItem m) {
    try {
      return reminders.firstWhere((r) => r.memoryId == m.id);
    } catch (_) {
      return null;
    }
  }

  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('MMM d, y').format(dt);
  }
}

class _SwipeableCard extends ConsumerStatefulWidget {
  const _SwipeableCard({required this.item, this.reminder});
  final MemoryItem item;
  final Reminder? reminder;

  @override
  ConsumerState<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends ConsumerState<_SwipeableCard> {
  @override
  Widget build(BuildContext context) {
    final deleteAfterMinutes = ref.watch(inboxDeleteAfterHoursProvider);
    final checkboxEnabled = ref.watch(inboxCheckboxEnabledProvider);
    final trailing = <Widget>[];
    if (widget.reminder != null) {
      trailing.add(MnemoChip.bell(label: _reminderLabel(widget.reminder!.remindAt)));
    }

    // Show a location chip if the item has a location
    if (widget.item.locationName != null && widget.item.locationName!.isNotEmpty) {
      trailing.add(MnemoChip(label: '📍 ${widget.item.locationName!}'));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Checkbox — only shown when enabled in settings
        if (checkboxEnabled) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, right: 4),
            child: GestureDetector(
              onTap: () => _toggleDone(deleteAfterMinutes),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.item.doneInInbox
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: widget.item.doneInInbox
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
                child: widget.item.doneInInbox
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Opacity(
            opacity: (checkboxEnabled && widget.item.doneInInbox) ? 0.5 : 1.0,
            child: MemoryCard(
              item: widget.item,
              trailingChips: trailing,
              onSwipeArchive: () async {
                await MemoryRepository.instance.toggleArchived(widget.item);
                showAppToast(widget.item.archived ? 'Restored' : 'Archived');
              },
              onSwipePin: () => MemoryRepository.instance.togglePinned(widget.item),
              onLongPress: () => showMemoryActionsSheet(context, widget.item),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleDone(int deleteAfterMinutes) async {
    final item = widget.item;
    item.doneInInbox = !item.doneInInbox;
    item.doneAt = item.doneInInbox ? DateTime.now() : null;
    await MemoryRepository.instance.update(item);

    if (item.doneInInbox && deleteAfterMinutes > 0) {
      // Schedule auto-delete
      Future.delayed(Duration(minutes: deleteAfterMinutes), () async {
        final fresh = await MemoryRepository.instance.getById(item.id);
        if (fresh != null && fresh.doneInInbox) {
          await MemoryRepository.instance.delete(fresh);
        }
      });

      final label = _durationLabel(deleteAfterMinutes);

      // Use the centered overlay toast (never gets stuck above the nav bar)
      showAppToast(
        'Done · deletes in $label',
        actionLabel: 'Undo',
        onAction: () async {
          item.doneInInbox = false;
          item.doneAt = null;
          await MemoryRepository.instance.update(item);
        },
      );
    } else if (item.doneInInbox) {
      // deleteAfterMinutes == 0 (Never) — just confirm it's marked done
      showAppToast(
        'Marked done',
        actionLabel: 'Undo',
        onAction: () async {
          item.doneInInbox = false;
          item.doneAt = null;
          await MemoryRepository.instance.update(item);
        },
      );
    }
  }

  static String _durationLabel(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    if (hours < 24) return hours == 1 ? '1 hour' : '$hours hours';
    final days = hours ~/ 24;
    return days == 1 ? '1 day' : '$days days';
  }

  String _reminderLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = d.difference(today).inDays;
    final hm = DateFormat('h:mm a').format(dt);
    if (diff == 0) return 'Today $hm';
    if (diff == 1) return 'Tomorrow $hm';
    if (diff > 1 && diff < 7) return '${DateFormat('EEE').format(dt)} $hm';
    return '${DateFormat('MMM d').format(dt)} $hm';
  }
}

/// Enhanced filter sheet with quick filters, date range, and category.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  List<CategoryDef> _categories = [];
  String? _selectedCategoryId;
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final list = await CategoryService.instance.loadAllBrowsable();
    if (mounted) setState(() => _categories = list);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(inboxFilterProvider);
    final scheme = Theme.of(context).colorScheme;
    const quickChips = [InboxFilter.today, InboxFilter.pinned, InboxFilter.archive];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Filter',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            // Quick filters
            Text('QUICK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final f in quickChips)
                  ChoiceChip(
                    selected: filter == f,
                    label: Text(_label(f)),
                    onSelected: (_) {
                      ref.read(inboxFilterProvider.notifier).state =
                          filter == f ? InboxFilter.all : f;
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Date range
            Text('DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: now,
                  initialDateRange: _dateRange,
                );
                if (picked != null) setState(() => _dateRange = picked);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.date_range_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      _dateRange == null
                          ? 'All time'
                          : '${DateFormat('MMM d').format(_dateRange!.start)} – ${DateFormat('MMM d').format(_dateRange!.end)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_dateRange != null)
                      GestureDetector(
                        onTap: () => setState(() => _dateRange = null),
                        child: Icon(Icons.close_rounded, size: 18, color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Category filter
            Text('CATEGORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return ChoiceChip(
                      selected: _selectedCategoryId == null,
                      label: const Text('All'),
                      onSelected: (_) => setState(() => _selectedCategoryId = null),
                    );
                  }
                  final c = _categories[i - 1];
                  final active = _selectedCategoryId == c.id;
                  return ChoiceChip(
                    selected: active,
                    avatar: Icon(c.icon, size: 14, color: c.color),
                    label: Text(c.label),
                    onSelected: (_) => setState(() => _selectedCategoryId = active ? null : c.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  ref.read(inboxAdvancedFilterProvider.notifier).state = AdvancedFilter(
                    categoryId: _selectedCategoryId,
                    dateRange: _dateRange,
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('Apply filters'),
              ),
            ),
            if (ref.watch(inboxAdvancedFilterProvider).isActive) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    ref.read(inboxAdvancedFilterProvider.notifier).state = const AdvancedFilter();
                    ref.read(inboxFilterProvider.notifier).state = InboxFilter.all;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Clear all filters'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _label(InboxFilter f) {
    switch (f) {
      case InboxFilter.all: return 'All';
      case InboxFilter.today: return 'Today';
      case InboxFilter.pinned: return 'Pinned';
      case InboxFilter.archive: return 'Archive';
    }
  }
}

/// Inline filter chips for the inbox. Only Today / Pinned / Archive are shown
/// as explicit chips — "All" is the default state (no chip highlighted). Tapping
/// the already-active chip deselects it, returning to All. This avoids the
/// confusing "All is always selected" look.
class _InlineFilterRow extends StatelessWidget {
  const _InlineFilterRow({
    required this.filter,
    required this.onChanged,
  });

  final InboxFilter filter;
  final ValueChanged<InboxFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    // Only show the non-All filters as chips.
    const chips = [InboxFilter.today, InboxFilter.pinned, InboxFilter.archive];
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            for (final f in chips) ...[
              _FilterChip(
                label: _label(f),
                active: filter == f,
                onTap: () {
                  // Tapping the active chip deselects → back to All.
                  onChanged(filter == f ? InboxFilter.all : f);
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  String _label(InboxFilter f) {
    switch (f) {
      case InboxFilter.all:
        return 'All';
      case InboxFilter.today:
        return 'Today';
      case InboxFilter.pinned:
        return 'Pinned';
      case InboxFilter.archive:
        return 'Archive';
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Simple search delegate wired into the Inbox app-bar search icon.
class _InboxSearchDelegate extends SearchDelegate<MemoryItem?> {
  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear_rounded),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Search your memories',
        subtitle: 'Type any word, tag or phrase. Search runs entirely on-device.',
      );
    }
    return FutureBuilder<List<MemoryItem>>(
      future: MemoryRepository.instance.search(query),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snap.data!;
        if (results.isEmpty) {
          return EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            subtitle: 'Nothing matches "$query".',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenPadH, 8, DesignTokens.screenPadH, 24),
          itemCount: results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => MemoryCard(item: results[i]),
        );
      },
    );
  }
}
