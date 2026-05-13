import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../services/habit_repository.dart';
import '../../widgets/empty_state.dart';
import '../shared/providers.dart';
import 'habit_editor_sheet.dart';
import 'habit_stats_screen.dart';

/// Main habits screen — shows today's habits with completion toggles,
/// a weekly review banner, and per-habit numeric goal progress.
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
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    children: [
                      // ── Feature 5: Weekly review banner ──────────────
                      _WeeklyReviewBanner(habitIds: habits.map((h) => h.id).toList()),
                      const SizedBox(height: 12),
                      // ── Habit cards ───────────────────────────────────
                      ...List.generate(
                        habits.length,
                        (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _HabitCard(habit: habits[i]),
                        ),
                      ),
                    ],
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

// ── Feature 5: Weekly Review Banner ──────────────────────────────────────────

class _WeeklyReviewBanner extends StatefulWidget {
  const _WeeklyReviewBanner({required this.habitIds});
  final List<int> habitIds;

  @override
  State<_WeeklyReviewBanner> createState() => _WeeklyReviewBannerState();
}

class _WeeklyReviewBannerState extends State<_WeeklyReviewBanner> {
  int _completed = 0;
  int _total = 0;
  List<int> _dailyCounts = List.filled(7, 0);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _WeeklyReviewBanner old) {
    super.didUpdateWidget(old);
    if (old.habitIds.length != widget.habitIds.length) _load();
  }

  Future<void> _load() async {
    final result =
        await HabitRepository.instance.weeklySummary(widget.habitIds);
    if (!mounted) return;
    setState(() {
      _completed = result.completed;
      _total = result.total;
      _dailyCounts = result.dailyCounts;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _total == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final rate = _total > 0 ? _completed / _total : 0.0;
    final pct = (rate * 100).round();

    // Motivational message based on rate.
    final String message;
    if (pct >= 90) {
      message = 'Incredible week — you\'re on fire! 🔥';
    } else if (pct >= 70) {
      message = 'Great progress this week! Keep it up 💪';
    } else if (pct >= 50) {
      message = 'Solid effort — push a little harder 🎯';
    } else if (pct > 0) {
      message = 'Every check-in counts. You\'ve got this 🌱';
    } else {
      message = 'Start your week strong — check off a habit!';
    }

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                'This week',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              Text(
                '$_completed / $_total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '($pct%)',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Day-by-day bar chart.
          Row(
            children: List.generate(7, (i) {
              final day = weekStart.add(Duration(days: i));
              final isFuture = day.isAfter(now);
              final isToday = DateUtils.isSameDay(day, now);
              final count = _dailyCounts[i];
              final maxCount =
                  widget.habitIds.isEmpty ? 1 : widget.habitIds.length;
              final barFill = isFuture
                  ? 0.0
                  : maxCount > 0
                      ? count / maxCount
                      : 0.0;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      // Bar.
                      SizedBox(
                        height: 36,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                            width: double.infinity,
                            height: isFuture
                                ? 4
                                : (4 + barFill * 32).clamp(4.0, 36.0),
                            decoration: BoxDecoration(
                              color: isFuture
                                  ? scheme.onPrimaryContainer
                                      .withValues(alpha: 0.15)
                                  : barFill > 0
                                      ? scheme.onPrimaryContainer
                                          .withValues(alpha: 0.85)
                                      : scheme.onPrimaryContainer
                                          .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                              border: isToday
                                  ? Border.all(
                                      color: scheme.onPrimaryContainer,
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayLabels[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isToday
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: scheme.onPrimaryContainer
                              .withValues(alpha: isToday ? 1.0 : 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Habit Card ────────────────────────────────────────────────────────────────

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
    final done =
        await HabitRepository.instance.isCompletedToday(widget.habit.id);
    final streak =
        await HabitRepository.instance.currentStreak(widget.habit.id);
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
    final hasGoal = h.targetValue != null && h.targetValue! > 0;
    // Completion rate over last 7 days as a proxy for today's progress
    // when there's a goal (binary for now — full credit when done today).
    final goalProgress = hasGoal ? (_done ? 1.0 : 0.0) : null;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Checkbox.
                  GestureDetector(
                    onTap: _toggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _done ? color : Colors.transparent,
                        border: Border.all(color: color, width: 2.5),
                      ),
                      child: _done
                          ? const Icon(Icons.check_rounded,
                              size: 20, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name + streak.
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
                        // Goal label or streak.
                        if (hasGoal)
                          Text(
                            'Goal: ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'.trim(),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        else
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
                  // 7-day strip.
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
              // ── Feature 2: Goal progress bar ─────────────────────────
              if (hasGoal) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: goalProgress ?? 0.0,
                          minHeight: 5,
                          backgroundColor:
                              scheme.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _done
                          ? '${_fmtTarget(h.targetValue!)} / ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'.trim()
                          : '0 / ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'.trim(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _done ? color : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (_streak > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '🔥 $_streak day streak',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
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

  String _fmtTarget(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();
}

// ── Habit Detail Sheet ────────────────────────────────────────────────────────

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
            // Drag handle.
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
            if (habit.targetValue != null) ...[
              const SizedBox(height: 4),
              Text(
                'Goal: ${habit.targetValue! % 1 == 0 ? habit.targetValue!.toInt() : habit.targetValue!} ${habit.targetUnit ?? ''}'.trim(),
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Action buttons.
            Row(
              children: [
                // Stats button — Feature 1.
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HabitStatsScreen(habit: habit),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bar_chart_rounded),
                    label: const Text('Stats'),
                  ),
                ),
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
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
