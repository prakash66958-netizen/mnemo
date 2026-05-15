import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../models/habit.dart';
import '../models/habit_completion.dart';
import 'database_service.dart';
import 'firestore_sync_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// Repository for creating, updating, and querying habits and their daily
/// completions. All writes also manage the corresponding daily notification
/// and emit Firestore sync hooks when `Sync_Enabled` is true.
class HabitRepository {
  HabitRepository._();
  static final HabitRepository instance = HabitRepository._();

  Isar get _isar => DatabaseService.instance.isar;

  /// Source of v4 UUIDs assigned to `cloudId` on create. Stable across
  /// instances (singleton repo) so tests can mock the package directly.
  static const _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // Habit mutations
  // ---------------------------------------------------------------------------

  Future<Habit> create({
    required String name,
    String? emoji,
    required Color color,
    TimeOfDay? remindAt,
  }) async {
    final now = DateTime.now();
    final habit = Habit()
      ..cloudId = _uuid.v4()
      ..name = name
      ..emoji = emoji
      ..colorValue = color.toARGB32()
      ..createdAt = now
      ..updatedAt = now
      ..remindHour = remindAt?.hour
      ..remindMinute = remindAt?.minute
      ..notificationId = 0;

    await _isar.writeTxn(() async {
      final id = await _isar.habits.put(habit);
      habit.notificationId = (id + 100000) & 0x7FFFFFFF;
      await _isar.habits.put(habit);
    });

    if (remindAt != null) {
      if (habit.intervalMinutes > 0) {
        await NotificationService.instance.scheduleInterval(
          baseId: habit.notificationId,
          title: '${emoji ?? '✅'} $name',
          body: "Time to check off your habit!",
          startHour: remindAt.hour,
          endHour: habit.intervalEndHour,
          intervalMinutes: habit.intervalMinutes,
        );
      } else {
        await NotificationService.instance.scheduleDaily(
          id: habit.notificationId,
          title: '${emoji ?? '✅'} $name',
          body: "Time to check off your habit!",
          hour: remindAt.hour,
          minute: remindAt.minute,
        );
      }
    }

    if (await SettingsService.instance.getSyncEnabled()) {
      FirestoreSyncService.instance.enqueueUpsert('habits', habit);
    }
    return habit;
  }

  Future<void> update(Habit habit) async {
    habit.updatedAt = DateTime.now();
    await NotificationService.instance.cancel(habit.notificationId);
    // Also cancel interval slots.
    for (var i = 0; i < 24; i++) {
      await NotificationService.instance.cancel(habit.notificationId + i);
    }
    await _isar.writeTxn(() async {
      await _isar.habits.put(habit);
    });
    if (!habit.archived && habit.remindHour != null) {
      if (habit.intervalMinutes > 0) {
        await NotificationService.instance.scheduleInterval(
          baseId: habit.notificationId,
          title: '${habit.emoji ?? '✅'} ${habit.name}',
          body: "Time to check off your habit!",
          startHour: habit.remindHour!,
          endHour: habit.intervalEndHour,
          intervalMinutes: habit.intervalMinutes,
        );
      } else {
        await NotificationService.instance.scheduleDaily(
          id: habit.notificationId,
          title: '${habit.emoji ?? '✅'} ${habit.name}',
          body: "Time to check off your habit!",
          hour: habit.remindHour!,
          minute: habit.remindMinute ?? 0,
        );
      }
    }
    if (await SettingsService.instance.getSyncEnabled()) {
      FirestoreSyncService.instance.enqueueUpsert('habits', habit);
    }
  }

  Future<void> delete(Habit habit) async {
    await NotificationService.instance.cancel(habit.notificationId);
    // Also cancel all interval slots (notificationId + 0 through + 23).
    for (var i = 0; i < 24; i++) {
      await NotificationService.instance.cancel(habit.notificationId + i);
    }
    final syncEnabled = await SettingsService.instance.getSyncEnabled();
    if (syncEnabled) {
      // Cascade: tombstone every completion under this habit so other
      // devices drop them too. The engine soft-deletes locally and hard-
      // deletes on tombstone ack.
      final completions = await _isar.habitCompletions
          .filter()
          .habitIdEqualTo(habit.id)
          .findAll();
      for (final c in completions) {
        FirestoreSyncService.instance
            .enqueueDelete('habitCompletions', c);
      }
      FirestoreSyncService.instance.enqueueDelete('habits', habit);
    } else {
      // Sync disabled — hard-delete locally as today.
      await _isar.writeTxn(() async {
        await _isar.habitCompletions
            .filter()
            .habitIdEqualTo(habit.id)
            .deleteAll();
        await _isar.habits.delete(habit.id);
      });
    }
  }

