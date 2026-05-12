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

  /// Has the notification fired at least once.
  bool fired = false;

  /// User dismissed / completed the reminder. We keep it around for history.
  @Index()
  bool completed = false;

  /// The notification id used when scheduling with flutter_local_notifications.
  /// Kept so we can cancel if the reminder is edited or deleted.
  late int notificationId;
}
