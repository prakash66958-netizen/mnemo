import 'package:flutter/material.dart';

import '../models/habit.dart';

/// Pure helpers that translate a [Habit]'s reminder schedule fields into a
/// concrete list of slots for a single local day.
///
/// These functions are the single source of truth for "how many checkboxes
/// should the habit card render today?" and "what time labels do those
/// checkboxes display?". The habit card UI ([_HabitCard] in `focus_tab.dart`)
/// and the per-day completion percentage on `habit_stats_screen.dart` both
/// consume this module so the two surfaces never disagree.
///
/// All time math is in local-day minute arithmetic: `startMinutes` is
/// `remindHour * 60 + remindMinute` (defaulting nulls to 0) and `endMinutes`
/// is `intervalEndHour * 60`. Per Requirement 7, a Habit with
/// `intervalMinutes <= 0` is treated as a single-slot legacy habit, and a
/// Habit whose end hour falls before the start time is also collapsed to a
/// single slot so an invalid range never crashes the card.

/// Returns the number of reminder slots [h] produces in a single local day.
///
/// Always returns a value >= 1.
///
/// Algorithm (Req 7.1, 7.2, 7.3, 7.12):
///
///   * `intervalMinutes <= 0`      → 1 (legacy single-slot habit)
///   * `endMinutes < startMinutes` → 1 (invalid range fallback)
///   * otherwise                   → `((end - start) ~/ step) + 1`
int dailySlotCount(Habit h) {
  if (h.intervalMinutes <= 0) return 1;
  final start = (h.remindHour ?? 0) * 60 + (h.remindMinute ?? 0);
  final end = h.intervalEndHour * 60;
  if (end < start) return 1;
  return ((end - start) ~/ h.intervalMinutes) + 1;
}

/// Returns the wall-clock start time of slot [index] for habit [h].
///
/// [index] is clamped to `[0, dailySlotCount(h) - 1]` so callers that pass
/// a stale or out-of-range index still get a well-defined time. The hour is
/// taken modulo 24 so an interval that wraps past midnight (which we do not
/// expose to users today, but might in the future) still produces a valid
/// `TimeOfDay`.
TimeOfDay slotStartTime(Habit h, int index) {
  final count = dailySlotCount(h);
  final clamped = index.clamp(0, count - 1);
  final start = (h.remindHour ?? 0) * 60 + (h.remindMinute ?? 0);
  final step = h.intervalMinutes <= 0 ? 0 : h.intervalMinutes;
  final m = start + step * clamped;
  return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
}

/// Returns every slot start time for [h], in ascending order from the first
/// slot of the day to the last.
List<TimeOfDay> slotStartTimes(Habit h) =>
    List<TimeOfDay>.generate(dailySlotCount(h), (i) => slotStartTime(h, i));

/// Formats a [TimeOfDay] as a 24-hour `HH:MM` label, e.g. `09:05`, `22:00`.
///
/// This is the label rendered on each slot checkbox so users can match the
/// checkbox to the corresponding reminder time at a glance.
String formatSlotLabel(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
