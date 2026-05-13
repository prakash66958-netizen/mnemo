import 'dart:io' as java_io;

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../models/habit.dart';
import '../models/habit_completion.dart';
import '../models/memory_item.dart';
import '../models/reminder.dart';

/// Thin singleton wrapper around the Isar database.
///
/// Opens a single instance for the lifetime of the app. All feature-level
/// repositories read [instance.isar] to construct queries.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Isar? _isar;

  Isar get isar {
    final i = _isar;
    if (i == null) {
      throw StateError(
        'DatabaseService.open() must be called before accessing isar.',
      );
    }
    return i;
  }

  bool get isOpen => _isar != null && _isar!.isOpen;

  /// Opens the Isar database. Safe to call multiple times.
  ///
  /// If the schema has changed since the last install (e.g. new collections
  /// like Habit/HabitCompletion were added), Isar 3 will throw on open. We
  /// catch that, delete the old DB file, and re-open with the new schema.
  Future<void> open() async {
    if (isOpen) return;
    final dir = await getApplicationDocumentsDirectory();
    final schemas = [
      MemoryItemSchema,
      ReminderSchema,
      HabitSchema,
      HabitCompletionSchema,
    ];
    try {
      _isar = await Isar.open(
        schemas,
        directory: dir.path,
        name: AppConstants.dbName,
        inspector: false,
      );
    } catch (_) {
      // Schema mismatch or corrupt DB — delete and retry.
      // Delete all possible Isar files for this DB name.
      final basePath = '${dir.path}/${AppConstants.dbName}';
      for (final ext in ['.isar', '.isar.lock']) {
        try {
          final f = java_io.File('$basePath$ext');
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      // Retry open — this time it's a fresh DB.
      _isar = await Isar.open(
        schemas,
        directory: dir.path,
        name: AppConstants.dbName,
        inspector: false,
      );
    }
  }

  Future<void> close() async {
    final i = _isar;
    if (i != null && i.isOpen) {
      await i.close();
    }
    _isar = null;
  }

  /// Wipes every collection. Used by the "Clear all data" setting.
  Future<void> clearAll() async {
    await isar.writeTxn(() async {
      await isar.memoryItems.clear();
      await isar.reminders.clear();
      await isar.habits.clear();
      await isar.habitCompletions.clear();
    });
  }
}
