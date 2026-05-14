import 'package:isar/isar.dart';

part 'habit.g.dart';

/// A daily habit the user wants to track (e.g. "Drink water", "Read 10 pages").
@collection
class Habit {
  Id id = Isar.autoIncrement;

  /// Stable cross-device document id (v4 UUID).
  ///
  /// Mirrors the Firestore document id at `users/{ownerUid}/habits/{cloudId}`.
  /// Defaults to an empty string for rows that pre-date this column; the
  /// `IsarMigrationService` backfills a UUID on first launch after upgrade,
  /// and the repository assigns one at create time for new rows.
  @Index(unique: true)
  String cloudId = '';

  late String name;

  /// Optional emoji shown on the card (e.g. "💧").
  String? emoji;

  /// ARGB32 color value from the palette.
  late int colorValue;

  late DateTime createdAt;

  /// Last time this row was mutated. Drives the last-write-wins conflict
  /// resolution policy in `FirestoreSyncService`. Bumped by repository writes
  /// to `DateTime.now()`. Migration sets it to `createdAt` for legacy rows.
  late DateTime updatedAt;

  /// Soft-delete marker. Non-null means the row has been deleted locally and
  /// is awaiting tombstone upload + remote sweep. Inbound tombstones with
  /// non-null `deletedAt` cause a hard delete on this device.
  DateTime? deletedAt;

  @Index()
  bool archived = false;

  /// Daily reminder hour (0–23). Null means no reminder.
  int? remindHour;

  /// Daily reminder minute (0–59).
  int? remindMinute;

  /// If > 0, this habit uses interval-based reminders (e.g. every 120 minutes)
  /// instead of a single daily reminder. The notifications fire from
  /// [remindHour] (start) to [intervalEndHour] (end) at this interval.
  int intervalMinutes = 0;

  /// End hour for interval reminders (0–23). Defaults to 22 (10 PM).
  int intervalEndHour = 22;

  /// Stable notification id derived from Isar id.
  late int notificationId;

  // ── Feature 2: Numeric Goals ──────────────────────────────────────────────

  /// Optional numeric target per day (e.g. 8 for "8 glasses of water").
  /// Null means the habit is a simple binary (done / not done).
  double? targetValue;

  /// Unit label for the target (e.g. "glasses", "km", "pages", "minutes").
  /// Only meaningful when [targetValue] is set.
  String? targetUnit;
}
