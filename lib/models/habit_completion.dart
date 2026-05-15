import 'package:isar/isar.dart';

part 'habit_completion.g.dart';

/// Records a single day's completion of a [Habit].
@collection
class HabitCompletion {
  Id id = Isar.autoIncrement;

  /// Reference to the parent [Habit] using its Isar auto-increment primary key.
  ///
  /// This local reference is preserved for backwards compatibility with
  /// existing in-app queries (Requirement 4.7); cloud sync separately
  /// serializes the parent's `cloudId` as `habitCloudId`.
  @Index(composite: [CompositeIndex('date')])
  late int habitId;

  /// Normalized to midnight local time so queries can match by day.
  @Index()
  late DateTime date;

  late DateTime completedAt;

  /// Last time this completion was mutated. Bumped by the repository on every
  /// write and used as the conflict-resolution key for cloud sync
  /// (last-write-wins by `updatedAt`).
  ///
  /// On the first launch after upgrade, [IsarMigrationService] sets this to
  /// [completedAt] when missing.
  @Index()
  late DateTime updatedAt;

  /// Stable cross-device document id (v4 UUID) used as the Firestore document
  /// id under `users/{ownerUid}/habitCompletions/{cloudId}`.
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

  /// Slot index for habits that fire multiple times per day.
  ///
  /// Closed range `[0, dailySlotCount - 1]` indexed from the earliest slot
  /// of the day. Null on legacy rows; readers MUST treat null as
  /// `slotIndex = 0` for backward compatibility (Requirement 7.9).
  int? slotIndex;
}
