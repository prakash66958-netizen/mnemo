// Focus tab — combines a Pomodoro timer and the habit tracker.
//
// Layout: segmented selector at the top toggles between "Timer" and "Habits".
// A live countdown badge stays in the header so the user always sees the
// running timer regardless of which sub-section is selected.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../models/habit.dart';
import '../../services/habit_repository.dart';
import '../../services/habit_slot_calculator.dart';
import '../../services/notification_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/segmented_tabs.dart';
import '../habits/habit_editor_sheet.dart';
import '../habits/habit_stats_screen.dart';
import '../shared/providers.dart';

// ── Pomodoro state ────────────────────────────────────────────────────────────

enum PomPhase { work, shortBreak, longBreak }

/// Customisable phase durations (in seconds). Defaults match the classic
/// Pomodoro technique: 25/5/15. The user can override these from the timer
/// settings sheet.
class PomDurations {
  const PomDurations({
    required this.workSecs,
    required this.shortSecs,
    required this.longSecs,
  });

  final int workSecs;
  final int shortSecs;
  final int longSecs;

  static const defaults = PomDurations(
    workSecs: 25 * 60,
    shortSecs: 5 * 60,
    longSecs: 15 * 60,
  );

  int forPhase(PomPhase phase) {
    switch (phase) {
      case PomPhase.work:
        return workSecs;
      case PomPhase.shortBreak:
        return shortSecs;
      case PomPhase.longBreak:
        return longSecs;
    }
  }

  PomDurations copyWith({int? workSecs, int? shortSecs, int? longSecs}) =>
      PomDurations(
        workSecs: workSecs ?? this.workSecs,
        shortSecs: shortSecs ?? this.shortSecs,
        longSecs: longSecs ?? this.longSecs,
      );
}

class PomodoroState {
  const PomodoroState({
    required this.phase,
    required this.secondsLeft,
    required this.running,
    required this.session,
    required this.durations,
  });
  final PomPhase phase;
  final int secondsLeft;
  final bool running;
  final int session; // 1..4 before long break
  final PomDurations durations;

  factory PomodoroState.initial(
          [PomDurations durations = PomDurations.defaults]) =>
      PomodoroState(
        phase: PomPhase.work,
        secondsLeft: durations.workSecs,
        running: false,
        session: 1,
        durations: durations,
      );

  PomodoroState copyWith({
    PomPhase? phase,
    int? secondsLeft,
    bool? running,
    int? session,
    PomDurations? durations,
  }) =>
      PomodoroState(
        phase: phase ?? this.phase,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        running: running ?? this.running,
        session: session ?? this.session,
        durations: durations ?? this.durations,
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
    final total = durations.forPhase(phase);
    return total > 0 ? 1.0 - (secondsLeft / total) : 0.0;
  }
}

/// Persistent, kill-resilient Pomodoro state.
///
/// Storage strategy:
/// - When running, we persist the absolute end-timestamp (`prefPomEndsAt`).
///   On restore we compute `secondsLeft = endsAt - now` so the timer keeps
///   ticking accurately even if the app was killed for an hour.
/// - When paused, we persist `secondsLeft` directly.
/// - We also schedule a local notification at the end-timestamp so the user
///   gets an "alarm" when the phase ends — even if the app is closed.
class PomodoroNotifier extends StateNotifier<PomodoroState> {
  PomodoroNotifier() : super(PomodoroState.initial()) {
    _restore();
  }

  Timer? _timer;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final durations = PomDurations(
      workSecs:
          prefs.getInt(AppConstants.prefPomWorkSecs) ?? PomDurations.defaults.workSecs,
      shortSecs: prefs.getInt(AppConstants.prefPomShortSecs) ??
          PomDurations.defaults.shortSecs,
      longSecs: prefs.getInt(AppConstants.prefPomLongSecs) ??
          PomDurations.defaults.longSecs,
    );

    final phaseName = prefs.getString(AppConstants.prefPomPhase);
    final phase = PomPhase.values.firstWhere(
      (p) => p.name == phaseName,
      orElse: () => PomPhase.work,
    );
    final session = prefs.getInt(AppConstants.prefPomSession) ?? 1;
    final running = prefs.getBool(AppConstants.prefPomRunning) ?? false;
    final endsAtStr = prefs.getString(AppConstants.prefPomEndsAt);

