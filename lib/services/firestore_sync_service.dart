import 'dart:async';
import 'dart:io' as java_io;
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../models/habit.dart';
import '../models/habit_completion.dart';
import '../models/memory_item.dart';
import '../models/reminder.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'sync/restore_flow.dart';
import 'sync/sync_codec.dart';

/// 1500 ms quiescent window before a buffered upsert is flushed to Firestore.
/// Lives here so the property tests in `test/sync/debounce_queue_test.dart`
/// can pin the same constant.
const Duration _kDebounceWindow = Duration(milliseconds: 1500);

/// 30-day retention applied to remote tombstones by [FirestoreSyncService.sweepTombstones].
/// Documents whose `deletedAt` is older than this are batch-deleted from
/// Firestore on every `start()` and `syncNow()` call.
const Duration _kTombstoneRetention = Duration(days: 30);

/// Maximum delay between listener re-attach attempts (Requirement 11.4).
const Duration _kBackoffCap = Duration(seconds: 60);

/// Outcome of the last-write-wins comparator. Internal — callers consume
/// the booleans `result == _CompareResult.remoteWins` etc. directly.
enum _CompareResult { remoteWins, localWins }

/// One slot in the debounce queue: the latest serialized payload for a
/// given `(collection, cloudId)` plus the pending flush timer. Subsequent
/// `enqueueUpsert` calls overwrite both fields, so N writes within the
/// 1500 ms window collapse into a single Firestore write that carries the
/// last state (Property 7).
class _PendingUpsert {
  _PendingUpsert({required this.payload, required this.timer});

  Map<String, dynamic> payload;
  Timer timer;
}

/// The Firestore sync engine.
///
/// Owns:
///
/// * The singleton lifecycle (`init`/`start`/`stop`).
/// * The `(collection, cloudId)`-keyed 1500 ms debounce queue and its flush
///   to `users/$uid/$collection/$cloudId`.
/// * `lastCloudSync` advancement on every Firestore ack (Property 9).
/// * Per-collection snapshot listeners with exponential-backoff re-attach
///   (Requirement 11.4) and a permission-denied kill-switch (Requirement 11.3).
/// * The conflict resolver — last-write-wins on `updatedAt`, deterministic
///   tie-break on `(ownerUid, cloudId)` — used by the live listener path
///   and by `RestoreFlow` on populated DBs (Requirements 6.3, 6.4, 7.1, 7.2).
/// * Tombstone upload, inbound tombstone application, tombstone-ack hard
///   delete, and the 30-day remote sweep (Requirements 5.5, 6.5, 8.1, 8.3,
///   8.4, 8.5).
/// * The suppress-echo `_applyingRemote` set keyed on
///   `(collection, cloudId, updatedAtMs)` so a remote-applied row is not
///   re-uploaded by any incidental re-trigger of `enqueueUpsert`
///   (Requirement 6.7).
class FirestoreSyncService {
  FirestoreSyncService._();
  static final FirestoreSyncService instance = FirestoreSyncService._();

  /// Synced collection names used as path segments under `users/{uid}`.
  /// Order is significant for `RestoreFlow` (memories before reminders so
  /// `memoryCloudId` resolves; habits before habitCompletions so
  /// `habitCloudId` resolves), but for sweep / start it's just the set.
  static const List<String> _kSyncedCollections = <String>[
    'memories',
    'reminders',
    'habits',
    'habitCompletions',
  ];

  // ── Identity / lifecycle ─────────────────────────────────────────────────

  String? _uid;
  bool _running = false;
  StreamSubscription<User?>? _userSub;

  // ── Outgoing pipeline ────────────────────────────────────────────────────

  /// Keyed by `'$collection|$cloudId'`. Holds the latest serialized payload
  /// alongside its pending flush [Timer]. `stop()` cancels every timer and
  /// drops the buffered payloads without uploading them.
  final Map<String, _PendingUpsert> _pending = <String, _PendingUpsert>{};

  // ── Inbound pipeline ─────────────────────────────────────────────────────

