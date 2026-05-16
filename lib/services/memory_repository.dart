import 'dart:io';
import 'dart:math' as math;

import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../core/category.dart';
import '../models/habit.dart';
import '../models/habit_completion.dart';
import '../models/memory_item.dart';
import '../models/reminder.dart';
import 'classifier_service.dart';
import 'database_service.dart';
import 'firestore_sync_service.dart';
import 'notification_service.dart';
import 'promise_detector.dart';
import 'settings_service.dart';

/// Whether a sync hook fires for an upsert or a delete. Local helper used
/// by [MemoryRepository._emitSync] to keep the dispatch readable.
enum _MutationKind { upsert, delete }

/// Central place for creating, updating, deleting and querying memories.
///
/// Every create/update path here:
///  1. Runs the classifier to set a category.
///  2. Runs the promise detector to flag `hasPromise`.
///  3. Tokenizes for fast local search.
///  4. Persists the item in a single write txn.
class MemoryRepository {
  MemoryRepository._();
  static final MemoryRepository instance = MemoryRepository._();

  Isar get _isar => DatabaseService.instance.isar;

  /// UUID generator for `cloudId` assignment on create. Held as an
  /// instance field so test suites can substitute it if needed; the
  /// runtime cost is just the const constructor call.
  final Uuid _uuid = const Uuid();