    int secondsLeft = durations.forPhase(phase);
    bool stillRunning = running;

    if (running && endsAtStr != null) {
      final endsAt = DateTime.tryParse(endsAtStr);
      if (endsAt != null) {
        final remaining = endsAt.difference(DateTime.now()).inSeconds;
        if (remaining > 0) {
          secondsLeft = remaining;
        } else {
          // Phase ended while the app was closed — stop and reset to next
          // phase's full duration so the user can start it fresh.
          stillRunning = false;
          secondsLeft = durations.forPhase(phase);
        }
      }
    } else {
      secondsLeft = prefs.getInt(AppConstants.prefPomSecsLeft) ??
          durations.forPhase(phase);
    }

    state = PomodoroState(
      phase: phase,
      secondsLeft: secondsLeft,
      running: stillRunning,
      session: session,
      durations: durations,
    );

    // Resume the ticking timer if we were running.
    if (stillRunning) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  Future<void> _persist({DateTime? endsAt}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefPomPhase, state.phase.name);
    await prefs.setInt(AppConstants.prefPomSession, state.session);
    await prefs.setBool(AppConstants.prefPomRunning, state.running);
    await prefs.setInt(AppConstants.prefPomSecsLeft, state.secondsLeft);
    if (endsAt != null) {
      await prefs.setString(
          AppConstants.prefPomEndsAt, endsAt.toIso8601String());
    } else {
      await prefs.remove(AppConstants.prefPomEndsAt);
    }
  }

  /// Updates the user's custom durations and resets the current phase to its
  /// new full length (only when not running).
  Future<void> setDurations(PomDurations d) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.prefPomWorkSecs, d.workSecs);
    await prefs.setInt(AppConstants.prefPomShortSecs, d.shortSecs);
    await prefs.setInt(AppConstants.prefPomLongSecs, d.longSecs);
    if (state.running) {
      // Apply only the durations object — keep the running countdown intact.
      state = state.copyWith(durations: d);
    } else {
      state = state.copyWith(
        durations: d,
        secondsLeft: d.forPhase(state.phase),
      );
      await _persist();
    }
  }

  void toggle() {
    if (state.running) {
      _pause();
    } else {
      _start();
    }
  }

  Future<void> _start() async {
    final endsAt = DateTime.now().add(Duration(seconds: state.secondsLeft));
    state = state.copyWith(running: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    await _persist(endsAt: endsAt);
    await _scheduleEndNotification(endsAt);
  }

  Future<void> _pause() async {
    _timer?.cancel();
    state = state.copyWith(running: false);
    await _persist();
    await NotificationService.instance.cancelFocusEnd();
  }

  Future<void> _scheduleEndNotification(DateTime endsAt) async {
    final String title;
    final String body;
    switch (state.phase) {
      case PomPhase.work:
        title = '🎯 Focus session complete';
        body = 'Great work! Time for a break.';
      case PomPhase.shortBreak:
        title = '☕ Break\'s over';
        body = 'Ready to focus? Tap to start the next session.';
      case PomPhase.longBreak:
        title = '🌟 Long break done';
        body = 'Recharged and ready. Let\'s go!';
    }
    await NotificationService.instance.scheduleFocusEnd(
      when: endsAt,
      title: title,
      body: body,
    );
  }

  void _tick() {
    if (state.secondsLeft <= 1) {
      _timer?.cancel();
      _advance();
    } else {
      state = state.copyWith(secondsLeft: state.secondsLeft - 1);
    }
  }

  Future<void> _advance() async {
    await NotificationService.instance.cancelFocusEnd();
    if (state.phase == PomPhase.work) {
      final nextSession = state.session + 1;
      if (nextSession > 4) {
        state = PomodoroState(
          phase: PomPhase.longBreak,
          secondsLeft: state.durations.longSecs,
          running: false,
          session: 1,
          durations: state.durations,
        );
      } else {
        state = PomodoroState(
          phase: PomPhase.shortBreak,
          secondsLeft: state.durations.shortSecs,
          running: false,
          session: nextSession,
          durations: state.durations,
        );
      }
    } else {
      state = PomodoroState(
        phase: PomPhase.work,
        secondsLeft: state.durations.workSecs,
        running: false,
        session: state.session,
        durations: state.durations,
      );
    }
    await _persist();
  }

  Future<void> reset() async {
    _timer?.cancel();
    state = PomodoroState.initial(state.durations);
    await _persist();
    await NotificationService.instance.cancelFocusEnd();
  }

  Future<void> skipTo(PomPhase phase) async {
    _timer?.cancel();
    state = PomodoroState(
      phase: phase,
      secondsLeft: state.durations.forPhase(phase),
      running: false,
      session: state.session,
      durations: state.durations,
    );
    await _persist();
    await NotificationService.instance.cancelFocusEnd();
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
              const SizedBox(width: 16),
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
              const SizedBox(width: 16),
              IconButton.outlined(
                onPressed: pom.running
                    ? null
                    : () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => _DurationsSheet(
                            current: pom.durations,
                          ),
                        ),
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Customise durations',
                style: IconButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  minimumSize: const Size(48, 48),
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
  Set<int> _completedSlots = <int>{};
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
    final slots =
        await HabitRepository.instance.completedSlotsToday(widget.habit.id);
    final streak =
        await HabitRepository.instance.currentStreak(widget.habit.id);
    final week =
        await HabitRepository.instance.last7Days(widget.habit.id);
    if (!mounted) return;
    setState(() {
      _completedSlots = slots;
      _streak = streak;
      _week = week;
    });
  }

  Future<void> _toggleSlot(int slotIndex) async {
    await HabitRepository.instance.toggleSlot(widget.habit, slotIndex);
    await _load();
  }

  /// True when slot 0 is completed for today. Used for the legacy
  /// binary-checkbox path (single-slot habits) and for surfaces (week
  /// dots, goal progress) that retain the day-level "did anything" view.
  bool get _doneToday => _completedSlots.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    final color = Color(h.colorValue);
    final scheme = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(
        color.withValues(alpha: 0.10), scheme.surfaceContainerHigh);
    final hasGoal = h.targetValue != null && h.targetValue! > 0;
    // Goal progress mirrors the legacy binary view: any completion today
    // counts as goal-met. This keeps single-slot habits visually unchanged
    // and keeps streak / week-dot semantics intact for multi-slot habits.
    final goalProgress = hasGoal ? (_doneToday ? 1.0 : 0.0) : null;
    final slotCount = dailySlotCount(h);
    // Req 7.14: when an edit shrinks today's slot count below an existing
    // recorded slotIndex, render only `[0, slotCount - 1]`. The disk row
    // is left intact by HabitRepository.toggleSlot (we never touch it).
    final visibleSlots = <int>{
      for (final s in _completedSlots)
        if (s < slotCount) s,
    };

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
                  if (slotCount == 1)
                    GestureDetector(
                      onTap: () => _toggleSlot(0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _doneToday ? color : Colors.transparent,
                          border: Border.all(color: color, width: 2.5),
                        ),
                        child: _doneToday
                            ? const Icon(Icons.check_rounded,
                                size: 20, color: Colors.white)
                            : null,
                      ),
                    )
                  else
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.12),
                        border: Border.all(
                          color: color.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '${visibleSlots.length}/$slotCount',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
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
              if (slotCount > 1) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < slotCount; i++)
                      _SlotCheckbox(
                        label:
                            formatSlotLabel(slotStartTime(h, i)),
                        checked: visibleSlots.contains(i),
                        color: color,
                        onTap: () => _toggleSlot(i),
                      ),
                  ],
                ),
              ],
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
                      _doneToday
                          ? '${_fmtTarget(h.targetValue!)} / ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'
                              .trim()
                          : '0 / ${_fmtTarget(h.targetValue!)} ${h.targetUnit ?? ''}'
                              .trim(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _doneToday
                            ? color
                            : scheme.onSurfaceVariant,
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
    ).then((_) {
      // Req 7.13: when the user edits the habit (slot count, time range,
      // interval, etc.), the editor sheet closes and we re-load so the
      // card re-renders against the new schedule. We always reload —
      // even on plain "Stats" or "Delete" closes — because reloading is
      // cheap and keeps the card's day/streak/week state fresh.
      if (mounted) _load();
    });
  }

  String _fmtTarget(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();
}