  /// One snapshot subscription per collection. Cancelled and replaced by
  /// `_attachWithRetry` on every reattach; cleared in `stop`.
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _subs = <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};

  /// Per-collection consecutive-error counter for exponential backoff.
  /// Reset to zero whenever a snapshot is delivered successfully. The
  /// next re-attempt delay is `min(60_000, 1000 * 2^(n-1))` ms.
  final Map<String, int> _attempts = <String, int>{};

  // ── Suppress-echo guard ──────────────────────────────────────────────────

  /// Set of `'$collection|$cloudId|<updatedAtMs>'` keys currently being
  /// applied from a remote snapshot. Populated before the inbound write
  /// commits and removed via `scheduleMicrotask` so the repository's
  /// post-write hook (which runs synchronously after the Isar txn) sees
  /// the flag and suppresses an outbound echo.
  ///
  /// The compound key includes `updatedAtMs` so a fresh user edit (which
  /// advances `updatedAt`) is *not* suppressed: any genuine outbound write
  /// produces a strictly greater `updatedAt` than the one we just applied.
  final Set<String> _applyingRemote = <String>{};

  // ── Public error surface ────────────────────────────────────────────────

  /// Last terminal sync error surface for the Settings UI (Requirement 11.3).
  /// `null` means the engine is healthy. Set to a short human-readable
  /// string by `_onPermissionDenied`.
  Object? lastError;

  /// Per-collection inserted-counts from the most recent [RestoreFlow.run]
  /// invocation. Settings reads this once on first frame after sign-in to
  /// render the "imported X memories, Y reminders, …" toast (Requirement
  /// 9.6). `null` until [start] has completed at least one restore pass —
  /// or when the restore failed (the engine swallows restore exceptions
  /// so listener attach is never blocked).
  RestoreSummary? lastRestoreSummary;

  // ── Firestore handle ─────────────────────────────────────────────────────

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Subscribes to [AuthService.userStream] and starts the engine when the
  /// user is non-null, stops it when null.
  ///
  /// Safe to call once at boot from `main.dart` (task 7.12). The auth
  /// listener fires immediately with the current user, so a cold start
  /// while signed in transitions straight into [start].
  Future<void> init() async {
    _userSub ??= AuthService.instance.userStream.listen((user) async {
      if (user != null) {
        await start(user.uid);
      } else {
        await stop();
      }
    });
  }

  /// Marks the engine running for [uid], attaches the four snapshot
  /// listeners (with exponential-backoff re-attach), and kicks off a
  /// background tombstone sweep.
  ///
  /// Idempotent against re-entry: if the engine is already running for the
  /// same uid we still re-arm the listener fan-out so a previous
  /// permission-denied kill leaves a clean re-entry path.
  Future<void> start(String uid) async {
    _uid = uid;
    _running = true;
    lastError = null;

    // Run the restore pass before any long-running listeners attach so
    // a fresh-install device hydrates from Firestore in one bounded
    // pass rather than racing the snapshot stream's initial delivery
    // against repository writes (Requirement 9.1).
    //
    // Wrapped in try/catch: a restore failure (offline, transient
    // permission glitch, malformed remote doc) must never block the
    // listener attach below. The listeners themselves are the
    // long-term reconciliation mechanism, so a missed restore just
    // means the UI surfaces stale-but-correct data until the next
    // listener delivery.
    try {
      lastRestoreSummary = await RestoreFlow.run(uid);
    } catch (e) {
      debugPrint('[FirestoreSyncService] RestoreFlow.run failed: $e');
      lastRestoreSummary = null;
    }

    // Re-attach the four snapshot listeners. Each call is isolated: a
    // failure on one collection schedules a retry for that collection
    // alone and never blocks the others.
    for (final c in _kSyncedCollections) {
      _attempts[c] = 0;
      _attachWithRetry(c);
    }

    // Background tombstone sweep. Fire-and-forget — we don't want a
    // sweep failure to block the rest of the start path. Internal errors
    // are absorbed inside `sweepTombstones`.
    unawaited(sweepTombstones());
  }

  /// Tears the engine down.
  ///
  /// Cancels every pending debounce timer **without** flushing — the
  /// contract is that a sign-out (or auth-state churn) never leaks the
  /// previous user's buffered edits to a freshly signed-in account. Also
  /// cancels every snapshot listener and resets the backoff counters.
  Future<void> stop() async {
    _running = false;

    for (final pending in _pending.values) {
      pending.timer.cancel();
    }
    _pending.clear();

    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    _attempts.clear();

    _uid = null;
  }

  /// Enqueue an upsert for [item] in [collection].
  ///
  /// Called by repositories after the Isar write transaction commits.
  /// No-ops when:
  /// * the engine isn't running,
  /// * no user is signed in,
  /// * `item.cloudId` is empty (unmigrated row — should be impossible after
  ///   `IsarMigrationService` runs at boot),
  /// * the same `(collection, cloudId, updatedAtMs)` is currently being
  ///   applied from a remote snapshot (suppress-echo).
  ///
  /// Otherwise serializes [item] via `sync_codec` (resolving parent
  /// `cloudId`s by looking up Isar primary keys), stores the payload in
  /// `_pending`, and schedules a 1500 ms flush.
  void enqueueUpsert(String collection, dynamic item) {
    if (!_running) return;
    final uid = _uid;
    if (uid == null) return;

    final cloudId = _cloudIdOf(item);
    if (cloudId.isEmpty) return;

    // Suppress-echo: any genuine outbound write produces a strictly
    // greater `updatedAt` than the one we just applied, so this only
    // matches when an inbound listener delivery is being mirrored back
    // through some repository path.
    final updatedAtMs = _updatedAtMsOf(item);
    final echoKey = _echoKey(collection, cloudId, updatedAtMs);
    if (_applyingRemote.contains(echoKey)) return;

    // Serialization needs an Isar lookup for parent `cloudId`s, so it's
    // async; the public API stays `void` by fire-and-forgetting the future.
    // Errors during serialization are swallowed by `_serializeAndQueue`.
    unawaited(_serializeAndQueue(uid, collection, cloudId, item));
  }

  /// Enqueue a delete for [item] in [collection].
  ///
  /// Soft-deletes the local row (sets `deletedAt = updatedAt = now`) and
  /// schedules a tombstone document — an envelope-only document carrying
  /// `cloudId`, `ownerUid`, `createdAt`, `updatedAt`, `deletedAt` — to the
  /// matching cloud path. On Firestore ack, the local row is hard-deleted
  /// via `deleteByCloudId` and any device-local notification is cancelled.
  ///
  /// When `Sync_Enabled` is false the repository hook never reaches here:
  /// signed-out deletes are hard-local, see Requirement 8.2.
  void enqueueDelete(String collection, dynamic item) {
    if (!_running) return;
    final uid = _uid;
    if (uid == null) return;

    final cloudId = _cloudIdOf(item);
    if (cloudId.isEmpty) return;

    unawaited(_softDeleteAndQueueTombstone(uid, collection, cloudId, item));
  }

  /// One-shot reconciliation pass triggered by Settings → "Sync now"
  /// (Requirement 12.4).
  ///
  /// Runs in two stages:
  ///
  /// 1. [RestoreFlow.run] — pulls every non-tombstone document under
  ///    `users/{uid}/{collection}` and applies it through the same
  ///    last-write-wins comparator as the live listener path. This is
  ///    what picks up remote changes that arrived while listeners were
  ///    detached (e.g. backed-off after a transient error) or paused.
  ///    Idempotent: a re-run on a fully-current local DB is a no-op
  ///    because every doc loses the comparator (Requirement 9.5).
  /// 2. [sweepTombstones] — clears out remote tombstones older than 30
  ///    days for the current owner (Requirement 8.5). Useful from the
  ///    Settings UI so the user can trigger a sweep without waiting for
  ///    the next app launch.
  ///
  /// Restore failures are swallowed — the sweep should still run, and
  /// the next listener delivery will repair any inconsistency. Sweep
  /// failures are absorbed internally by [sweepTombstones].
  Future<void> syncNow() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      lastRestoreSummary = await RestoreFlow.run(uid);
    } catch (e) {
      debugPrint('[FirestoreSyncService] syncNow RestoreFlow failed: $e');
    }

    await sweepTombstones();
  }

  /// Batch-delete tombstones older than 30 days for the current owner.
  ///
  /// Called at startup and from `syncNow()`. Tombstones whose `deletedAt`
  /// is at most 30 days old are kept so devices that were offline for ≤ 30
  /// days still see the delete on reconnect (Requirement 8.5).
  Future<void> sweepTombstones() async {
    if (!_running) return;
    final uid = _uid;
    if (uid == null) return;

    final cutoff = DateTime.now().subtract(_kTombstoneRetention);
    final cutoffTs = Timestamp.fromDate(cutoff);

    for (final c in _kSyncedCollections) {
      try {
        final snap = await _firestore
            .collection('users/$uid/$c')
            .where('deletedAt', isLessThan: cutoffTs)
            .get();
        if (snap.docs.isEmpty) continue;
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          await _onPermissionDenied();
          return;
        }
        // Anything else (network blip, transient backend error) just
        // means the next sweep retries — the cap is 30 days of build-up,
        // which is fine.
        debugPrint('[FirestoreSyncService] sweep $c failed: ${e.code}');
      } catch (e) {
        debugPrint('[FirestoreSyncService] sweep $c failed: $e');
      }
    }
  }

  // ── Internals: outgoing pipeline ────────────────────────────────────────

  Future<void> _serializeAndQueue(
    String uid,
    String collection,
    String cloudId,
    dynamic item,
  ) async {
    final Map<String, dynamic> payload;
    try {
      payload = await _serialize(uid, collection, item);
    } catch (_) {
      // Unknown collection or missing parent reference — drop the write
      // rather than crash the repository's post-commit hook.
      return;
    }

    // Identity may have changed while we were awaiting the Isar lookup.
    if (!_running || _uid != uid) return;

    final key = '$collection|$cloudId';
    _pending[key]?.timer.cancel();

    final timer = Timer(_kDebounceWindow, () {
      // Capture-by-closure of (uid, collection, cloudId, key) is safe —
      // `_pending[key]` always carries the freshest payload at flush time.
      unawaited(_flush(uid, collection, cloudId, key));
    });

    _pending[key] = _PendingUpsert(payload: payload, timer: timer);
  }

  Future<void> _flush(
    String uid,
    String collection,
    String cloudId,
    String key,
  ) async {
    final pending = _pending.remove(key);
    if (pending == null) return;
    // Identity check: if we stopped or signed in as someone else between
    // schedule and flush, drop the write.
    if (!_running || _uid != uid) return;

    try {
      await _firestore
          .collection('users/$uid/$collection')
          .doc(cloudId)
          .set(pending.payload, SetOptions(merge: true));
      await SettingsService.instance.setLastCloudSync(DateTime.now());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await _onPermissionDenied();
      }
      // Anything else: the SDK keeps the offline queue and will retry on
      // reconnect (Requirement 11.1). We deliberately do not re-enqueue
      // here to avoid double-flushes once the SDK retries succeed.
    } catch (_) {
      // Non-Firebase exception: log-by-omission and let a future write
      // pick up the latest state.
    }
  }

  // ── Internals: tombstones ───────────────────────────────────────────────

  /// Soft-deletes the local row, uploads an envelope-only tombstone, and
  /// on ack hard-deletes the local row plus any associated notification.
  Future<void> _softDeleteAndQueueTombstone(
    String uid,
    String collection,
    String cloudId,
    dynamic item,
  ) async {
    final isar = DatabaseService.instance.isar;
    final now = DateTime.now();

    // 1. Capture envelope bits before we mutate.
    final createdAt = _createdAtOf(item) ?? now;

    // 2. Soft-delete the local row in a writeTxn.
    try {
      await isar.writeTxn(() async {
        if (item is MemoryItem) {
          item.deletedAt = now;
          item.updatedAt = now;
          await isar.memoryItems.put(item);
        } else if (item is Reminder) {
          item.deletedAt = now;
          item.updatedAt = now;
          await isar.reminders.put(item);
        } else if (item is Habit) {
          item.deletedAt = now;
          item.updatedAt = now;
          await isar.habits.put(item);
        } else if (item is HabitCompletion) {
          item.deletedAt = now;
          item.updatedAt = now;
          await isar.habitCompletions.put(item);
        }
      });
    } catch (_) {
      // If the local soft-delete fails we still try to upload the
      // tombstone — the cloud truth is what other devices observe.
    }

    // 3. Build the envelope-only tombstone payload. Reuses the same
    //    debounce machinery as upserts so a rapid delete-then-undelete
    //    sequence (rare, but possible from undo-style UIs) collapses to
    //    the last-state Firestore write.
    final payload = <String, dynamic>{
      'cloudId': cloudId,
      'ownerUid': uid,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(now),
      'deletedAt': Timestamp.fromDate(now),
    };

    if (!_running || _uid != uid) return;

    final key = '$collection|$cloudId';
    _pending[key]?.timer.cancel();

    final timer = Timer(_kDebounceWindow, () {
      unawaited(_flushTombstone(uid, collection, cloudId, key));
    });

    _pending[key] = _PendingUpsert(payload: payload, timer: timer);
  }

  /// Identical to [_flush] but on ack also hard-deletes the local row by
  /// `cloudId` and cancels the device-local notification (if any).
  Future<void> _flushTombstone(
    String uid,
    String collection,
    String cloudId,
    String key,
  ) async {
    final pending = _pending.remove(key);
    if (pending == null) return;
    if (!_running || _uid != uid) return;

    final isar = DatabaseService.instance.isar;

    try {
      await _firestore
          .collection('users/$uid/$collection')
          .doc(cloudId)
          .set(pending.payload, SetOptions(merge: true));
      await SettingsService.instance.setLastCloudSync(DateTime.now());

      // Hard-delete the local row and cancel any associated notification.
      await _hardDeleteLocalByCloudId(isar, collection, cloudId);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        await _onPermissionDenied();
      }
      // Anything else: the SDK queues the tombstone for retry and the
      // local row stays soft-deleted until the next ack.
    } catch (_) {
      // Non-Firebase exception: leave the row soft-deleted; a future
      // sync will re-attempt the tombstone.
    }
  }

  /// Hard-deletes the matching local row for a given cloudId across the
  /// four collections, cancels device-local notifications when relevant,
  /// and best-effort removes any on-disk image for memories.
  Future<void> _hardDeleteLocalByCloudId(
    Isar isar,
    String collection,
    String cloudId,
  ) async {
    switch (collection) {
      case 'memories':
        final m = await isar.memoryItems.getByCloudId(cloudId);
        final imagePath = m?.imagePath;
        await isar.writeTxn(() async {
          await isar.memoryItems.deleteByCloudId(cloudId);
        });
        // Best-effort delete of the on-disk image. Failures are ignored:
        // the file may have already been moved or deleted, or the path
        // may be a relative app-doc reference that no longer resolves.
        if (imagePath != null && imagePath.isNotEmpty) {
          try {
            final f = java_io.File(imagePath);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
        break;

      case 'reminders':
        final r = await isar.reminders.getByCloudId(cloudId);
        final notificationId = r?.notificationId;
        await isar.writeTxn(() async {
          await isar.reminders.deleteByCloudId(cloudId);
        });
        if (notificationId != null) {
          try {
            await NotificationService.instance.cancel(notificationId);
          } catch (_) {}
        }
        break;

      case 'habits':
        final h = await isar.habits.getByCloudId(cloudId);
        final notificationId = h?.notificationId;
        await isar.writeTxn(() async {
          await isar.habits.deleteByCloudId(cloudId);
        });
        if (notificationId != null) {
          try {
            await NotificationService.instance.cancel(notificationId);
            // Habits also schedule interval slots at notificationId+i;
            // mirror the cancel-fan-out used by HabitRepository.delete.
            for (var i = 0; i < 24; i++) {
              await NotificationService.instance.cancel(notificationId + i);
            }
          } catch (_) {}
        }
        break;

      case 'habitCompletions':
        await isar.writeTxn(() async {
          await isar.habitCompletions.deleteByCloudId(cloudId);
        });
        break;
    }
  }

  // ── Internals: inbound pipeline ─────────────────────────────────────────

  /// Attach a snapshot listener for [collection] with exponential-backoff
  /// re-attach. The attempt counter is reset on every successful snapshot
  /// delivery so transient errors don't accumulate forever.
  ///
  /// On `permission-denied` the engine stops entirely (Requirement 11.3).
  void _attachWithRetry(String collection) {
    final uid = _uid;
    if (uid == null || !_running) return;

    late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> sub;
    sub = _firestore
        .collection('users/$uid/$collection')
        .snapshots()
        .listen(
      (snap) {
        _attempts[collection] = 0;
        // Snapshot handling is async-by-doc; we don't await the whole
        // pipeline here so the listener stream isn't backpressured.
        unawaited(_handleSnapshot(collection, snap));
      },
      onError: (Object e, StackTrace st) async {
        await sub.cancel();
        _subs.remove(collection);

        if (e is FirebaseException && e.code == 'permission-denied') {
          await _onPermissionDenied();
          return;
        }

        if (!_running) return;

        final n = (_attempts[collection] ?? 0) + 1;
        _attempts[collection] = n;
        // delay = min(60_000, 1000 * 2^(n-1)) ms.
        final delayMs = math.min(
          _kBackoffCap.inMilliseconds,
          1000 * math.pow(2, n - 1).toInt(),
        );
        Timer(Duration(milliseconds: delayMs), () {
          if (_running) _attachWithRetry(collection);
        });
      },
    );
    _subs[collection] = sub;
  }

  /// Iterate `snap.docChanges` and dispatch each change to either
  /// `_applyRemoteUpsert` (live data) or `_handleTombstone` (deleted /
  /// missing data). Tombstone classification is by `data['deletedAt']`,
  /// matching the Firestore document schema.
  Future<void> _handleSnapshot(
    String collection,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    for (final change in snap.docChanges) {
      final doc = change.doc;
      final data = doc.data();

      if (data == null || change.type == DocumentChangeType.removed) {
        // Hard-deleted remotely (sweep collapsed the doc) — defensively
        // mirror the delete locally so the row doesn't stick around.
        await _handleTombstone(collection, doc);
        continue;
      }

      if (data['deletedAt'] != null) {
        await _handleTombstone(collection, doc);
      } else {
        await _applyRemoteUpsert(collection, doc, data);
      }
    }
  }

  /// Apply a non-tombstone document to the local Isar.
  ///
  /// Decision tree:
  /// * No local match → insert with re-derived Device_Local_Fields and
  ///   re-schedule notifications when the row is active.
  /// * Local match, remote `updatedAt` wins → overwrite local, preserving
  ///   the existing Isar pk and the device-local fields (`imagePath`,
  ///   `notificationId`). Re-schedule notifications when relevant.
  /// * Local match, local `updatedAt` wins → skip.
  Future<void> _applyRemoteUpsert(
    String collection,
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
  ) async {
    final cloudId = (data['cloudId'] as String?) ?? doc.id;
    if (cloudId.isEmpty) return;
    final remoteUpdatedAt = _readTimestamp(data['updatedAt']);
    if (remoteUpdatedAt == null) return;

    final echoKey = _echoKey(
      collection,
      cloudId,
      remoteUpdatedAt.millisecondsSinceEpoch,
    );
    _applyingRemote.add(echoKey);

    try {
      switch (collection) {
        case 'memories':
          await _applyRemoteMemory(data, cloudId, remoteUpdatedAt);
          break;
        case 'reminders':
          await _applyRemoteReminder(data, cloudId, remoteUpdatedAt);
          break;
        case 'habits':
          await _applyRemoteHabit(data, cloudId, remoteUpdatedAt);
          break;
        case 'habitCompletions':
          await _applyRemoteCompletion(data, cloudId, remoteUpdatedAt);
          break;
      }
    } catch (e) {
      debugPrint(
        '[FirestoreSyncService] applying remote $collection/$cloudId '
        'failed: $e',
      );
    } finally {
      // Removed on the next microtask so the repository's post-write hook
      // (which runs synchronously after the txn) still sees the flag.
      scheduleMicrotask(() => _applyingRemote.remove(echoKey));
    }
  }

  Future<void> _applyRemoteMemory(
    Map<String, dynamic> data,
    String cloudId,
    DateTime remoteUpdatedAt,
  ) async {
    final isar = DatabaseService.instance.isar;
    final local = await isar.memoryItems.getByCloudId(cloudId);

    if (local == null) {
      // Insert. Re-derive Device_Local_Fields:
      //  * imagePath: null (the binary isn't synced — Requirement 9.4).
      //  * linkedIds: empty. The referenced parents may not be restored
      //    yet; the cross-link is recomputed when the user next edits
      //    a memory through the repository.
      final inserted = mapToMemory(data);
      await isar.writeTxn(() async {
        await isar.memoryItems.put(inserted);
      });
      return;
    }

    final result = _compare(
      remoteUpdatedAt: remoteUpdatedAt,
      remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
      remoteCloudId: cloudId,
      localUpdatedAt: local.updatedAt,
      localOwnerUid: _uid ?? '',
      localCloudId: local.cloudId,
    );
    if (result == _CompareResult.localWins) return;

    // Remote wins: overwrite preserving Isar pk and device-local fields.
    final merged = mapToMemory(data)
      ..id = local.id
      // searchTokens are recomputed by the repository on the next write;
      // until then we preserve the existing tokens so search keeps working.
      ..searchTokens = List<String>.from(local.searchTokens)
      // linkedIds are local-only references; preserve them as-is (the
      // codec leaves them empty so we'd otherwise lose the user's links).
      ..linkedIds = List<int>.from(local.linkedIds)
      ..reminderPromptHandled = local.reminderPromptHandled;

    await isar.writeTxn(() async {
      await isar.memoryItems.put(merged);
    });
  }

  Future<void> _applyRemoteReminder(
    Map<String, dynamic> data,
    String cloudId,
    DateTime remoteUpdatedAt,
  ) async {
    final isar = DatabaseService.instance.isar;
    final local = await isar.reminders.getByCloudId(cloudId);

    // Resolve memoryCloudId → local Isar pk via the parent memory.
    final memoryCloudId = data['memoryCloudId'] as String?;
    int? memoryIsarId;
    if (memoryCloudId != null && memoryCloudId.isNotEmpty) {
      final parent = await isar.memoryItems.getByCloudId(memoryCloudId);
      memoryIsarId = parent?.id;
    }

    if (local == null) {
      // Insert with a placeholder notificationId; we re-derive it from
      // the assigned Isar id and re-put inside the same writeTxn (mirrors
      // the repository's create flow).
      final inserted = mapToReminder(
        data,
        memoryIsarId: memoryIsarId,
        notificationId: 0,
      );
      late int notificationId;
      await isar.writeTxn(() async {
        final id = await isar.reminders.put(inserted);
        notificationId = id & 0x7FFFFFFF;
        inserted.notificationId = notificationId;
        await isar.reminders.put(inserted);
      });

      // Re-schedule the local notification when the reminder is active.
      if (!inserted.completed &&
          inserted.remindAt.isAfter(DateTime.now())) {
        try {
          await NotificationService.instance.schedule(
            id: notificationId,
            title: 'Mnemo reminder',
            body: inserted.text,
            when: inserted.remindAt,
          );
        } catch (_) {}
      }
      return;
    }

    final result = _compare(
      remoteUpdatedAt: remoteUpdatedAt,
      remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
      remoteCloudId: cloudId,
      localUpdatedAt: local.updatedAt,
      localOwnerUid: _uid ?? '',
      localCloudId: local.cloudId,
    );
    if (result == _CompareResult.localWins) return;

    final merged = mapToReminder(
      data,
      memoryIsarId: memoryIsarId,
      notificationId: local.notificationId,
    )..id = local.id;

    // Cancel + re-schedule to pick up the (potentially new) time/body —
    // mirrors `ReminderRepository.update`.
    try {
      await NotificationService.instance.cancel(local.notificationId);
    } catch (_) {}
    await isar.writeTxn(() async {
      await isar.reminders.put(merged);
    });
    if (!merged.completed && merged.remindAt.isAfter(DateTime.now())) {
      try {
        await NotificationService.instance.schedule(
          id: merged.notificationId,
          title: 'Mnemo reminder',
          body: merged.text,
          when: merged.remindAt,
        );
      } catch (_) {}
    }
  }

  Future<void> _applyRemoteHabit(
    Map<String, dynamic> data,
    String cloudId,
    DateTime remoteUpdatedAt,
  ) async {
    final isar = DatabaseService.instance.isar;
    final local = await isar.habits.getByCloudId(cloudId);

    if (local == null) {
      final inserted = mapToHabit(data, notificationId: 0);
      late int notificationId;
      await isar.writeTxn(() async {
        final id = await isar.habits.put(inserted);
        notificationId = (id + 100000) & 0x7FFFFFFF;
        inserted.notificationId = notificationId;
        await isar.habits.put(inserted);
      });

      // Re-schedule when the habit is active.
      if (!inserted.archived && inserted.remindHour != null) {
        try {
          if (inserted.intervalMinutes > 0) {
            await NotificationService.instance.scheduleInterval(
              baseId: notificationId,
              title: '${inserted.emoji ?? '✅'} ${inserted.name}',
              body: 'Time to check off your habit!',
              startHour: inserted.remindHour!,
              endHour: inserted.intervalEndHour,
              intervalMinutes: inserted.intervalMinutes,
            );
          } else {
            await NotificationService.instance.scheduleDaily(
              id: notificationId,
              title: '${inserted.emoji ?? '✅'} ${inserted.name}',
              body: 'Time to check off your habit!',
              hour: inserted.remindHour!,
              minute: inserted.remindMinute ?? 0,
            );
          }
        } catch (_) {}
      }
      return;
    }

    final result = _compare(
      remoteUpdatedAt: remoteUpdatedAt,
      remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
      remoteCloudId: cloudId,
      localUpdatedAt: local.updatedAt,
      localOwnerUid: _uid ?? '',
      localCloudId: local.cloudId,
    );
    if (result == _CompareResult.localWins) return;

    final merged = mapToHabit(data, notificationId: local.notificationId)
      ..id = local.id;

    // Cancel old schedule (single + interval slots) and re-schedule.
    try {
      await NotificationService.instance.cancel(local.notificationId);
      for (var i = 0; i < 24; i++) {
        await NotificationService.instance
            .cancel(local.notificationId + i);
      }
    } catch (_) {}
    await isar.writeTxn(() async {
      await isar.habits.put(merged);
    });
    if (!merged.archived && merged.remindHour != null) {
      try {
        if (merged.intervalMinutes > 0) {
          await NotificationService.instance.scheduleInterval(
            baseId: merged.notificationId,
            title: '${merged.emoji ?? '✅'} ${merged.name}',
            body: 'Time to check off your habit!',
            startHour: merged.remindHour!,
            endHour: merged.intervalEndHour,
            intervalMinutes: merged.intervalMinutes,
          );
        } else {
          await NotificationService.instance.scheduleDaily(
            id: merged.notificationId,
            title: '${merged.emoji ?? '✅'} ${merged.name}',
            body: 'Time to check off your habit!',
            hour: merged.remindHour!,
            minute: merged.remindMinute ?? 0,
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _applyRemoteCompletion(
    Map<String, dynamic> data,
    String cloudId,
    DateTime remoteUpdatedAt,
  ) async {
    final isar = DatabaseService.instance.isar;
    final local = await isar.habitCompletions.getByCloudId(cloudId);

    final habitCloudId = data['habitCloudId'] as String?;
    if (habitCloudId == null || habitCloudId.isEmpty) return;
    final parent = await isar.habits.getByCloudId(habitCloudId);
    if (parent == null) {
      // Parent habit hasn't arrived yet — drop the completion. The next
      // listener delivery (or the next user action that re-puts this
      // completion remotely) will pick it up once the parent is restored.
      return;
    }

    if (local == null) {
      final inserted = mapToCompletion(data, habitIsarId: parent.id);
      await isar.writeTxn(() async {
        await isar.habitCompletions.put(inserted);
      });
      return;
    }

    final result = _compare(
      remoteUpdatedAt: remoteUpdatedAt,
      remoteOwnerUid: (data['ownerUid'] as String?) ?? '',
      remoteCloudId: cloudId,
      localUpdatedAt: local.updatedAt,
      localOwnerUid: _uid ?? '',
      localCloudId: local.cloudId,
    );
    if (result == _CompareResult.localWins) return;

    final merged = mapToCompletion(data, habitIsarId: parent.id)
      ..id = local.id;
    await isar.writeTxn(() async {
      await isar.habitCompletions.put(merged);
    });
  }

  /// Apply a tombstone document (live-listener path or sweep-removed doc).
  /// Hard-deletes the local row and cancels any associated device-local
  /// notification / on-disk image.
  Future<void> _handleTombstone(
    String collection,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final cloudId = doc.id;
    if (cloudId.isEmpty) return;

    // Same suppress-echo guard around the local hard-delete: any
    // repository observer that fires on the inbound delete sees the key
    // and skips re-uploading the tombstone we just received.
    //
    // Tombstones carry a `deletedAt` timestamp; use it to key the guard
    // so genuine local re-creates (which advance updatedAt) still flow.
    DateTime? remoteUpdatedAt;
    final data = doc.data();
    if (data != null) {
      remoteUpdatedAt = _readTimestamp(data['updatedAt']);
    }
    final updatedAtMs =
        remoteUpdatedAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    final echoKey = _echoKey(collection, cloudId, updatedAtMs);
    _applyingRemote.add(echoKey);

    try {
      final isar = DatabaseService.instance.isar;
      await _hardDeleteLocalByCloudId(isar, collection, cloudId);
    } catch (e) {
      debugPrint(
        '[FirestoreSyncService] applying tombstone $collection/$cloudId '
        'failed: $e',
      );
    } finally {
      scheduleMicrotask(() => _applyingRemote.remove(echoKey));
    }
  }

  // ── Internals: permission-denied kill-switch ────────────────────────────

  /// Stops the engine, disables sync, and stores a sign-in-required
  /// message for Settings to render. Idempotent — calling it twice does
  /// nothing additional.
  Future<void> _onPermissionDenied() async {
    lastError = 'Sign-in required';
    await stop();
    try {
      await SettingsService.instance.setSyncEnabled(false);
    } catch (_) {}
  }

  // ── Internals: helpers ──────────────────────────────────────────────────

  /// Compares a remote document and a local row under the last-write-wins
  /// policy. `updatedAt` greater wins; on tie, lexicographic
  /// `(ownerUid, cloudId)` decides — guarantees determinism even when
  /// two devices race the same wall-clock millisecond (Requirement 7.2).
  _CompareResult _compare({
    required DateTime remoteUpdatedAt,
    required String remoteOwnerUid,
    required String remoteCloudId,
    required DateTime localUpdatedAt,
    required String localOwnerUid,
    required String localCloudId,
  }) {
    final cmp = remoteUpdatedAt.compareTo(localUpdatedAt);
    if (cmp > 0) return _CompareResult.remoteWins;
    if (cmp < 0) return _CompareResult.localWins;
    final r = '$remoteOwnerUid|$remoteCloudId';
    final l = '$localOwnerUid|$localCloudId';
    return r.compareTo(l) > 0
        ? _CompareResult.remoteWins
        : _CompareResult.localWins;
  }

  String _echoKey(String collection, String cloudId, int updatedAtMs) =>
      '$collection|$cloudId|$updatedAtMs';

  /// Pulls `cloudId` off any of the four supported model types.
  /// Returns the empty string for unknown inputs so callers no-op safely.
  String _cloudIdOf(dynamic item) {
    if (item is MemoryItem) return item.cloudId;
    if (item is Reminder) return item.cloudId;
    if (item is Habit) return item.cloudId;
    if (item is HabitCompletion) return item.cloudId;
    return '';
  }

  /// Pulls `updatedAt.millisecondsSinceEpoch` off any of the four model
  /// types. Returns 0 for unknown inputs (which then keys the suppress-echo
  /// guard at `(collection, cloudId, 0)` — never matches a real remote).
  int _updatedAtMsOf(dynamic item) {
    if (item is MemoryItem) return item.updatedAt.millisecondsSinceEpoch;
    if (item is Reminder) return item.updatedAt.millisecondsSinceEpoch;
    if (item is Habit) return item.updatedAt.millisecondsSinceEpoch;
    if (item is HabitCompletion) return item.updatedAt.millisecondsSinceEpoch;
    return 0;
  }

  /// `createdAt` for any of the four model types. `HabitCompletion` has
  /// no `createdAt` field on the local model — its `completedAt` is used
  /// by the codec as the envelope `createdAt`, so we mirror that here.
  /// Returns null for unknown inputs.
  DateTime? _createdAtOf(dynamic item) {
    if (item is MemoryItem) return item.createdAt;
    if (item is Reminder) return item.createdAt;
    if (item is Habit) return item.createdAt;
    if (item is HabitCompletion) return item.completedAt;
    return null;
  }

  DateTime? _readTimestamp(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Dispatches on [collection] to the matching `sync_codec` function.
  ///
  /// Reference resolution — `linkedIds → linkedCloudIds` for memories,
  /// `memoryId → memoryCloudId` for reminders, `habitId → habitCloudId`
  /// for completions — happens here by reading the parent row out of Isar
  /// by primary key. The codec itself stays pure.
  Future<Map<String, dynamic>> _serialize(
    String uid,
    String collection,
    dynamic item,
  ) async {
    final isar = DatabaseService.instance.isar;
    switch (collection) {
      case 'memories':
        final m = item as MemoryItem;
        final linkedCloudIds = <String>[];
        for (final pk in m.linkedIds) {
          final parent = await isar.memoryItems.get(pk);
          if (parent != null && parent.cloudId.isNotEmpty) {
            linkedCloudIds.add(parent.cloudId);
          }
        }
        return memoryToMap(m, ownerUid: uid, linkedCloudIds: linkedCloudIds);

      case 'reminders':
        final r = item as Reminder;
        String? memoryCloudId;
        final memoryPk = r.memoryId;
        if (memoryPk != null) {
          final parent = await isar.memoryItems.get(memoryPk);
          if (parent != null && parent.cloudId.isNotEmpty) {
            memoryCloudId = parent.cloudId;
          }
        }
        return reminderToMap(r, ownerUid: uid, memoryCloudId: memoryCloudId);

      case 'habits':
        final h = item as Habit;
        return habitToMap(h, ownerUid: uid);

      case 'habitCompletions':
        final c = item as HabitCompletion;
        final parent = await isar.habits.get(c.habitId);
        if (parent == null || parent.cloudId.isEmpty) {
          // Without a resolvable parent cloudId we'd violate Requirement
          // 10.6 (habit completions reference the habit's cloudId). Drop
          // the write — it'll be picked up on the next mutation once the
          // parent has been synced.
          throw StateError(
            'FirestoreSyncService: habit completion ${c.cloudId} has no '
            'cloud-resolvable parent habit (habitId=${c.habitId})',
          );
        }
        return completionToMap(
          c,
          ownerUid: uid,
          habitCloudId: parent.cloudId,
        );

      default:
        throw ArgumentError(
          'FirestoreSyncService: unknown collection "$collection"',
        );
    }
  }
}
