import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../../models/habit.dart';
import '../../models/habit_completion.dart';
import '../../models/memory_item.dart';
import '../../models/reminder.dart';
import '../database_service.dart';
import '../notification_service.dart';
import '../settings_service.dart';
import 'sync_codec.dart';

/// Immutable per-collection summary of records inserted by [RestoreFlow.run].
///
/// Counts only NEW inserts. Updates that were applied (because the remote
/// won the comparator) or skipped (because the local copy was newer) are
/// not counted: this number is what the Settings UI surfaces as
/// "imported X memories" on the post-sign-in toast (Requirement 9.6).
class RestoreSummary {
  const RestoreSummary({
    required this.memories,
    required this.reminders,
    required this.habits,
    required this.habitCompletions,
  });

  final int memories;
  final int reminders;
  final int habits;
  final int habitCompletions;

  /// Total newly-inserted records across all four collections.
  int get total => memories + reminders + habits + habitCompletions;
}

/// First-sign-in restore path.
///
/// [RestoreFlow.run] is invoked once when sign-in completes, before the
/// long-running snapshot listeners in [FirestoreSyncService] attach. It is
/// safe to run on any device — empty or populated — because every step
/// uses the same last-write-wins comparator as the live-listener path:
/// remote wins when its `updatedAt` is greater; on ties, the lexicographic
/// `(ownerUid, cloudId)` tuple decides (Requirements 7.1, 7.2, 9.5).
///
/// Ordering: `memories → reminders → habits → habitCompletions`. Reminders
/// resolve `memoryCloudId → memoryId` (Isar pk), and habit completions
/// resolve `habitCloudId → habitId`, so each parent collection is fully
/// restored before its children. A completion whose parent habit is
/// missing (e.g. tombstoned remotely while orphan completions still
/// exist) is silently dropped.
///
/// The conflict-resolution comparator is intentionally re-implemented
/// inline here rather than imported from [FirestoreSyncService]: that
/// service keeps it private (`_compare`) and the comparator is only
/// three lines, so duplication is cheaper than refactoring the engine
/// to expose it. Both call sites (the live `_applyRemoteUpsert` path
/// and this restore path) use identical semantics — keep them in sync.
class RestoreFlow {
  RestoreFlow._();

  /// Streams every non-tombstone document under
  /// `users/{uid}/{collection}` into Isar for the four synced
  /// collections, then re-derives notification schedules for active
  /// reminders and habits.
  ///
  /// On completion, advances `lastCloudSync` so the Settings UI shows
  /// the moment the restore finished (Requirement 9.6).
  static Future<RestoreSummary> run(String uid) async {
    final firestore = FirebaseFirestore.instance;

    // Step 1 — pull each collection in dependency order. Each per-row
    // insert assigns its device-local notificationId from the freshly
    // allocated Isar pk and re-puts inside the same writeTxn (mirrors
    // the repository's create flow).
    final memoryInserts = await _restoreMemories(firestore, uid);
    final reminderInserts = await _restoreReminders(firestore, uid);
    final habitInserts = await _restoreHabits(firestore, uid);
    final completionInserts = await _restoreCompletions(firestore, uid);

    // Step 2 — notification re-derivation pass (Requirements 9.2, 9.3).
    // notificationIds are already assigned during the per-row inserts
    // above; this pass walks Isar one more time and registers the
    // actual OS notifications for rows that are currently active.
    await _rescheduleReminders();
    await _rescheduleHabits();

    // Step 3 — bookkeeping.
    await SettingsService.instance.setLastCloudSync(DateTime.now());

    return RestoreSummary(
      memories: memoryInserts,
      reminders: reminderInserts,
      habits: habitInserts,
      habitCompletions: completionInserts,
    );
  }

  // ── Per-collection restore passes ──────────────────────────────────────

  static Future<int> _restoreMemories(
    FirebaseFirestore firestore,
    String uid,
  ) async {
    final isar = DatabaseService.instance.isar;
    final snap = await firestore.collection('users/$uid/memories').get();
    var inserted = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      // Tombstones don't restore (Requirement 9.1: "every non-tombstone
      // document"). The 30-day sweep handles their lifecycle separately.
      if (data['deletedAt'] != null) continue;

      final cloudId = (data['cloudId'] as String?) ?? doc.id;
      if (cloudId.isEmpty) continue;
      final remoteUpdatedAt = _readTimestamp(data['updatedAt']);
      if (remoteUpdatedAt == null) continue;

      try {
        final local = await isar.memoryItems.getByCloudId(cloudId);

        if (local == null) {
          // Fresh insert. `imagePath = null` per Requirement 9.4 — the
          // binary isn't synced and the on-device path on the source
          // device wouldn't resolve here anyway. `linkedIds` is left
          // empty: the codec doesn't translate `linkedCloudIds` back
          // (those references can dangle if their targets aren't
          // restored yet) and the user's next edit through the
          // repository recomputes them.
          final item = mapToMemory(data);
          await isar.writeTxn(() async {
            await isar.memoryItems.put(item);
          });
          inserted++;
          continue;
        }

        // Populated DB: route through the same last-write-wins comparator
        // as the live-listener path so a re-run of the restore is
        // idempotent and any concurrent local edits aren't clobbered
        // (Requirement 9.5).
        if (!_remoteWins(
          remoteUpdatedAt: remoteUpdatedAt,
          remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
          remoteCloudId: cloudId,
          localUpdatedAt: local.updatedAt,
          localOwnerUid: uid,
          localCloudId: local.cloudId,
        )) {
          continue;
        }

        // Remote wins: overwrite preserving the existing Isar pk and the
        // device-local fields (`imagePath`, `searchTokens`, `linkedIds`,
        // `reminderPromptHandled`). These mirror the merge in
        // `FirestoreSyncService._applyRemoteMemory`.
        final merged = mapToMemory(data)
          ..id = local.id
          ..searchTokens = List<String>.from(local.searchTokens)
          ..linkedIds = List<int>.from(local.linkedIds)
          ..reminderPromptHandled = local.reminderPromptHandled;
        await isar.writeTxn(() async {
          await isar.memoryItems.put(merged);
        });
      } catch (e) {
        debugPrint('[RestoreFlow] memory $cloudId failed: $e');
      }
    }

