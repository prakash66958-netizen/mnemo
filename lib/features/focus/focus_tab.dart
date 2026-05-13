// Focus tab — combines a Pomodoro timer and the habit tracker.
//
// Layout: segmented selector at the top toggles between "Timer" and "Habits".
// A live countdown badge stays in the header so the user always sees the
// running timer regardless of which sub-section is selected.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../services/habit_repository.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/segmented_tabs.dart';
import '../habits/habit_editor_sheet.dart';
import '../habits/habit_stats_screen.dart';
import '../shared/providers.dart';

// ── Pomodoro state ────────────────────────────────────────────────────────────

enum PomPhase { work, shortBreak, longBreak }

class PomodoroState {
  const PomodoroState({
    required this.phase,
    required this.secondsLeft,
    required this.running,
    required this.session,
  });
  final PomPhase phase;
  final int secondsLeft;
  final bool running;
  final int session; // 1..4 before long break

  static const _workSecs = 25 * 60;
  static const _shortSecs = 5 * 60;
  static const _longSecs = 15 * 60;

  factory PomodoroState.initial() => const PomodoroState(
        phase: PomPhase.work,
        secondsLeft: _workSecs,
        running: false,
        session: 1,
      );

  PomodoroState copyWith({
    PomPhase? phase,
    int? secondsLeft,
    bool? running,
    int? session,
  }) =>
      PomodoroState(
        phase: phase ?? this.phase,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        running: running ?? this.running,
        session: session ?? this.session,
      );

  String get label {
    switch (phase) {
      case PomPhase.work:
        return 'Focus';
      case PomPhase.shortBreak:
        return 'Short Break';
      case PomPhase.longBreak:
        return 'Long Break';
    }
  }

  String get timeString {
    final m = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get progress {
    final total = phase == PomPhase.work
        ? _workSecs
        : phase == PomPhase.shortBreak
            ? _shortSecs
            : _longSecs;
    return 1.0 - (secondsLeft / total);
  }
}

class PomodoroNotifier extends StateNotifier<PomodoroState> {
  PomodoroNotifier() : super(PomodoroState.initial());
  Timer? _timer;

  void toggle() {
    if (state.running) {
      _timer?.cancel();
      state = state.copyWith(running: false);
    } else {
      state = state.copyWith(running: true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    if (state.secondsLeft <= 1) {
      _timer?.cancel();
      _advance();
    } else {
      state = state.copyWith(secondsLeft: state.secondsLeft - 1);
    }
  }

  void _advance() {
    if (state.phase == PomPhase.work) {
      final nextSession = state.session + 1;
      if (nextSession > 4) {
        state = const PomodoroState(
          phase: PomPhase.longBreak,
          secondsLeft: PomodoroState._longSecs,
          running: false,
          session: 1,
        );
      } else {
        state = PomodoroState(
          phase: PomPhase.shortBreak,
          secondsLeft: PomodoroState._shortSecs,
          running: false,
          session: nextSession,
        );
      }
    } else {
      state = PomodoroState(
        phase: PomPhase.work,
        secondsLeft: PomodoroState._workSecs,
        running: false,
        session: state.session,
      );
    }
  }

  void reset() {
    _timer?.cancel();
    state = PomodoroState.initial();
  }

  void skipTo(PomPhase phase) {
    _timer?.cancel();
    final secs = phase == PomPhase.work
        ? PomodoroState._workSecs
        : phase == PomPhase.shortBreak
            ? PomodoroState._shortSecs
            : PomodoroState._longSecs;
    state = PomodoroState(
      phase: phase,
      secondsLeft: secs,
      running: false,
      session: state.session,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final pomodoroProvider =
    StateNotifierProvider<PomodoroNotifier, PomodoroState>(
  (ref) => PomodoroNotifier(),
);

// ── Section enum ──────────────────────────────────────────────────────────────

enum _FocusSection { timer, habits }

// ── Focus Tab ─────────────────────────────────────────────────────────────────

class FocusTab extends ConsumerStatefulWidget {
  const FocusTab({super.key});

  @override
  ConsumerState<FocusTab> createState() => _FocusTabState();
}

class _FocusTabState extends ConsumerState<FocusTab> {
  _FocusSection _section = _FocusSection.timer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pom = ref.watch(pomodoroProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Focus',
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
                  // Live timer badge — visible even when on Habits tab
                  if (pom.running) _LiveBadge(timeString: pom.timeString),
                ],
              ),
            ),
            // ── Segmented selector ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SegmentedTabs<_FocusSection>(
                values: _FocusSection.values,
                labelOf: (s) =>
                    s == _FocusSection.timer ? '⏱  Timer' : '✅  Habits',
                selected: _section,
                onChanged: (s) => setState(() => _section = s),
              ),
            ),
            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _section == _FocusSection.timer
                    ? const _TimerSection(key: ValueKey('timer'))
                    : const _HabitsSection(key: ValueKey('habits')),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _section == _FocusSection.habits
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New habit'),
            )
          : null,
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

// ── Live badge in header ──────────────────────────────────────────────────────

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.timeString});
  final String timeString;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_rounded,
              size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            timeString,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timer Section ─────────────────────────────────────────────────────────────

