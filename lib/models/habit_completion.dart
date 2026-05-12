import 'package:isar/isar.dart';

part 'habit_completion.g.dart';

/// Records a single day's completion of a [Habit].
@collection
class HabitCompletion {
  Id id = Isar.autoIncrement;

  @Index(composite: [CompositeIndex('date')])
  late int habitId;

  /// Normalized to midnight local time so queries can match by day.
  @Index()
  late DateTime date;

  late DateTime completedAt;
}