// ── Per-slot checkbox chip ────────────────────────────────────────────────────
//
// Used by [_HabitCard] for habits with `dailySlotCount > 1`. Renders the
// slot's start time as a tappable pill that toggles between unchecked
// (outlined) and checked (filled with a tick). Visually consistent with the
// legacy binary checkbox so single-slot habits and multi-slot habits read
// as variants of the same affordance.

class _SlotCheckbox extends StatelessWidget {
  const _SlotCheckbox({
    required this.label,
    required this.checked,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: checked ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked ? color : color.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                checked
                    ? Icons.check_rounded
                    : Icons.access_time_rounded,
                key: ValueKey<bool>(checked),
                size: 14,
                color: checked ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: checked ? Colors.white : scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
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


// ── Custom durations bottom sheet ────────────────────────────────────────────

/// Bottom sheet that lets the user pick custom durations for each Pomodoro
/// phase. Shows quick-pick presets (15, 25, 30, 45, 60 for focus; 5, 10, 15
/// for breaks) plus a custom number input for any other value.
class _DurationsSheet extends ConsumerStatefulWidget {
  const _DurationsSheet({required this.current});
  final PomDurations current;

  @override
  ConsumerState<_DurationsSheet> createState() => _DurationsSheetState();
}

class _DurationsSheetState extends ConsumerState<_DurationsSheet> {
  late int _workMin;
  late int _shortMin;
  late int _longMin;

  @override
  void initState() {
    super.initState();
    _workMin = widget.current.workSecs ~/ 60;
    _shortMin = widget.current.shortSecs ~/ 60;
    _longMin = widget.current.longSecs ~/ 60;
  }

  Future<void> _save() async {
    final d = PomDurations(
      workSecs: _workMin.clamp(1, 180) * 60,
      shortSecs: _shortMin.clamp(1, 60) * 60,
      longSecs: _longMin.clamp(1, 120) * 60,
    );
    await ref.read(pomodoroProvider.notifier).setDurations(d);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Customise durations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Set the length of each phase. Defaults match the classic Pomodoro: 25 / 5 / 15 minutes.',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            _DurationPicker(
              label: 'Focus',
              icon: Icons.timer_rounded,
              minutes: _workMin,
              presets: const [15, 25, 30, 45, 60, 90],
              maxMinutes: 180,
              onChanged: (v) => setState(() => _workMin = v),
            ),
            const SizedBox(height: 14),
            _DurationPicker(
              label: 'Short Break',
              icon: Icons.coffee_rounded,
              minutes: _shortMin,
              presets: const [3, 5, 7, 10],
              maxMinutes: 60,
              onChanged: (v) => setState(() => _shortMin = v),
            ),
            const SizedBox(height: 14),
            _DurationPicker(
              label: 'Long Break',
              icon: Icons.spa_rounded,
              minutes: _longMin,
              presets: const [10, 15, 20, 30],
              maxMinutes: 120,
              onChanged: (v) => setState(() => _longMin = v),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
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

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({
    required this.label,
    required this.icon,
    required this.minutes,
    required this.presets,
    required this.maxMinutes,
    required this.onChanged,
  });
  final String label;
  final IconData icon;
  final int minutes;
  final List<int> presets;
  final int maxMinutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCustom = !presets.contains(minutes);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$minutes min',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in presets)
                ChoiceChip(
                  label: Text('$p'),
                  selected: minutes == p,
                  onSelected: (_) => onChanged(p),
                  visualDensity: VisualDensity.compact,
                ),
              ChoiceChip(
                label: Text(isCustom ? 'Custom · $minutes' : 'Custom…'),
                selected: isCustom,
                onSelected: (_) => _showCustomDialog(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomDialog(BuildContext context) async {
    final controller = TextEditingController(text: '$minutes');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label duration'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Minutes (1–$maxMinutes)',
            suffixText: 'min',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v >= 1 && v <= maxMinutes) {
                Navigator.pop(ctx, v);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null) onChanged(result);
  }
}
