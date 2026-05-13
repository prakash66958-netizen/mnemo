import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/habit.dart';
import '../../services/habit_repository.dart';

/// Full-screen stats view for a single habit.
/// Shows: current streak, longest streak, completion rates (7/30/90 days),
/// and a monthly calendar heatmap.
class HabitStatsScreen extends StatefulWidget {
  const HabitStatsScreen({super.key, required this.habit});
  final Habit habit;

  @override
  State<HabitStatsScreen> createState() => _HabitStatsScreenState();
}

class _HabitStatsScreenState extends State<HabitStatsScreen> {
  // Displayed month for the heatmap.
  late DateTime _month;

  // Loaded stats.
  int _currentStreak = 0;
  int _longestStreak = 0;
  double _rate7 = 0;
  double _rate30 = 0;
  double _rate90 = 0;
  int _totalCompletions = 0;
  Map<DateTime, bool> _monthMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = HabitRepository.instance;
    final id = widget.habit.id;
    final results = await Future.wait([
      repo.currentStreak(id),
      repo.longestStreak(id),
      repo.completionRateForDays(id, 7),
      repo.completionRateForDays(id, 30),
      repo.completionRateForDays(id, 90),
      repo.totalCompletions(id),
      repo.monthCompletions(id, _month.year, _month.month),
    ]);
    if (!mounted) return;
    setState(() {
      _currentStreak = results[0] as int;
      _longestStreak = results[1] as int;
      _rate7 = results[2] as double;
      _rate30 = results[3] as double;
      _rate90 = results[4] as double;
      _totalCompletions = results[5] as int;
      _monthMap = results[6] as Map<DateTime, bool>;
      _loading = false;
    });
  }

  Future<void> _changeMonth(int delta) async {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _loading = true;
    });
    final map = await HabitRepository.instance
        .monthCompletions(widget.habit.id, _month.year, _month.month);
    if (!mounted) return;
    setState(() {
      _monthMap = map;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.habit;
    final color = Color(h.colorValue);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text('${h.emoji ?? ''} ${h.name}'.trim()),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // ── Streak cards ──────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Current streak',
                        value: '$_currentStreak',
                        suffix: _currentStreak == 1 ? 'day' : 'days',
                        icon: Icons.local_fire_department_rounded,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Longest streak',
                        value: '$_longestStreak',
                        suffix: _longestStreak == 1 ? 'day' : 'days',
                        icon: Icons.emoji_events_rounded,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Total done',
                        value: '$_totalCompletions',
                        suffix: _totalCompletions == 1 ? 'time' : 'times',
                        icon: Icons.check_circle_rounded,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Best rate among the three windows.
                    Expanded(
                      child: _StatCard(
                        label: 'Best rate',
                        value:
                            '${(_bestRate * 100).round()}%',
                        suffix: _bestRateLabel,
                        icon: Icons.trending_up_rounded,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Completion rate bars ──────────────────────────────────
                _SectionHeader(label: 'Completion rate', color: color),
                const SizedBox(height: 10),
                _RateBar(label: 'Last 7 days', rate: _rate7, color: color),
                const SizedBox(height: 8),
                _RateBar(label: 'Last 30 days', rate: _rate30, color: color),
                const SizedBox(height: 8),
                _RateBar(label: 'Last 90 days', rate: _rate90, color: color),
                const SizedBox(height: 24),

                // ── Monthly heatmap ───────────────────────────────────────
                _SectionHeader(label: 'Monthly view', color: color),
                const SizedBox(height: 10),
                _MonthHeatmap(
                  month: _month,
                  completions: _monthMap,
                  color: color,
                  onPrev: () => _changeMonth(-1),
                  onNext: _month.isBefore(
                          DateTime(DateTime.now().year, DateTime.now().month))
                      ? () => _changeMonth(1)
                      : null,
                ),
              ],
            ),
    );
  }

  double get _bestRate => [_rate7, _rate30, _rate90]
      .reduce((a, b) => a > b ? a : b);

  String get _bestRateLabel {
    if (_bestRate == _rate7) return '7-day';
    if (_bestRate == _rate30) return '30-day';
    return '90-day';
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final String suffix;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(
      color.withValues(alpha: 0.10),
      scheme.surfaceContainerHigh,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            suffix,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateBar extends StatelessWidget {
  const _RateBar({
    required this.label,
    required this.rate,
    required this.color,
  });
  final String label;
  final double rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = (rate * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _MonthHeatmap extends StatelessWidget {
  const _MonthHeatmap({
    required this.month,
    required this.completions,
    required this.color,
    required this.onPrev,
    this.onNext,
  });
  final DateTime month;
  final Map<DateTime, bool> completions;
  final Color color;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daysInMonth =
        DateUtils.getDaysInMonth(month.year, month.month);
    // Weekday of the 1st (1=Mon, 7=Sun → 0-indexed offset).
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final offset = firstWeekday - 1; // 0 = Monday start

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // Month navigation header.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: onPrev,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                DateFormat('MMMM yyyy').format(month),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onNext,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Day-of-week labels.
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          // Calendar grid.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: offset + daysInMonth,
            itemBuilder: (_, index) {
              if (index < offset) return const SizedBox.shrink();
              final day = index - offset + 1;
              final date = DateTime(month.year, month.month, day);
              final done = completions[date] ?? false;
              final isToday = DateUtils.isSameDay(date, DateTime.now());
              final isFuture = date.isAfter(DateTime.now());

              return Container(
                decoration: BoxDecoration(
                  color: done
                      ? color
                      : isFuture
                          ? Colors.transparent
                          : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: isToday
                      ? Border.all(color: color, width: 1.5)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isToday ? FontWeight.w800 : FontWeight.w500,
                      color: done
                          ? Colors.white
                          : isFuture
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.3)
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Legend.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Completed',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Missed',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
