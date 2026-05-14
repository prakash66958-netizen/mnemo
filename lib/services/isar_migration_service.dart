import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/habit.dart';
import '../models/habit_completion.dart';
import '../models/memory_item.dart';
import '../models/reminder.dart';
import 'database_service.dart';

/// One-time, idempotent local migration that backfills cross-device document
/// ids and `updatedAt` timestamps for legacy rows produced before the
/// firestore-backup-sync schema landed.
///
/// The service:
///   1. Walks each of the four synced Isar collections (`MemoryItem`,
///      `Reminder`, `Habit`, `HabitCompletion`).
///   2. Assigns a v4 UUID to any row whose `cloudId` is empty.
///   3. Sets `updatedAt = createdAt` when the row's `updatedAt` is missing
///      (the `late` field is uninitialized or carries the Isar-default
///      epoch-zero sentinel). `HabitCompletion` has no `createdAt`, so
///      `completedAt` is used as the source instead.
///   4. Writes dirty rows back inside a single `writeTxn` per collection.
///   5. Removes the legacy `pref_last_drive_sync` SharedPreferences key
///      (Requirement 2.7); the cloud-sync replacement lives at
///      `pref_last_cloud_sync` and is written by `SettingsService`.
///
/// The migration is **idempotent**: a row that already carries a non-empty
/// `cloudId` and a non-zero `updatedAt` is skipped, so the second and
/// subsequent launches produce an empty dirty set and zero Isar writes.
///
/// All per-row work runs inside a try/catch so a single corrupt row never
/// aborts the whole migration — the row is logged-by-omission and the
/// migration continues with the next one.
class IsarMigrationService {
  IsarMigrationService._();
  static final IsarMigrationService instance = IsarMigrationService._();

  /// SharedPreferences key written by the now-removed Google Drive backup.
  /// Tracked here as a string literal rather than a constant on purpose:
  /// `AppConstants` no longer exposes it, and the migration is the only
  /// place that needs to refer to the legacy key.
  static const String _legacyDriveSyncKey = 'pref_last_drive_sync';

  final Uuid _uuid = const Uuid();

  /// Run the one-time migration. Safe to call on every app launch — second
  /// and subsequent invocations are no-ops because the dirty-row test is
  /// stable under repeat application.
  Future<void> run() async {
    final isar = DatabaseService.instance.isar;

    await _backfill<MemoryItem>(
      isar: isar,
      col: isar.memoryItems,
      getCloudId: (m) => m.cloudId,
      setCloudId: (m, v) => m.cloudId = v,
      getUpdatedAt: (m) => m.updatedAt,
      setUpdatedAt: (m, v) => m.updatedAt = v,
      updatedAtFallback: (m) => m.createdAt,
    );

    await _backfill<Reminder>(
      isar: isar,
      col: isar.reminders,
      getCloudId: (r) => r.cloudId,
      setCloudId: (r, v) => r.cloudId = v,
      getUpdatedAt: (r) => r.updatedAt,
      setUpdatedAt: (r, v) => r.updatedAt = v,
      updatedAtFallback: (r) => r.createdAt,
    );

    await _backfill<Habit>(
      isar: isar,
      col: isar.habits,
      getCloudId: (h) => h.cloudId,
      setCloudId: (h, v) => h.cloudId = v,
      getUpdatedAt: (h) => h.updatedAt,
      setUpdatedAt: (h, v) => h.updatedAt = v,
      updatedAtFallback: (h) => h.createdAt,
    );

    await _backfill<HabitCompletion>(
      isar: isar,
      col: isar.habitCompletions,
      getCloudId: (c) => c.cloudId,
      setCloudId: (c, v) => c.cloudId = v,
      getUpdatedAt: (c) => c.updatedAt,
      setUpdatedAt: (c, v) => c.updatedAt = v,
      // HabitCompletion has no createdAt; completedAt is the closest
      // wall-clock timestamp that already exists on every legacy row.
      updatedAtFallback: (c) => c.completedAt,
    );

    // Drop the legacy Google Drive sync timestamp. The cloud-sync replacement
    // (`pref_last_cloud_sync`) is written separately by SettingsService once
    // sync acks land.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyDriveSyncKey);
  }

  /// Reads every row of [col], assigns missing `cloudId`s, backfills missing
  /// `updatedAt`s, and writes the dirty subset back inside a single
  /// `writeTxn`.
  ///
  /// `getUpdatedAt` reads a `late DateTime` field. On legacy rows the field
  /// may be uninitialized (the read throws `LateInitializationError`) or
  /// populated with the type default (epoch-zero). Both shapes are treated
  /// as "missing" and resolved via [updatedAtFallback].
  Future<void> _backfill<T>({
    required Isar isar,
    required IsarCollection<T> col,
    required String Function(T) getCloudId,
    required void Function(T, String) setCloudId,
    required DateTime Function(T) getUpdatedAt,
    required void Function(T, DateTime) setUpdatedAt,
    required DateTime Function(T) updatedAtFallback,
  }) async {
    final all = await col.where().findAll();
    final dirty = <T>[];

    for (final item in all) {
      try {
        var changed = false;

        if (getCloudId(item).isEmpty) {
          setCloudId(item, _uuid.v4());
          changed = true;
        }

        if (_isMissingTimestamp(() => getUpdatedAt(item))) {
          // Wrap the fallback read in the same defensive try so a corrupt
          // `createdAt`/`completedAt` doesn't abort the migration; in that
          // case we fall back to `DateTime.now()` so the row still becomes
          // eligible for sync rather than being dropped.
          DateTime fallback;
          try {
            fallback = updatedAtFallback(item);
          } catch (_) {
            fallback = DateTime.now();
          }
          setUpdatedAt(item, fallback);
          changed = true;
        }

        if (changed) dirty.add(item);
      } catch (_) {
        // A single corrupt row should not block the whole migration.
        // Skip it and keep walking; the row will simply remain unsynced
        // until the user next edits it through the repository (which
        // will rewrite both fields anyway).
      }
    }

    if (dirty.isNotEmpty) {
      await isar.writeTxn(() async {
        await col.putAll(dirty);
      });
    }
  }

  /// True when a `late DateTime` getter is effectively unset:
  /// either the `late` initializer throws because the field was never
  /// assigned, or Isar deserialized a missing column to the type default
  /// (`DateTime.fromMillisecondsSinceEpoch(0)`).
  bool _isMissingTimestamp(DateTime Function() read) {
    DateTime current;
    try {
      current = read();
    } catch (_) {
      return true;
    }
    return current.millisecondsSinceEpoch <= 0;
  }
}
