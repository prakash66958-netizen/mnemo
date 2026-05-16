import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/habit.dart';
import '../../models/habit_completion.dart';
import '../../models/memory_item.dart';
import '../../models/reminder.dart';

/// Pure encode/decode functions between local Isar models and the
/// Firestore-bound `Map<String, dynamic>` representation.
///
/// Design contract:
///
/// * No class state, no Isar lookups, no I/O. Every reference translation
///   (`linkedIds → linkedCloudIds`, `memoryId → memoryCloudId`, `habitId →
///   habitCloudId`) is performed by the caller and threaded through the
///   function arguments. This keeps the codec pure and trivially
///   property-testable.
/// * `Device_Local_Field`s — `MemoryItem.imagePath`, `Reminder.notificationId`,
///   `Habit.notificationId` — are stripped on encode and re-derived from
///   caller-supplied values on decode.
/// * Every encoded map carries the common envelope: `cloudId`, `ownerUid`,
///   `createdAt`, `updatedAt`, `deletedAt`. `DateTime` values are stored as
///   Firestore `Timestamp`s; `null` is preserved as `null` for `deletedAt`.
/// * `decode(encode(x))` equals `x` modulo Device_Local_Fields and
///   reference fields whose translation lives outside the codec
///   (`linkedIds` for memories; `memoryId`/`habitId` for reminders/habit
///   completions).

// ────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ────────────────────────────────────────────────────────────────────────────

DateTime _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.parse(value);
  throw ArgumentError(
    'sync_codec: cannot convert value of type ${value.runtimeType} '
    'to DateTime ($value)',
  );
}

DateTime? _toDateOrNull(Object? value) =>
    value == null ? null : _toDate(value);

Timestamp? _toTimestampOrNull(DateTime? dt) =>
    dt == null ? null : Timestamp.fromDate(dt);

List<String> _toStringList(Object? value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return <String>[];
}

Map<String, dynamic> _envelope({
  required String cloudId,
  required String ownerUid,
  required DateTime createdAt,
  required DateTime updatedAt,
  required DateTime? deletedAt,
}) =>
    <String, dynamic>{
      'cloudId': cloudId,
      'ownerUid': ownerUid,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'deletedAt': _toTimestampOrNull(deletedAt),
    };

// ────────────────────────────────────────────────────────────────────────────
// MemoryItem
// ────────────────────────────────────────────────────────────────────────────

/// Encodes [m] for `users/{ownerUid}/memories/{m.cloudId}`.
///
/// `imagePath` and the local-only `searchTokens` / `reminderPromptHandled`
/// fields are intentionally excluded — they are device-local and re-derived
/// on the receiving device.
///
/// [linkedCloudIds] is the caller-resolved translation of `m.linkedIds`
/// (Isar primary keys → cloud ids); the codec performs no lookups itself.
Map<String, dynamic> memoryToMap(
  MemoryItem m, {
  required String ownerUid,
  List<String> linkedCloudIds = const <String>[],
}) {
  return <String, dynamic>{
    ..._envelope(
      cloudId: m.cloudId,
      ownerUid: ownerUid,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
      deletedAt: m.deletedAt,
    ),
    'title': m.title,
    'content': m.content,
    'rawUrl': m.rawUrl,
    'sourceType': m.sourceType,
    'categoryId': m.categoryId,
    'tags': List<String>.from(m.tags),
    'pinned': m.pinned,
    'archived': m.archived,
    'hasPromise': m.hasPromise,
    'colorValue': m.colorValue,
    'linkedCloudIds': List<String>.from(linkedCloudIds),
    'checklistMode': m.checklistMode,
    'checklistData': m.checklistData,
    'locationName': m.locationName,
    'locationUrl': m.locationUrl,
    'doneInInbox': m.doneInInbox,
    'doneAt': _toTimestampOrNull(m.doneAt),
  };
}

