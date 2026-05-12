import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../models/habit.dart';
import '../models/habit_completion.dart';
import 'database_service.dart';
import 'notification_service.dart';

/// Repository for creating, updating, and querying habits and their daily
/// completions. All writes also manage the corresponding daily notification.
class HabitRepository {
  HabitRepository._();
  static final HabitRepository instance = HabitRepository._();

  Isar get _isar => DatabaseService.instance.isar;

  Future<Habit> create({
    required String name,
    String? emoji,
    required Color color,
    TimeOfDay? remindAt,
  }) async {
    final now = DateTime.now();
    final habit = Habit()
      ..name = name
      ..emoji = emoji
      ..colorValue = color.toARGB32()
      ..createdAt = now
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
    return habit;
  }

  Future<void> update(Habit habit) async {
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
  }

  Future<void> delete(Habit habit) async {
    await NotificationService.instance.cancel(habit.notificationId);
    await _isar.writeTxn(() async {
      await _isar.habitCompletions
          .filter()
          .habitIdEqualTo(habit.id)
          .deleteAll();
      await _isar.habits.delete(habit.id);
    });
  }

  Future<void> archive(Habit habit) async {
    habit.archived = !habit.archived;
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
  }

  Future<void> toggleToday(Habit habit) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existing = await _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habit.id)
        .dateEqualTo(today)
        .findFirst();

    await _isar.writeTxn(() async {
      if (existing != null) {
        await _isar.habitCompletions.delete(existing.id);
      } else {
        final c = HabitCompletion()
          ..habitId = habit.id
          ..date = today
          ..completedAt = now;
        await _isar.habitCompletions.put(c);
      }
    });
  }

  Future<bool> isCompletedToday(int habitId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final c = await _isar.habitCompletions
        .filter()
        .habitIdEqualTo(habitId)
        .dateEqualTo(today)
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
          .findFirst();
      results.add(c != null);
    }
    return results;
  }

  Future<double> completionRate7Days(int habitId) async {
    final days = await last7Days(habitId);
    return days.where((d) => d).length / 7.0;
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
