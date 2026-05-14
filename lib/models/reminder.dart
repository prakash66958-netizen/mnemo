import 'package:isar/isar.dart';

part 'reminder.g.dart';

/// A scheduled reminder attached (optionally) to a saved memory.
///
/// We keep reminders as a separate collection so the user can have standalone
/// reminders (not tied to any memory) and so scheduled notifications can be
/// rescheduled on app launch cheaply.
@collection
class Reminder {
  Id id = Isar.autoIncrement;

  /// Optional link to the source memory that prompted this reminder.
  @Index()
  int? memoryId;

  late String text;

  /// Scheduled fire time (in the device's local timezone).
  @Index()
  late DateTime remindAt;

  @Index()
  late DateTime createdAt;

  /// Last time this reminder was mutated. Bumped by the repository on every
  /// write and used as the conflict-resolution key for cloud sync
  /// (last-write-wins by `updatedAt`).
  ///
  /// On the first launch after upgrade, [IsarMigrationService] sets this to
  /// [createdAt] when missing.
  @Index()
  late DateTime updatedAt;

  /// Has the notification fired at least once.
  bool fired = false;

  /// User dismissed / completed the reminder. We keep it around for history.
  @Index()
  bool completed = false;

  /// The notification id used when scheduling with flutter_local_notifications.
  /// Kept so we can cancel if the reminder is edited or deleted.
  late int notificationId;

  /// Stable cross-device document id (v4 UUID) used as the Firestore document
  /// id under `users/{ownerUid}/reminders/{cloudId}`.
  ///
  /// Defaults to the empty string so existing records read back from Isar
  /// before the migration runs are well-formed; the repository assigns a UUID
  /// at create time and [IsarMigrationService] backfills any pre-existing
  /// records on first launch.
  @Index(unique: true)
  String cloudId = '';

  /// Soft-delete marker. Non-null while the row is awaiting tombstone
  /// acknowledgement from Firestore; null for live records.
  DateTime? deletedAt;
}