/// Decodes a Firestore document body into a `MemoryItem`.
///
/// `imagePath` is always set to `null` (image features removed).
/// `linkedIds` is left empty — the caller
/// resolves `map['linkedCloudIds']` to local Isar primary keys after decode.
/// `searchTokens` is left empty so it is recomputed on the next insert path.
MemoryItem mapToMemory(
  Map<String, dynamic> map,
) {
  return MemoryItem()
    ..cloudId = (map['cloudId'] as String?) ?? ''
    ..title = map['title'] as String?
    ..content = (map['content'] as String?) ?? ''
    ..rawUrl = map['rawUrl'] as String?
    ..imagePath = null
    ..sourceType = (map['sourceType'] as String?) ?? ''
    ..categoryId = (map['categoryId'] as String?) ?? ''
    ..tags = _toStringList(map['tags'])
    ..searchTokens = const <String>[]
    ..createdAt = _toDate(map['createdAt'])
    ..updatedAt = _toDate(map['updatedAt'])
    ..pinned = map['pinned'] == true
    ..archived = map['archived'] == true
    ..hasPromise = map['hasPromise'] == true
    ..colorValue = map['colorValue'] as int?
    ..linkedIds = const <int>[]
    ..checklistMode = map['checklistMode'] == true
    ..checklistData = (map['checklistData'] as String?) ?? ''
    ..locationName = map['locationName'] as String?
    ..locationUrl = map['locationUrl'] as String?
    ..doneInInbox = map['doneInInbox'] == true
    ..doneAt = _toDateOrNull(map['doneAt'])
    ..deletedAt = _toDateOrNull(map['deletedAt']);
}

// ────────────────────────────────────────────────────────────────────────────
// Reminder
// ────────────────────────────────────────────────────────────────────────────

/// Encodes [r] for `users/{ownerUid}/reminders/{r.cloudId}`.
///
/// `notificationId` is stripped (Device_Local_Field). [memoryCloudId] is
/// the caller-resolved translation of `r.memoryId` (Isar pk → cloud id);
/// pass `null` for standalone reminders that aren't attached to a memory.
Map<String, dynamic> reminderToMap(
  Reminder r, {
  required String ownerUid,
  required String? memoryCloudId,
}) {
  return <String, dynamic>{
    ..._envelope(
      cloudId: r.cloudId,
      ownerUid: ownerUid,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
    ),
    'memoryCloudId': memoryCloudId,
    'text': r.text,
    'remindAt': Timestamp.fromDate(r.remindAt),
    'fired': r.fired,
    'completed': r.completed,
  };
}

/// Decodes a Firestore document body into a `Reminder`.
///
/// [memoryIsarId] is the caller-resolved local Isar primary key for the
/// parent memory (or `null` if the parent isn't present locally).
/// [notificationId] is the freshly assigned local notification id
/// (Property 13).
Reminder mapToReminder(
  Map<String, dynamic> map, {
  required int? memoryIsarId,
  required int notificationId,
}) {
  return Reminder()
    ..cloudId = (map['cloudId'] as String?) ?? ''
    ..memoryId = memoryIsarId
    ..text = (map['text'] as String?) ?? ''
    ..remindAt = _toDate(map['remindAt'])
    ..createdAt = _toDate(map['createdAt'])
    ..updatedAt = _toDate(map['updatedAt'])
    ..fired = map['fired'] == true
    ..completed = map['completed'] == true
    ..notificationId = notificationId
    ..deletedAt = _toDateOrNull(map['deletedAt']);
}

// ────────────────────────────────────────────────────────────────────────────
// Habit
// ────────────────────────────────────────────────────────────────────────────

/// Encodes [h] for `users/{ownerUid}/habits/{h.cloudId}`. `notificationId`
/// is stripped (Device_Local_Field).
Map<String, dynamic> habitToMap(
  Habit h, {
  required String ownerUid,
}) {
  return <String, dynamic>{
    ..._envelope(
      cloudId: h.cloudId,
      ownerUid: ownerUid,
      createdAt: h.createdAt,
      updatedAt: h.updatedAt,
      deletedAt: h.deletedAt,
    ),
    'name': h.name,
    'emoji': h.emoji,
    'colorValue': h.colorValue,
    'archived': h.archived,
    'remindHour': h.remindHour,
    'remindMinute': h.remindMinute,
    'intervalMinutes': h.intervalMinutes,
    'intervalEndHour': h.intervalEndHour,
    'targetValue': h.targetValue,
    'targetUnit': h.targetUnit,
  };
}