  /// Notify the Firestore sync engine after a write transaction commits.
  ///
  /// No-op when the user has not opted in to cloud backup
  /// (`SettingsService.getSyncEnabled() == false`), so the signed-out
  /// CRUD path is bit-identical to what it was under the Drive backup.
  /// Called *after* `writeTxn` so a failed Isar write never leaks an
  /// outbound Firestore write.
  Future<void> _emitSync(_MutationKind kind, MemoryItem m) async {
    if (!await SettingsService.instance.getSyncEnabled()) return;
    switch (kind) {
      case _MutationKind.upsert:
        FirestoreSyncService.instance.enqueueUpsert('memories', m);
        break;
      case _MutationKind.delete:
        FirestoreSyncService.instance.enqueueDelete('memories', m);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Creation
  // ---------------------------------------------------------------------------

  Future<MemoryItem> createTextMemory({
    required String content,
    String? title,
    MemorySource source = MemorySource.text,
    MemoryCategory? forcedCategory,
    String? forcedCategoryId,
  }) async {
    final detection = PromiseDetector.instance.detect(content);
    final autoCategory = detection.hasPromise
        ? MemoryCategory.promise
        : ClassifierService.instance.classify(content);
    // forcedCategoryId (custom category) takes precedence, then the built-in
    // enum override, then the auto-detected result.
    final categoryId = forcedCategoryId ??
        forcedCategory?.id ??
        autoCategory.id;

    final tags = ClassifierService.instance
        .extractTags(content, MemoryCategory.fromId(categoryId));
    final tokens = ClassifierService.instance
        .tokenize(content, title: title, tags: tags);

    final now = DateTime.now();
    final item = MemoryItem()
      ..cloudId = _uuid.v4()
      ..title = title
      ..content = content
      ..rawUrl = _extractUrl(content)
      ..sourceType = source.name
      ..categoryId = categoryId
      ..tags = tags
      ..searchTokens = tokens
      ..createdAt = now
      ..updatedAt = now
      ..hasPromise = detection.hasPromise;

    await _isar.writeTxn(() async {
      await _isar.memoryItems.put(item);
    });
    await _emitSync(_MutationKind.upsert, item);
    return item;
  }



  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<void> update(MemoryItem item) async {
    item.updatedAt = DateTime.now();
    item.searchTokens = ClassifierService.instance.tokenize(
      item.content,
      title: item.title,
      tags: item.tags,
    );
    await _isar.writeTxn(() async {
      await _isar.memoryItems.put(item);
    });
    await _emitSync(_MutationKind.upsert, item);
  }

  Future<void> togglePinned(MemoryItem item) async {
    item.pinned = !item.pinned;
    await update(item);
  }

  Future<void> toggleArchived(MemoryItem item) async {
    item.archived = !item.archived;
    await update(item);
  }

  Future<void> delete(MemoryItem item) async {
    // When cloud sync is on, hand off to the engine: it soft-deletes the
    // row (sets `deletedAt`/`updatedAt = now`), uploads a tombstone, and
    // hard-deletes locally on ack. We deliberately keep the cascade for
    // reminders local — tombstones for those flow through the reminder
    // repository as users (or other devices) interact with them.
    if (await SettingsService.instance.getSyncEnabled()) {
      // Cancel any local reminder notifications first so the user doesn't
      // see a notification for a memory that's about to disappear.
      final rems = await _isar.reminders
          .filter()
          .memoryIdEqualTo(item.id)
          .findAll();
      for (final r in rems) {
        try {
          await NotificationService.instance.cancel(r.notificationId);
        } catch (_) {}
      }
      // The engine handles the local soft-delete + tombstone upload.
      // Image files and reminder rows are cleaned up when the
      // tombstone is acknowledged (engine path) or via cascading
      // tombstones for the reminders themselves.
      await _emitSync(_MutationKind.delete, item);
      return;
    }

    // Signed-out path: hard-delete locally as before.
    // Cascade: remove reminders attached to this memory.
    await _isar.writeTxn(() async {
      final rems = await _isar.reminders
          .filter()
          .memoryIdEqualTo(item.id)
          .findAll();
      for (final r in rems) {
        await NotificationService.instance.cancel(r.notificationId);
      }
      await _isar.reminders
          .filter()
          .memoryIdEqualTo(item.id)
          .deleteAll();
      await _isar.memoryItems.delete(item.id);
    });
  }

  Future<void> markReminderPromptHandled(MemoryItem item) async {
    item.reminderPromptHandled = true;
    await update(item);
  }

  /// Links two entries bidirectionally.
  Future<void> linkEntries(MemoryItem a, MemoryItem b) async {
    if (!a.linkedIds.contains(b.id)) {
      a.linkedIds = [...a.linkedIds, b.id];
      await update(a);
    }
    if (!b.linkedIds.contains(a.id)) {
      b.linkedIds = [...b.linkedIds, a.id];
      await update(b);
    }
  }

  /// Removes a link between two entries bidirectionally.
  Future<void> unlinkEntries(MemoryItem a, MemoryItem b) async {
    a.linkedIds = a.linkedIds.where((id) => id != b.id).toList();
    await update(a);
    b.linkedIds = b.linkedIds.where((id) => id != a.id).toList();
    await update(b);
  }

  /// Fetches all entries linked to [item].
  Future<List<MemoryItem>> getLinked(MemoryItem item) async {
    if (item.linkedIds.isEmpty) return const [];
    final results = <MemoryItem>[];
    for (final id in item.linkedIds) {
      final m = await _isar.memoryItems.get(id);
      if (m != null) results.add(m);
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// All non-archived memories, newest first, pinned items on top.
  Stream<List<MemoryItem>> watchInbox() {
    return _isar.memoryItems
        .filter()
        .archivedEqualTo(false)
        .sortByPinnedDesc()
        .thenByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<MemoryItem>> watchByCategory(MemoryCategory category) {
    return watchByCategoryId(category.id);
  }

  Stream<List<MemoryItem>> watchByCategoryId(String categoryId) {
    return _isar.memoryItems
        .filter()
        .categoryIdEqualTo(categoryId, caseSensitive: false)
        .and()
        .archivedEqualTo(false)
        .sortByPinnedDesc()
        .thenByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<MemoryItem>> watchArchived() {
    return _isar.memoryItems
        .filter()
        .archivedEqualTo(true)
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  /// Local full-text search with light fuzzy matching.
  ///
  /// - exact-token match (via indexed searchTokens) is scored highest
  /// - `contains` fallback on content and title catches partial words
  /// - returns results sorted by recency * score
  Future<List<MemoryItem>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final terms = q
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    // Primary: indexed token match for any term.
    final tokenHits = await _isar.memoryItems
        .filter()
        .anyOf(terms, (q, t) => q.searchTokensElementContains(t))
        .and()
        .archivedEqualTo(false)
        .findAll();

    final byId = <int, _Scored>{};
    for (final m in tokenHits) {
      byId.putIfAbsent(m.id, () => _Scored(m, 0)).score += 3;
    }

    // Fallback: substring scan catches partial words and short queries that
    // the tokenizer wouldn't isolate ("you" in "youtube").
    final all = await _isar.memoryItems
        .filter()
        .archivedEqualTo(false)
        .findAll();
    for (final m in all) {
      final hay = '${m.title ?? ''} ${m.content}'.toLowerCase();
      for (final t in terms) {
        if (hay.contains(t)) {
          byId.putIfAbsent(m.id, () => _Scored(m, 0)).score += 1;
        }
      }
    }

    final scored = byId.values.toList()
      ..sort((a, b) {
        final s = b.score.compareTo(a.score);
        if (s != 0) return s;
        return b.item.createdAt.compareTo(a.item.createdAt);
      });
    return scored.map((s) => s.item).toList(growable: false);
  }

  /// Counts of items per category (non-archived).
  Future<Map<MemoryCategory, int>> categoryCounts() async {
    final all = await _isar.memoryItems
        .filter()
        .archivedEqualTo(false)
        .findAll();
    final counts = <MemoryCategory, int>{};
    for (final item in all) {
      final c = MemoryCategory.fromId(item.categoryId);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts;
  }

  /// Raw counts keyed by [MemoryItem.categoryId], so the Categories tab can
  /// display both built-in and custom categories with a single query.
  Future<Map<String, int>> categoryCountsById() async {
    final all = await _isar.memoryItems
        .filter()
        .archivedEqualTo(false)
        .findAll();
    final counts = <String, int>{};
    for (final item in all) {
      counts[item.categoryId] = (counts[item.categoryId] ?? 0) + 1;
    }
    return counts;
  }

  Future<MemoryItem?> getById(int id) =>
      _isar.memoryItems.get(id);

  /// Returns non-archived memories sorted by [MemoryItem.updatedAt]
  /// descending, paged via [offset] and [limit].
  ///
  /// Used by the link-picker sheet to show "recents" when the search
  /// query is empty; pagination keeps memory pressure bounded for users
  /// with thousands of entries.
  Future<List<MemoryItem>> fetchRecent({
    int limit = 50,
    int offset = 0,
  }) async {
    return _isar.memoryItems
        .filter()
        .archivedEqualTo(false)
        .sortByUpdatedAtDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
  }

  // ---------------------------------------------------------------------------
  // Backup / restore (JSON-based; documented in settings)
  //
  // New format (v2) bundles memories, reminders, and habits (with their
  // completions) into a single JSON object so a backup fully round-trips.
  // Old-format backups (a top-level JSON array of memory maps) still import
  // — see [importFromJson].
  // ---------------------------------------------------------------------------

  /// Full backup: memories, reminders, habits, and habit completions.
  Future<Map<String, dynamic>> exportAll() async {
    final items = await _isar.memoryItems.where().findAll();
    final reminders = await _isar.reminders.where().findAll();
    final habits = await _isar.habits.where().findAll();
    final completions = await _isar.habitCompletions.where().findAll();

    return {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'memories': items.map(_memoryToJson).toList(),
      'reminders': reminders.map(_reminderToJson).toList(),
      'habits': habits.map(_habitToJson).toList(),
      'habitCompletions': completions.map(_completionToJson).toList(),
    };
  }

  Map<String, dynamic> _memoryToJson(MemoryItem m) => {
        'id': m.id,
        'title': m.title,
        'content': m.content,
        'rawUrl': m.rawUrl,
        'imagePath': m.imagePath,
        'sourceType': m.sourceType,
        'categoryId': m.categoryId,
        'tags': m.tags,
        'createdAt': m.createdAt.toIso8601String(),
        'updatedAt': m.updatedAt.toIso8601String(),
        'pinned': m.pinned,
        'archived': m.archived,
        'hasPromise': m.hasPromise,
        'colorValue': m.colorValue,
      };

  Map<String, dynamic> _reminderToJson(Reminder r) => {
        'id': r.id,
        'memoryId': r.memoryId,
        'text': r.text,
        'remindAt': r.remindAt.toIso8601String(),
        'createdAt': r.createdAt.toIso8601String(),
        'fired': r.fired,
        'completed': r.completed,
        'notificationId': r.notificationId,
      };

  Map<String, dynamic> _habitToJson(Habit h) => {
        'id': h.id,
        'name': h.name,
        'emoji': h.emoji,
        'colorValue': h.colorValue,
        'createdAt': h.createdAt.toIso8601String(),
        'archived': h.archived,
        'remindHour': h.remindHour,
        'remindMinute': h.remindMinute,
        'intervalMinutes': h.intervalMinutes,
        'intervalEndHour': h.intervalEndHour,
        'notificationId': h.notificationId,
      };

  Map<String, dynamic> _completionToJson(HabitCompletion c) => {
        'habitId': c.habitId,
        'date': c.date.toIso8601String(),
        'completedAt': c.completedAt.toIso8601String(),
      };

  /// Imports a backup. Accepts both the legacy format (top-level JSON array
  /// of memory maps) and the new v2 format (object with memories / reminders
  /// / habits / habitCompletions arrays). Reminder notifications are
  /// re-scheduled and habit daily notifications are re-registered so the
  /// imported state is fully functional, not just visible.
  ///
  /// Hard caps per-collection at 50,000 items to prevent a crafted backup
  /// file from causing an OOM on import.
  Future<int> importFromJson(dynamic decoded) async {
    const maxItems = 50000;

    // Legacy: top-level list of memory maps.
    if (decoded is List) {
      final capped =
          decoded.length > maxItems ? decoded.sublist(0, maxItems) : decoded;
      return _importMemories(capped);
    }
    if (decoded is! Map) {
      throw const FormatException('Unsupported backup format');
    }

    var total = 0;
    // Maps: old reminder/habit id in the backup → new Isar id after import.
    // Used to keep the memoryId foreign key linkage intact.
    final memoryIdMap = <int, int>{};
    final habitIdMap = <int, int>{};

    List<dynamic> cap(List<dynamic>? list) {
      if (list == null) return const [];
      return list.length > maxItems ? list.sublist(0, maxItems) : list;
    }

    // 1) Memories
    final memList = cap(decoded['memories'] as List?);
    total += await _importMemories(memList, idMap: memoryIdMap);

    // 2) Reminders
    final remList = cap(decoded['reminders'] as List?);
    await _importReminders(remList, memoryIdMap);
    total += remList.length;

    // 3) Habits
    final habitList = cap(decoded['habits'] as List?);
    await _importHabits(habitList, habitIdMap);
    total += habitList.length;

    // 4) Habit completions
    final compList = cap(decoded['habitCompletions'] as List?);
    await _importCompletions(compList, habitIdMap);

    return total;
  }

  Future<int> _importMemories(
    List<dynamic> list, {
    Map<int, int>? idMap,
  }) async {
    // Pre-validate image paths OUTSIDE the writeTxn: file system calls and
    // an Isar write transaction don't mix well, so we resolve each memory's
    // imagePath first and only hit the DB inside the txn.
    final prepared = <MemoryItem>[];
    final oldIds = <int?>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      String? imagePath = raw['imagePath'] as String?;
      if (imagePath != null && imagePath.isNotEmpty) {
        try {
          if (!await File(imagePath).exists()) imagePath = null;
        } catch (_) {
          imagePath = null;
        }
      }
      final m = MemoryItem()
        ..title = raw['title'] as String?
        ..content = (raw['content'] ?? '') as String
        ..rawUrl = raw['rawUrl'] as String?
        ..imagePath = imagePath
        ..sourceType = (raw['sourceType'] ?? MemorySource.text.name) as String
        ..categoryId = (raw['categoryId'] ?? MemoryCategory.note.id) as String
        ..tags = ((raw['tags'] as List?)?.cast<String>()) ?? const []
        ..createdAt =
            DateTime.tryParse(raw['createdAt'] as String? ?? '') ??
                DateTime.now()
        ..updatedAt =
            DateTime.tryParse(raw['updatedAt'] as String? ?? '') ??
                DateTime.now()
        ..pinned = raw['pinned'] == true
        ..archived = raw['archived'] == true
        ..hasPromise = raw['hasPromise'] == true
        ..colorValue = raw['colorValue'] as int?;
      m.searchTokens = ClassifierService.instance
          .tokenize(m.content, title: m.title, tags: m.tags);
      prepared.add(m);
      oldIds.add(raw['id'] as int?);
    }

    // ── Deduplication ──────────────────────────────────────────────────────
    // Build a key from (content, createdAt-ms) and skip imports that already
    // exist locally. When the local copy is older than the imported one, we
    // overwrite it instead of creating a duplicate.
    final existing = await _isar.memoryItems.where().findAll();
    final existingByKey = <String, MemoryItem>{};
    String dedupKey(MemoryItem m) =>
        '${m.content}\u0001${m.createdAt.millisecondsSinceEpoch}';
    for (final e in existing) {
      existingByKey[dedupKey(e)] = e;
    }

    var imported = 0;
    await _isar.writeTxn(() async {
      for (var i = 0; i < prepared.length; i++) {
        final m = prepared[i];
        final key = dedupKey(m);
        final dup = existingByKey[key];
        if (dup != null) {
          // Already have it locally — keep whichever was edited more recently.
          if (m.updatedAt.isAfter(dup.updatedAt)) {
            m.id = dup.id; // overwrite
            await _isar.memoryItems.put(m);
            if (oldIds[i] != null && idMap != null) {
              idMap[oldIds[i]!] = dup.id;
            }
          } else {
            // Local copy is newer — skip the import entirely.
            if (oldIds[i] != null && idMap != null) {
              idMap[oldIds[i]!] = dup.id;
            }
          }
          continue;
        }
        final newId = await _isar.memoryItems.put(m);
        existingByKey[key] = m; // in case the same backup contains duplicates
        final oldId = oldIds[i];
        if (oldId != null && idMap != null) idMap[oldId] = newId;
        imported++;
      }
    });
    return imported;
  }

  Future<void> _importReminders(
    List<dynamic> list,
    Map<int, int> memoryIdMap,
  ) async {
    final now = DateTime.now();
    final toSchedule = <Reminder>[];
    await _isar.writeTxn(() async {
      for (final raw in list) {
        if (raw is! Map) continue;
        final oldMemoryId = raw['memoryId'] as int?;
        final r = Reminder()
          ..memoryId =
              oldMemoryId != null ? memoryIdMap[oldMemoryId] : null
          ..text = (raw['text'] ?? '') as String
          ..remindAt = DateTime.tryParse(raw['remindAt'] as String? ?? '') ??
              now.add(const Duration(hours: 1))
          ..createdAt = DateTime.tryParse(raw['createdAt'] as String? ?? '') ??
              now
          ..fired = raw['fired'] == true
          ..completed = raw['completed'] == true
          ..notificationId = 0;
        final newId = await _isar.reminders.put(r);
        r.notificationId = newId & 0x7FFFFFFF;
        await _isar.reminders.put(r);
        toSchedule.add(r);
      }
    });
    // Re-schedule the notifications outside the txn.
    for (final r in toSchedule) {
      if (r.completed || r.remindAt.isBefore(now)) continue;
      await NotificationService.instance.schedule(
        id: r.notificationId,
        title: 'Mnemo reminder',
        body: r.text,
        when: r.remindAt,
      );
    }
  }

  Future<void> _importHabits(
    List<dynamic> list,
    Map<int, int> idMap,
  ) async {
    // Build a dedup key from (name, createdAt-ms).
    final existing = await _isar.habits.where().findAll();
    final existingByKey = <String, Habit>{};
    String habitKey(Habit h) =>
        '${h.name}\u0001${h.createdAt.millisecondsSinceEpoch}';
    for (final h in existing) {
      existingByKey[habitKey(h)] = h;
    }

    final toSchedule = <Habit>[];
    await _isar.writeTxn(() async {
      for (final raw in list) {
        if (raw is! Map) continue;
        final oldId = raw['id'] as int?;
        final h = Habit()
          ..name = (raw['name'] ?? '') as String
          ..emoji = raw['emoji'] as String?
          ..colorValue = (raw['colorValue'] ?? 0xFF64748B) as int
          ..createdAt = DateTime.tryParse(raw['createdAt'] as String? ?? '') ??
              DateTime.now()
          ..archived = raw['archived'] == true
          ..remindHour = raw['remindHour'] as int?
          ..remindMinute = raw['remindMinute'] as int?
          ..intervalMinutes = (raw['intervalMinutes'] ?? 0) as int
          ..intervalEndHour = (raw['intervalEndHour'] ?? 22) as int
          ..notificationId = 0;
        final key = habitKey(h);
        final dup = existingByKey[key];
        if (dup != null) {
          // Already exists — reuse the local id, skip the import.
          if (oldId != null) idMap[oldId] = dup.id;
          continue;
        }
        final newId = await _isar.habits.put(h);
        h.notificationId = (newId + 100000) & 0x7FFFFFFF;
        await _isar.habits.put(h);
        existingByKey[key] = h;
        if (oldId != null) idMap[oldId] = newId;
        toSchedule.add(h);
      }
    });
    // Re-register daily / interval notifications outside the txn.
    for (final h in toSchedule) {
      if (h.archived || h.remindHour == null) continue;
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
    }
  }

  Future<void> _importCompletions(
    List<dynamic> list,
    Map<int, int> habitIdMap,
  ) async {
    // Dedup key: (habitId, normalized-day) so we never import the same
    // completion twice.
    final existing = await _isar.habitCompletions.where().findAll();
    final existingKeys = <String>{
      for (final c in existing)
        '${c.habitId}\u0001${c.date.millisecondsSinceEpoch}',
    };
    await _isar.writeTxn(() async {
      for (final raw in list) {
        if (raw is! Map) continue;
        final oldHabitId = raw['habitId'] as int?;
        if (oldHabitId == null) continue;
        final newHabitId = habitIdMap[oldHabitId];
        if (newHabitId == null) continue;
        final date = DateTime.tryParse(raw['date'] as String? ?? '') ??
            DateTime.now();
        final key = '$newHabitId\u0001${date.millisecondsSinceEpoch}';
        if (existingKeys.contains(key)) continue;
        final c = HabitCompletion()
          ..habitId = newHabitId
          ..date = date
          ..completedAt =
              DateTime.tryParse(raw['completedAt'] as String? ?? '') ??
                  DateTime.now();
        await _isar.habitCompletions.put(c);
        existingKeys.add(key);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  String? _extractUrl(String text) {
    final m =
        RegExp(r'https?:\/\/[^\s]+', caseSensitive: false).firstMatch(text);
    return m?.group(0);
  }
}

class _Scored {
  _Scored(this.item, this.score);
  final MemoryItem item;
  int score;
}

/// Stable 31-bit id for a reminder from its primary key, used when we need to
/// register a notification id without hitting Isar again. Kept here so the
/// reminder repository and memory repository can share the same logic.
int stableNotificationId(int reminderId) =>
    reminderId & 0x7FFFFFFF; // 31-bit positive int for Android notif ids

/// Allows callers that compute derived ids to stay consistent.
int randomNotificationIdSeed() => math.Random().nextInt(1 << 30);
