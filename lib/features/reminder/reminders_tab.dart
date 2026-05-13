import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/category.dart';
import '../../models/reminder.dart';
import '../../services/memory_repository.dart';
import '../../services/reminder_repository.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_label.dart';
import '../shared/providers.dart';

/// Reminders tab. Matches screen #4 of the HTML mockup:
///  - app bar with title + subtitle + "+ new" icon
///  - "Upcoming" timeline (coloured dot + text)
///  - "Past" timeline (faded / strike-through)
class RemindersTab extends ConsumerWidget {
  const RemindersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final activeAsync = ref.watch(activeRemindersProvider);
    final completedAsync = ref.watch(completedRemindersProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AppBar(
              upcoming: activeAsync.maybeWhen(
                data: (list) => list
                    .where((r) => r.remindAt.isAfter(DateTime.now()))
                    .length,
                orElse: () => 0,
              ),
            ),
            Expanded(
              child: _buildBody(
                context,
                activeAsync.asData?.value ?? const [],
                completedAsync.asData?.value ?? const [],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, List<Reminder> active, List<Reminder> done) {
    if (active.isEmpty && done.isEmpty) {
      return EmptyState(
        icon: Icons.alarm_rounded,
        title: 'No reminders yet',
        subtitle:
            'Create one from the + button below, or let Mnemo suggest one '
            'when it spots a promise in your notes.',
        action: FilledButton.icon(
          onPressed: () => context.push('/reminder/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New reminder'),
        ),
      );
    }

    final now = DateTime.now();
    final upcoming = active
        .where((r) => !r.remindAt.isBefore(now))
        .toList(growable: false);
    final overdue = active
        .where((r) => r.remindAt.isBefore(now))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
      children: [
        if (overdue.isNotEmpty) ...[
          const SectionLabel(label: 'Overdue'),
          for (var i = 0; i < overdue.length; i++)
            _TimelineRow(
              reminder: overdue[i],
              isLast: i == overdue.length - 1,
              tone: _Tone.overdue,
            ),
          const SizedBox(height: 4),
        ],
        if (upcoming.isNotEmpty) ...[
          const SectionLabel(label: 'Upcoming'),
          for (var i = 0; i < upcoming.length; i++)
            _TimelineRow(
              reminder: upcoming[i],
              isLast: i == upcoming.length - 1,
              tone: _Tone.upcoming,
            ),
          const SizedBox(height: 4),
        ],
        if (done.isNotEmpty) ...[
          const SectionLabel(label: 'Past'),
          for (var i = 0; i < done.length; i++)
            _TimelineRow(
              reminder: done[i],
              isLast: i == done.length - 1,
              tone: _Tone.past,
            ),
        ],
      ],
    );
  }
}

class _AppBar extends StatelessWidget {
  const _AppBar({required this.upcoming});
  final int upcoming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reminders',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  '$upcoming upcoming',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => context.push('/reminder/new'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              child: Icon(Icons.add_rounded,
                  size: 24, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { upcoming, overdue, past }

class _TimelineRow extends ConsumerWidget {
  const _TimelineRow({
    required this.reminder,
    required this.isLast,
    required this.tone,
  });

  final Reminder reminder;
  final bool isLast;
  final _Tone tone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isPast = tone == _Tone.past;

    final Color dotColor;
    switch (tone) {
      case _Tone.upcoming:
        dotColor = _accentForMemory(ref) ?? scheme.primary;
      case _Tone.overdue:
        dotColor = const Color(0xFFEF4444);
      case _Tone.past:
        dotColor = scheme.surfaceContainerHighest;
    }

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rail (dot + connecting line).
        SizedBox(
          width: 14,
          child: Column(
            children: [
              const SizedBox(height: 4),
              _Dot(color: dotColor, glow: !isPast),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(width: 14),
        // Content.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: isPast
                      ? null
                      : () => context.push('/reminder/edit/${reminder.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatWhen(reminder.remindAt, tone),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: tone == _Tone.overdue
                              ? const Color(0xFFEF4444)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reminder.text,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isPast ? scheme.onSurfaceVariant : scheme.onSurface,
                          decoration: isPast ? TextDecoration.lineThrough : null,
                          decorationColor:
                              scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(ref, tone),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isPast) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        onPressed: () async {
                          await ReminderRepository.instance.complete(reminder);
                        },
                        child: const Text('Done'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          textStyle:
                              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        onPressed: () async {
                          await ReminderRepository.instance.delete(reminder);
                        },
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return row;
  }

  Color? _accentForMemory(WidgetRef ref) {
    final mid = reminder.memoryId;
    if (mid == null) return null;
    // Try to surface the linked memory's category color for visual continuity
    // with the Inbox cards — nice-to-have, not essential.
    final inbox = ref.read(inboxStreamProvider).asData?.value;
    final match = inbox?.where((m) => m.id == mid);
    if (match == null || match.isEmpty) return null;
    return MemoryCategory.fromId(match.first.categoryId).color;
  }

  String _formatWhen(DateTime dt, _Tone tone) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = d.difference(today).inDays;
    final time = DateFormat('h:mm a').format(dt);

    if (tone == _Tone.overdue) {
      if (diff == 0) return 'Today · $time · overdue';
      if (diff == -1) return 'Yesterday · $time · overdue';
      return '${DateFormat('MMM d').format(dt)} · $time · overdue';
    }

    if (diff == 0) return 'Today · $time';
    if (diff == 1) return 'Tomorrow · $time';
    if (diff > 0 && diff < 7) {
      return '${DateFormat('EEEE').format(dt)} · $time';
    }
    return '${DateFormat('EEE, MMM d').format(dt)} · $time';
  }

  String _subtitle(WidgetRef ref, _Tone tone) {
    if (tone == _Tone.past) return '✓ Completed';
    final mid = reminder.memoryId;
    if (mid != null) {
      final inbox = ref.read(inboxStreamProvider).asData?.value;
      final match = inbox?.where((m) => m.id == mid);
      if (match != null && match.isNotEmpty) {
        return 'From ${MemoryCategory.fromId(match.first.categoryId).label.toLowerCase()}';
      }
      return 'Linked memory';
    }
    return 'Created ${_ago(reminder.createdAt)}';
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.glow});
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  spreadRadius: 3,
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Keep the import side-effect-free — these are used elsewhere and we need
/// them for the analyzer.
// ignore: unused_element
void _keepAnalyzerHappy() {
  MemoryRepository.instance;
}