/// Decodes a Firestore document body into a `Habit`.
///
/// [notificationId] is the freshly assigned local notification id
/// (Property 13). The caller is responsible for re-registering any
/// scheduled notification.
Habit mapToHabit(
  Map<String, dynamic> map, {
  required int notificationId,
}) {
  return Habit()
    ..cloudId = (map['cloudId'] as String?) ?? ''
    ..name = (map['name'] as String?) ?? ''
    ..emoji = map['emoji'] as String?
    ..colorValue = (map['colorValue'] as int?) ?? 0
    ..createdAt = _toDate(map['createdAt'])
    ..updatedAt = _toDate(map['updatedAt'])
    ..archived = map['archived'] == true
    ..remindHour = map['remindHour'] as int?
    ..remindMinute = map['remindMinute'] as int?
    ..intervalMinutes = (map['intervalMinutes'] as int?) ?? 0
    ..intervalEndHour = (map['intervalEndHour'] as int?) ?? 22
    ..notificationId = notificationId
    ..targetValue = (map['targetValue'] as num?)?.toDouble()
    ..targetUnit = map['targetUnit'] as String?
    ..deletedAt = _toDateOrNull(map['deletedAt']);
}

// ────────────────────────────────────────────────────────────────────────────
// HabitCompletion
// ────────────────────────────────────────────────────────────────────────────

/// Encodes [c] for `users/{ownerUid}/habitCompletions/{c.cloudId}`.
///
/// [habitCloudId] is the caller-resolved translation of `c.habitId` (Isar
/// pk → cloud id). `HabitCompletion` has no `createdAt` field on the local
/// model, so the envelope's `createdAt` mirrors `completedAt` — this keeps
/// every cloud document well-formed under the common envelope without
/// inventing wall-clock times.
Map<String, dynamic> completionToMap(
  HabitCompletion c, {
  required String ownerUid,
  required String habitCloudId,
}) {
  return <String, dynamic>{
    ..._envelope(
      cloudId: c.cloudId,
      ownerUid: ownerUid,
      createdAt: c.completedAt,
      updatedAt: c.updatedAt,
      deletedAt: c.deletedAt,
    ),
    'habitCloudId': habitCloudId,
    'date': Timestamp.fromDate(c.date),
    'completedAt': Timestamp.fromDate(c.completedAt),
    // Only emit `slotIndex` when non-null so legacy single-slot habits and
    // documents written by older clients keep their existing shape
    // (Requirements 7.8, 7.9).
    if (c.slotIndex != null) 'slotIndex': c.slotIndex,
  };
}

/// Decodes a Firestore document body into a `HabitCompletion`.
///
/// [habitIsarId] is the caller-resolved local Isar primary key of the
/// parent habit. (`HabitCompletion.habitId` is non-nullable, so the parent
/// must already be restored before any completion is decoded — that
/// ordering is enforced by `RestoreFlow`.)
HabitCompletion mapToCompletion(
  Map<String, dynamic> map, {
  required int habitIsarId,
}) {
  return HabitCompletion()
    ..cloudId = (map['cloudId'] as String?) ?? ''
    ..habitId = habitIsarId
    ..date = _toDate(map['date'])
    ..completedAt = _toDate(map['completedAt'])
    ..updatedAt = _toDate(map['updatedAt'])
    ..deletedAt = _toDateOrNull(map['deletedAt'])
    // Inbound legacy/single-slot documents omit `slotIndex`; readers treat
    // null as slot 0 (Requirement 7.9).
    ..slotIndex = (map['slotIndex'] as int?);
}