class _TimerSection extends ConsumerWidget {
  const _TimerSection({super.key});

  /// Phase colours that adapt to dark mode automatically.
  /// We keep work tied to the theme primary so it changes seamlessly,
  /// and use slightly desaturated greens/cyans for breaks.
  static Color _phaseColor(PomPhase phase, ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    switch (phase) {
      case PomPhase.work:
        return scheme.primary;
      case PomPhase.shortBreak:
        return isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A);
      case PomPhase.longBreak:
        return isDark ? const Color(0xFF22D3EE) : const Color(0xFF0891B2);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pom = ref.watch(pomodoroProvider);
    final notifier = ref.read(pomodoroProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    final phaseColor = _phaseColor(pom.phase, scheme);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
      child: Column(
        children: [
          // Phase chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PhaseChip(
                label: 'Focus',
                active: pom.phase == PomPhase.work,
                color: _phaseColor(PomPhase.work, scheme),
                onTap: () => notifier.skipTo(PomPhase.work),
              ),
              const SizedBox(width: 8),
              _PhaseChip(
                label: 'Short Break',
                active: pom.phase == PomPhase.shortBreak,
                color: _phaseColor(PomPhase.shortBreak, scheme),
                onTap: () => notifier.skipTo(PomPhase.shortBreak),
              ),
              const SizedBox(width: 8),
              _PhaseChip(
                label: 'Long Break',
                active: pom.phase == PomPhase.longBreak,
                color: _phaseColor(PomPhase.longBreak, scheme),
                onTap: () => notifier.skipTo(PomPhase.longBreak),
              ),
            ],
          ),
          const SizedBox(height: 36),
          // Large circular timer
          SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: pom.progress,
                    strokeWidth: 8,
                    backgroundColor: phaseColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pom.timeString,
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        color: phaseColor,
                        letterSpacing: -2,
                      ),
                    ),
                    Text(
                      pom.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: phaseColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Session dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Session',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              ...List.generate(4, (i) {
                final filled = i < pom.session - 1 ||
                    (pom.phase == PomPhase.work && i == pom.session - 1);
                return Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? phaseColor
                        : phaseColor.withValues(alpha: 0.2),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 32),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                onPressed: notifier.reset,
                icon: const Icon(Icons.refresh_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  minimumSize: const Size(48, 48),
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 160,
                height: 52,
                child: FilledButton.icon(
                  onPressed: notifier.toggle,
                  icon: Icon(
                    pom.running
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 24,
                  ),
                  label: Text(
                    pom.running ? 'Pause' : 'Start Focus',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: phaseColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Tips card
          _TipsCard(phase: pom.phase),
        ],
      ),
    );
  }
}