  Future<void> archive(Habit habit) async {
    habit.archived = !habit.archived;
    habit.updatedAt = DateTime.now();
    if (habit.archived) {
      await NotificationService.instance.cancel(habit.notificationId);
    }
    await _isar.writeTxn(() async {
      await _isar.habits.put(habit);
    });
    if (!habit.archived && habit.remindHour != null) {
      await NotificationService.instance.scheduleDaily(
        id: habit.notificationId,
        title: '${habit.emoji ?? '✅'} ${habit.name}',
        body: "Time to check off your habit!",
        hour: habit.remindHour!,
        minute: habit.remindMinute ?? 0,
      );
    }
    if (await SettingsService.instance.getSyncEnabled()) {
      FirestoreSyncService.instance.enqueueUpsert('habits', habit);
    }
  }

  // ---------------------------------------------------------------------------
  // HabitCompletion mutations
  // ---------------------------------------------------------------------------

  /// Returns the set of slot indices that have a completion record for today.
  ///
  /// "Today" is the device-local calendar date (midnight in the local
  /// timezone). Legacy rows whose `slotIndex` is null contribute index 0
  /// per Requirement 7.9.
  Future<Set<int>> completedSlotsToday(int habitId) async {
    final today = _midnightLocal(DateTime.now());
    final rows = await _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habitId)
        .dateEqualTo(today)
        .deletedAtIsNull()
        .findAll();
    return {for (final c in rows) c.slotIndex ?? 0};
  }

  /// Toggles the completion for [habit] on the device-local calendar date
  /// for [now], at slot [slotIndex].
  ///
  /// Inserts a new completion row when none exists for that
  /// `(habit, today, slotIndex)` tuple; otherwise removes the existing row
  /// (soft-deletes when sync is enabled, hard-deletes when it isn't).
  ///
  /// "Existing" matches a row whose `date` equals today AND whose
  /// `slotIndex` is either equal to [slotIndex] or null when [slotIndex]
  /// is 0 (Requirement 7.9: treat null as slot 0).
  Future<void> toggleSlot(
    Habit habit,
    int slotIndex, {
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
    final today = _midnightLocal(n);
    final candidates = await _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habit.id)
        .dateEqualTo(today)
        .deletedAtIsNull()
        .findAll();
    HabitCompletion? existing;
    for (final c in candidates) {
      if ((c.slotIndex ?? 0) == slotIndex) {
        existing = c;
        break;
      }
    }

    final syncEnabled = await SettingsService.instance.getSyncEnabled();

    if (existing != null) {
      if (syncEnabled) {
        // Soft-delete locally first so subsequent queries exclude this row
        // immediately, then enqueue the Firestore tombstone in the background.
        existing.deletedAt = DateTime.now();
        existing.updatedAt = existing.deletedAt!;
        await _isar.writeTxn(() async {
          await _isar.habitCompletions.put(existing!);
        });
        FirestoreSyncService.instance
            .enqueueDelete('habitCompletions', existing);
      } else {
        final id = existing.id;
        await _isar.writeTxn(() async {
          await _isar.habitCompletions.delete(id);
        });
      }
    } else {
      final c = HabitCompletion()
        ..cloudId = _uuid.v4()
        ..habitId = habit.id
        ..date = today
        ..completedAt = n
        ..updatedAt = n
        ..slotIndex = slotIndex;
      await _isar.writeTxn(() async {
        await _isar.habitCompletions.put(c);
      });
      if (syncEnabled) {
        FirestoreSyncService.instance.enqueueUpsert('habitCompletions', c);
      }
    }
  }

  /// Legacy single-slot toggle. Kept as a thin shim around [toggleSlot] so
  /// any callers that don't pass an explicit slot index continue to work
  /// against the slot-0 binary contract.
  Future<void> toggleToday(Habit habit) => toggleSlot(habit, 0);

  /// Returns the local midnight (00:00:00.000) for the calendar date of
  /// [t] in the device's current timezone. Used as the canonical `date`
  /// key for HabitCompletion rows.
  DateTime _midnightLocal(DateTime t) => DateTime(t.year, t.month, t.day);

  // ---------------------------------------------------------------------------
  // Queries (unchanged — read-only paths don't trigger sync hooks)
  // ---------------------------------------------------------------------------

  Future<bool> isCompletedToday(int habitId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final c = await _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habitId)
        .dateEqualTo(today)
        .deletedAtIsNull()
        .findFirst();
    return c != null;
  }

  Stream<List<Habit>> watchActive() {
    return _isar.habits
        .filter()
        .archivedEqualTo(false)
        .sortByCreatedAt()
        .watch(fireImmediately: true);
  }

  Future<int> currentStreak(int habitId) async {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    var streak = 0;
    while (true) {
      final c = await _isar.habitCompletions
          .filter()
          .habitIdEqualTo(habitId)
          .dateEqualTo(day)
          .deletedAtIsNull()
          .findFirst();
      if (c == null) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<List<bool>> last7Days(int habitId) async {
    final now = DateTime.now();
    final results = <bool>[];
    for (var i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final c = await _isar.habitCompletions
          .filter()
          .habitIdEqualTo(habitId)
          .dateEqualTo(day)
          .deletedAtIsNull()
          .findFirst();
      results.add(c != null);
    }
    return results;
  }

  Future<double> completionRate7Days(int habitId) async {
    final days = await last7Days(habitId);
    return days.where((d) => d).length / 7.0;
  }

  /// Completion rate over the last [days] days (0.0–1.0).
  Future<double> completionRateForDays(int habitId, int days) async {
    final now = DateTime.now();
    var completed = 0;
    for (var i = 0; i < days; i++) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final c = await _isar.habitCompletions
          .filter()
          .habitIdEqualTo(habitId)
          .dateEqualTo(day)
          .deletedAtIsNull()
          .findFirst();
      if (c != null) completed++;
    }
    return completed / days.toDouble();
  }

  /// Longest ever streak for a habit.
  Future<int> longestStreak(int habitId) async {
    final completions = await _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habitId)
        .deletedAtIsNull()
        .sortByDate()
        .findAll();
    if (completions.isEmpty) return 0;

    int longest = 1;
    int current = 1;
    for (var i = 1; i < completions.length; i++) {
      final prev = completions[i - 1].date;
      final curr = completions[i].date;
      final diff = curr.difference(prev).inDays;
      if (diff == 1) {
        current++;
        if (current > longest) longest = current;
      } else if (diff > 1) {
        current = 1;
      }
    }
    return longest;
  }

  /// Returns a map of {date → completed} for the given month.
  Future<Map<DateTime, bool>> monthCompletions(
      int habitId, int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
    final completions = await _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habitId)
        .dateBetween(start, end)
        .deletedAtIsNull()
        .findAll();
    final doneSet = {for (final c in completions) c.date};
    final result = <DateTime, bool>{};
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      result[d] = doneSet.contains(d);
    }
    return result;
  }

  /// Total completions ever for a habit.
  Future<int> totalCompletions(int habitId) async {
    return _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habitId)
        .deletedAtIsNull()
        .count();
  }

  /// Weekly summary: how many habits were completed each day this week
  /// (Mon–Sun), and total possible (active habits × 7).
  Future<({int completed, int total, List<int> dailyCounts})>
      weeklySummary(List<int> habitIds) async {
    if (habitIds.isEmpty) {
      return (completed: 0, total: 0, dailyCounts: List.filled(7, 0));
    }
    final now = DateTime.now();
    // Start of current week (Monday).
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: (now.weekday - 1)));
    final dailyCounts = List.filled(7, 0);
    var totalCompleted = 0;
    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      if (day.isAfter(now)) break;
      for (final id in habitIds) {
        final c = await _isar.habitCompletions
            .filter()
            .habitIdEqualTo(id)
            .dateEqualTo(day)
            .deletedAtIsNull()
            .findFirst();
        if (c != null) {
          dailyCounts[i]++;
          totalCompleted++;
        }
      }
    }
    final daysElapsed = now.weekday; // 1=Mon … 7=Sun
    final total = habitIds.length * daysElapsed;
    return (
      completed: totalCompleted,
      total: total,
      dailyCounts: dailyCounts,
    );
  }

  Future<void> rescheduleAll() async {
    final active = await _isar.habits
        .filter()
        .archivedEqualTo(false)
        .findAll();
    for (final h in active) {
      if (h.remindHour != null) {
        if (h.intervalMinutes > 0) {
          await NotificationService.instance.scheduleInterval(
            baseId: h.notificationId,
            title: '${h.emoji ?? '✅'} ${h.name}',
            body: "Time to check off your habit!",
            startHour: h.remindHour!,
            endHour: h.intervalEndHour,
            intervalMinutes: h.intervalMinutes,
          );
        } else {
          await NotificationService.instance.scheduleDaily(
            id: h.notificationId,
            title: '${h.emoji ?? '✅'} ${h.name}',
            body: "Time to check off your habit!",
            hour: h.remindHour!,
            minute: h.remindMinute ?? 0,
          );
        }
      }
    }
  }
}
