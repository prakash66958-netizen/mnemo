import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../services/habit_repository.dart';
import '../../widgets/empty_state.dart';
import '../shared/providers.dart';
import 'habit_editor_sheet.dart';

/// Main habits screen — shows today's habits with completion toggles.
class HabitsTab extends ConsumerWidget {
  const HabitsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitListProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Habits',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, MMM d').format(DateTime.now()),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: habitsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (habits) {
                  if (habits.isEmpty) {
                    return EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'No habits yet',
                      subtitle:
                          'Track daily habits like exercise, reading, or '
                          'drinking water. Tap + to create your first one.',
                      action: FilledButton.icon(
                        onPressed: () => _openEditor(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New habit'),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: habits.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _HabitCard(habit: habits[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New habit'),
      ),
    );
  }

  void _openEditor(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const HabitEditorSheet(),
    );
  }
}

class _HabitCard extends StatefulWidget {
  const _HabitCard({required this.habit});
  final Habit habit;

  @override
  State<_HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<_HabitCard> {
  bool _done = false;
  int _streak = 0;
  List<bool> _week = List.filled(7, false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _HabitCard old) {
    super.didUpdateWidget(old);
    if (old.habit.id != widget.habit.id) _load();
  }

  Future<void> _load() async {
    final done = await HabitRepository.instance.isCompletedToday(widget.habit.id);
    final streak = await HabitRepository.instance.currentStreak(widget.habit.id);
    final week = await HabitRepository.instance.last7Days(widget.habit.id);
    if (!mounted) return;
    setState(() {
      _done = done;
      _streak = streak;
      _week = week;
    });
  }

  Future<void> _toggle() async {
    await HabitRepository.instance.toggleToday(widget.habit);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    final color = Color(h.colorValue);
    final scheme = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(
      color.withValues(alpha: 0.10),
      scheme.surfaceContainerHigh,
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          child: Row(
            children: [
              // Checkbox
              GestureDetector(
                onTap: _toggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _done ? color : Colors.transparent,
                    border: Border.all(
                      color: color,
                      width: 2.5,
                    ),
                  ),
                  child: _done
                      ? const Icon(Icons.check_rounded,
                          size: 20, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              // Name + streak
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${h.emoji ?? ''} ${h.name}'.trim(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _streak > 0
                          ? '🔥 $_streak day streak'
                          : (h.remindHour != null
                              ? 'Every day at ${_fmtTime(h.remindHour!, h.remindMinute ?? 0)}'
                              : 'No reminder'),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // 7-day strip
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final d in _week)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d ? color : Colors.transparent,
                        border: Border.all(
                          color: d ? color : scheme.outlineVariant,
                          width: 1.2,
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
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HabitDetailSheet(habit: widget.habit),
    );
  }

  String _fmtTime(int h, int m) {
    final t = TimeOfDay(hour: h, minute: m);
    final hr = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mn = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hr:$mn $ap';
  }
}

class _HabitDetailSheet extends StatelessWidget {
  const _HabitDetailSheet({required this.habit});
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final color = Color(habit.colorValue);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${habit.emoji ?? '✅'} ${habit.name}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<int>(
              future: HabitRepository.instance.currentStreak(habit.id),
              builder: (_, snap) => Text(
                '🔥 ${snap.data ?? 0} day streak',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => HabitEditorSheet(existing: habit),
                      );
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () async {
                      Navigator.pop(context);
                      await HabitRepository.instance.delete(habit);
                    },
                    style: FilledButton.styleFrom(
                      foregroundColor: scheme.error,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