// ── Tips card shown below the timer ──────────────────────────────────────────

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.phase});
  final PomPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String tip;
    final IconData icon;
    switch (phase) {
      case PomPhase.work:
        tip = 'Put your phone face-down and close distracting tabs. '
            'You\'ve got 25 minutes — make them count.';
        icon = Icons.lightbulb_outline_rounded;
      case PomPhase.shortBreak:
        tip = 'Stand up, stretch, grab some water. '
            'A 5-minute reset makes the next session sharper.';
        icon = Icons.self_improvement_rounded;
      case PomPhase.longBreak:
        tip = 'Great work — 4 sessions done! '
            'Take 15 minutes to recharge before the next round.';
        icon = Icons.celebration_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color : color.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? color : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── Habits Section ────────────────────────────────────────────────────────────

class _HabitsSection extends ConsumerWidget {
  const _HabitsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitListProvider);
    final scheme = Theme.of(context).colorScheme;

    return habitsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (habits) {
        if (habits.isEmpty) {
          return EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'No habits yet',
            subtitle: 'Track daily habits like exercise, reading, or '
                'drinking water. Tap + to create your first one.',
            action: FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const HabitEditorSheet(),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New habit'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            _WeeklyReviewBanner(
                habitIds: habits.map((h) => h.id).toList()),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Today\'s habits',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${habits.length} total',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
    );
  }
}

// ── Weekly Review Banner ──────────────────────────────────────────────────────
//
// Fix: previously the bar chart sat directly under the "This week" row with
// only 10px of gap — when bars reached full height (36px) they visually
// crowded the title text. The chart is now wrapped in its own container with
// a clear vertical gutter and the bar height is reduced slightly so it
// breathes.

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
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      // Slightly more vertical padding to give the chart breathing room.
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — title, count, percentage.
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: 6),
              Text('This week',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer)),
              const Spacer(),
              Text('$_completed / $_total',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer)),
              const SizedBox(width: 4),
              Text('($pct%)',
                  style: TextStyle(
                      fontSize: 12,
                      color: scheme.onPrimaryContainer
                          .withValues(alpha: 0.7))),
            ],
          ),
          // ↓ Increased gap from 10 → 16 so bars don't crowd the title.
          const SizedBox(height: 16),
          // Chart container — fixed height includes both bars and labels,
          // so nothing can spill upward.
          SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
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
                // Reduced max bar height from 36 → 32 to leave a clean gap.
                final barHeight =
                    isFuture ? 4.0 : (4 + barFill * 28).clamp(4.0, 32.0);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          width: double.infinity,
                          height: barHeight,
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
                                    width: 1.5)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
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
          ),
          const SizedBox(height: 10),
          Text(message,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer
                      .withValues(alpha: 0.85))),
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
    final week =
        await HabitRepository.instance.last7Days(widget.habit.id);
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
        color.withValues(alpha: 0.10), scheme.surfaceContainerHigh);
    final hasGoal = h.targetValue != null && h.targetValue! > 0;
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${h.emoji ?? ''} ${h.name}'.trim(),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        if (hasGoal)
                          Text(
                            'Goal: ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'
                                .trim(),
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant),
                          )
                        else
                          Text(
                            _streak > 0
                                ? '🔥 $_streak day streak'
                                : 'No reminder',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final d in _week)
                        Container(
                          width: 8,
                          height: 8,
                          margin:
                              const EdgeInsets.symmetric(horizontal: 1.5),
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
                          ? '${_fmtTarget(h.targetValue!)} / ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'
                              .trim()
                          : '0 / ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'
                              .trim(),
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
                  Text('🔥 $_streak day streak',
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
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
                  fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            FutureBuilder<int>(
              future: HabitRepository.instance.currentStreak(habit.id),
              builder: (_, snap) => Text(
                '🔥 ${snap.data ?? 0} day streak',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ),
            if (habit.targetValue != null) ...[
              const SizedBox(height: 4),
              Text(
                'Goal: ${habit.targetValue! % 1 == 0 ? habit.targetValue!.toInt() : habit.targetValue!} ${habit.targetUnit ?? ''}'
                    .trim(),
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
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
                        builder: (_) =>
                            HabitEditorSheet(existing: habit),
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
                        foregroundColor: scheme.error),
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

