import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../core/category.dart';
import '../models/memory_item.dart';
import '../models/reminder.dart';
import 'database_service.dart';
import 'firestore_sync_service.dart';
import 'memory_repository.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// Direction of a sync hook fan-out: a write that should propagate as an
/// upsert versus one that should propagate as a tombstone.
enum _MutationKind { upsert, delete }

/// Repository for creating, updating and listing reminders.
///
/// All reminder writes also (de)register the corresponding local notification
/// so the "schedule database" and "OS alarm queue" stay in sync. Each
/// mutating method assigns / bumps the cloud-sync metadata fields
/// (`cloudId`, `updatedAt`) before persisting and emits a sync hook after
/// the Isar transaction commits, so the [FirestoreSyncService] mirrors the
/// change to `users/{ownerUid}/reminders/{cloudId}` whenever
/// `Sync_Enabled` is true.
class ReminderRepository {
  ReminderRepository._();
  static final ReminderRepository instance = ReminderRepository._();

  static const Uuid _uuid = Uuid();

  Isar get _isar => DatabaseService.instance.isar;

  Future<Reminder> create({
    required String text,
    required DateTime remindAt,
    int? memoryId,
  }) async {
    // If this reminder isn't tied to an existing memory, drop a companion
    // MemoryItem into the "reminder" category so the reminder's text is
    // browsable from the Categories tab alongside other saved content.
    int? effectiveMemoryId = memoryId;
    if (effectiveMemoryId == null) {
      final companion = await MemoryRepository.instance.createTextMemory(
        content: text,
        forcedCategory: MemoryCategory.reminder,
        source: MemorySource.text,
      );
      effectiveMemoryId = companion.id;
    }

    final now = DateTime.now();
    final reminder = Reminder()
      ..memoryId = effectiveMemoryId
      ..text = text
      ..remindAt = remindAt
      ..createdAt = now
      ..updatedAt = now
      ..cloudId = _uuid.v4()
      ..notificationId = 0; // patched below once we have the Isar id

    await _isar.writeTxn(() async {
      final id = await _isar.reminders.put(reminder);
      reminder.notificationId = id & 0x7FFFFFFF;
      await _isar.reminders.put(reminder);
    });

    await NotificationService.instance.schedule(
      id: reminder.notificationId,
      title: 'Mnemo reminder',
      body: text,
      when: remindAt,
    );
    await _emitSync(_MutationKind.upsert, reminder);
    return reminder;
  }

  Future<void> update(Reminder reminder) async {
    // Cancel & re-schedule to pick up a potentially new time/body.
    await NotificationService.instance.cancel(reminder.notificationId);
    reminder.updatedAt = DateTime.now();
    await _isar.writeTxn(() async {
      await _isar.reminders.put(reminder);
    });
    if (!reminder.completed && reminder.remindAt.isAfter(DateTime.now())) {
      await NotificationService.instance.schedule(
        id: reminder.notificationId,
        title: 'Mnemo reminder',
        body: reminder.text,
        when: reminder.remindAt,
      );
    }
    await _emitSync(_MutationKind.upsert, reminder);
  }

  Future<void> complete(Reminder reminder) async {
    reminder.completed = true;
    reminder.updatedAt = DateTime.now();
    await NotificationService.instance.cancel(reminder.notificationId);
    await _isar.writeTxn(() async {
      await _isar.reminders.put(reminder);
    });
    await _emitSync(_MutationKind.upsert, reminder);
  }

  Future<void> delete(Reminder reminder) async {
    await NotificationService.instance.cancel(reminder.notificationId);
    // The reminder may have a companion memory created at reminder-creation
    // time. Both rows are independently synced records, so when sync is on
    // we soft-delete each through the engine; when sync is off we hard
    // delete both locally (existing behavior).
    final memoryId = reminder.memoryId;
    if (await SettingsService.instance.getSyncEnabled()) {
      FirestoreSyncService.instance.enqueueDelete('reminders', reminder);
      if (memoryId != null) {
        final companion = await _isar.memoryItems.get(memoryId);
        if (companion != null) {
          FirestoreSyncService.instance.enqueueDelete('memories', companion);
        }
      }
    } else {
      // Hard-delete locally (existing flow): also remove the companion
      // memory so the reminder disappears from the Inbox and the Reminder
      // category tile.
      await _isar.writeTxn(() async {
        await _isar.reminders.delete(reminder.id);
        if (memoryId != null) {
          await _isar.memoryItems.delete(memoryId);
        }
      });
    }
  }

  /// Upcoming (not completed, future) + overdue (not completed, past).
  Stream<List<Reminder>> watchAllActive() {
    return _isar.reminders
        .filter()
        .completedEqualTo(false)
        .sortByRemindAt()
        .watch(fireImmediately: true);
  }

  Stream<List<Reminder>> watchCompleted() {
    return _isar.reminders
        .filter()
        .completedEqualTo(true)
        .sortByRemindAtDesc()
        .watch(fireImmediately: true);
  }

  Future<List<Reminder>> getByMemory(int memoryId) {
    return _isar.reminders
        .filter()
        .memoryIdEqualTo(memoryId)
        .findAll();
  }

  /// On app startup, re-register notifications for any active reminders. The
  /// OS may have dropped them after reboot / app reinstall.
  ///
  /// Reminders whose [Reminder.remindAt] has already passed and that have not
  /// yet been marked `fired` are shown immediately (so the user still sees
  /// alarms they missed while the app/device was off). We then persist
  /// `fired = true` so we don't re-notify on the next launch.
  Future<void> rescheduleAll() async {
    final active = await _isar.reminders
        .filter()
        .completedEqualTo(false)
        .findAll();
    final now = DateTime.now();
    final missed = <Reminder>[];
    for (final r in active) {
      if (r.remindAt.isAfter(now)) {
        await NotificationService.instance.schedule(
          id: r.notificationId,
          title: 'Mnemo reminder',
          body: r.text,
          when: r.remindAt,
        );
      } else if (!r.fired) {
        await NotificationService.instance.showNow(
          id: r.notificationId,
          title: 'Mnemo reminder',
          body: r.text,
        );
        r.fired = true;
        r.updatedAt = DateTime.now();
        missed.add(r);
      }
    }
    if (missed.isNotEmpty) {
      await _isar.writeTxn(() async {
        for (final r in missed) {
          await _isar.reminders.put(r);
        }
      });
      for (final r in missed) {
        await _emitSync(_MutationKind.upsert, r);
      }
    }
  }

  /// Fan out a Reminder mutation to the cloud sync engine. No-ops when the
  /// device is signed-out (Requirement 3.2) so the in-process behavior is
  /// bit-identical to the pre-sync code path.
  Future<void> _emitSync(_MutationKind kind, Reminder r) async {
    if (!await SettingsService.instance.getSyncEnabled()) return;
    if (kind == _MutationKind.upsert) {
      FirestoreSyncService.instance.enqueueUpsert('reminders', r);
    } else {
      FirestoreSyncService.instance.enqueueDelete('reminders', r);
    }
  }
}