    return inserted;
  }

  static Future<int> _restoreReminders(
    FirebaseFirestore firestore,
    String uid,
  ) async {
    final isar = DatabaseService.instance.isar;
    final snap = await firestore.collection('users/$uid/reminders').get();
    var inserted = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['deletedAt'] != null) continue;

      final cloudId = (data['cloudId'] as String?) ?? doc.id;
      if (cloudId.isEmpty) continue;
      final remoteUpdatedAt = _readTimestamp(data['updatedAt']);
      if (remoteUpdatedAt == null) continue;

      try {
        // Resolve `memoryCloudId → memoryId` against the just-restored
        // memories collection. Standalone reminders (no parent memory)
        // and reminders whose parent isn't present locally fall through
        // with `memoryIsarId == null`.
        final memoryCloudId = data['memoryCloudId'] as String?;
        int? memoryIsarId;
        if (memoryCloudId != null && memoryCloudId.isNotEmpty) {
          final parent = await isar.memoryItems.getByCloudId(memoryCloudId);
          memoryIsarId = parent?.id;
        }

        final local = await isar.reminders.getByCloudId(cloudId);

        if (local == null) {
          // Fresh insert with a placeholder notificationId; we re-derive
          // it from the assigned Isar id and re-put inside the same
          // writeTxn (Requirement 6.6 / Property 13).
          final item = mapToReminder(
            data,
            memoryIsarId: memoryIsarId,
            notificationId: 0,
          );
          await isar.writeTxn(() async {
            final id = await isar.reminders.put(item);
            item.notificationId = id & 0x7FFFFFFF;
            await isar.reminders.put(item);
          });
          inserted++;
          continue;
        }

        if (!_remoteWins(
          remoteUpdatedAt: remoteUpdatedAt,
          remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
          remoteCloudId: cloudId,
          localUpdatedAt: local.updatedAt,
          localOwnerUid: uid,
          localCloudId: local.cloudId,
        )) {
          continue;
        }

        final merged = mapToReminder(
          data,
          memoryIsarId: memoryIsarId,
          notificationId: local.notificationId,
        )..id = local.id;
        await isar.writeTxn(() async {
          await isar.reminders.put(merged);
        });
      } catch (e) {
        debugPrint('[RestoreFlow] reminder $cloudId failed: $e');
      }
    }

    return inserted;
  }

  static Future<int> _restoreHabits(
    FirebaseFirestore firestore,
    String uid,
  ) async {
    final isar = DatabaseService.instance.isar;
    final snap = await firestore.collection('users/$uid/habits').get();
    var inserted = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['deletedAt'] != null) continue;

      final cloudId = (data['cloudId'] as String?) ?? doc.id;
      if (cloudId.isEmpty) continue;
      final remoteUpdatedAt = _readTimestamp(data['updatedAt']);
      if (remoteUpdatedAt == null) continue;

      try {
        final local = await isar.habits.getByCloudId(cloudId);

        if (local == null) {
          // Fresh insert: notificationId = (id + 100000) & 0x7FFFFFFF
          // matches `HabitRepository.add` and `_applyRemoteHabit`.
          final item = mapToHabit(data, notificationId: 0);
          await isar.writeTxn(() async {
            final id = await isar.habits.put(item);
            item.notificationId = (id + 100000) & 0x7FFFFFFF;
            await isar.habits.put(item);
          });
          inserted++;
          continue;
        }

        if (!_remoteWins(
          remoteUpdatedAt: remoteUpdatedAt,
          remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
          remoteCloudId: cloudId,
          localUpdatedAt: local.updatedAt,
          localOwnerUid: uid,
          localCloudId: local.cloudId,
        )) {
          continue;
        }

        final merged = mapToHabit(data, notificationId: local.notificationId)
          ..id = local.id;
        await isar.writeTxn(() async {
          await isar.habits.put(merged);
        });
      } catch (e) {
        debugPrint('[RestoreFlow] habit $cloudId failed: $e');
      }
    }

    return inserted;
  }

  static Future<int> _restoreCompletions(
    FirebaseFirestore firestore,
    String uid,
  ) async {
    final isar = DatabaseService.instance.isar;
    final snap =
        await firestore.collection('users/$uid/habitCompletions').get();
    var inserted = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['deletedAt'] != null) continue;

      final cloudId = (data['cloudId'] as String?) ?? doc.id;
      if (cloudId.isEmpty) continue;
      final remoteUpdatedAt = _readTimestamp(data['updatedAt']);
      if (remoteUpdatedAt == null) continue;

      try {
        // Resolve `habitCloudId → habitId`. Skip orphan completions —
        // `HabitCompletion.habitId` is non-nullable and the repository
        // would refuse to insert a completion without a parent habit.
        final habitCloudId = data['habitCloudId'] as String?;
        if (habitCloudId == null || habitCloudId.isEmpty) continue;
        final parent = await isar.habits.getByCloudId(habitCloudId);
        if (parent == null) continue;

        final local = await isar.habitCompletions.getByCloudId(cloudId);

        if (local == null) {
          final item = mapToCompletion(data, habitIsarId: parent.id);
          await isar.writeTxn(() async {
            await isar.habitCompletions.put(item);
          });
          inserted++;
          continue;
        }

        if (!_remoteWins(
          remoteUpdatedAt: remoteUpdatedAt,
          remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
          remoteCloudId: cloudId,
          localUpdatedAt: local.updatedAt,
          localOwnerUid: uid,
          localCloudId: local.cloudId,
        )) {
          continue;
        }

        final merged = mapToCompletion(data, habitIsarId: parent.id)
          ..id = local.id;
        await isar.writeTxn(() async {
          await isar.habitCompletions.put(merged);
        });
      } catch (e) {
        debugPrint('[RestoreFlow] completion $cloudId failed: $e');
      }
    }

    return inserted;
  }

  // ── Notification re-derivation pass ────────────────────────────────────

  /// Schedules a one-shot notification for every active reminder
  /// (`completed == false && remindAt > now`). Soft-deleted rows are
  /// excluded — the local DB may carry transient `deletedAt` markers
  /// while their tombstone uploads are still in flight.
  static Future<void> _rescheduleReminders() async {
    final isar = DatabaseService.instance.isar;
    final now = DateTime.now();
    final reminders = await isar.reminders.where().findAll();

    for (final Reminder r in reminders) {
      if (r.deletedAt != null) continue;
      if (r.completed) continue;
      if (!r.remindAt.isAfter(now)) continue;
      try {
        await NotificationService.instance.schedule(
          id: r.notificationId,
          title: 'Mnemo reminder',
          body: r.text,
          when: r.remindAt,
        );
      } catch (e) {
        debugPrint('[RestoreFlow] schedule reminder ${r.cloudId} failed: $e');
      }
    }
  }

  /// Schedules notifications for every active habit
  /// (`archived == false && remindHour != null`). Habits with
  /// `intervalMinutes > 0` get the interval fan-out; the rest get a
  /// single daily notification — matches `HabitRepository.add` and
  /// `_applyRemoteHabit`.
  static Future<void> _rescheduleHabits() async {
    final isar = DatabaseService.instance.isar;
    final habits = await isar.habits.where().findAll();

    for (final Habit h in habits) {
      if (h.deletedAt != null) continue;
      if (h.archived) continue;
      if (h.remindHour == null) continue;
      try {
        if (h.intervalMinutes > 0) {
          await NotificationService.instance.scheduleInterval(
            baseId: h.notificationId,
            title: '${h.emoji ?? '✅'} ${h.name}',
            body: 'Time to check off your habit!',
            startHour: h.remindHour!,
            endHour: h.intervalEndHour,
            intervalMinutes: h.intervalMinutes,
          );
        } else {
          await NotificationService.instance.scheduleDaily(
            id: h.notificationId,
            title: '${h.emoji ?? '✅'} ${h.name}',
            body: 'Time to check off your habit!',
            hour: h.remindHour!,
            minute: h.remindMinute ?? 0,
          );
        }
      } catch (e) {
        debugPrint('[RestoreFlow] schedule habit ${h.cloudId} failed: $e');
      }
    }
  }
}

// ── Module-private helpers ────────────────────────────────────────────────

/// Conflict resolver: last-write-wins on `updatedAt`, deterministic
/// tie-break on lexicographic `(ownerUid, cloudId)`. Mirrors
/// `FirestoreSyncService._compare` — keep the two in sync.
bool _remoteWins({
  required DateTime remoteUpdatedAt,
  required String remoteOwnerUid,
  required String remoteCloudId,
  required DateTime localUpdatedAt,
  required String localOwnerUid,
  required String localCloudId,
}) {
  final cmp = remoteUpdatedAt.compareTo(localUpdatedAt);
  if (cmp > 0) return true;
  if (cmp < 0) return false;
  final r = '$remoteOwnerUid|$remoteCloudId';
  final l = '$localOwnerUid|$localCloudId';
  return r.compareTo(l) > 0;
}

DateTime? _readTimestamp(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}
