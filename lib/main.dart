import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/category_service.dart';
import 'services/database_service.dart';
import 'services/firestore_sync_service.dart';
import 'services/isar_migration_service.dart';
import 'services/notification_service.dart';

/// Container for boot-time errors that should be surfaced once on the
/// settings screen instead of crashing the app.
///
/// Requirement 1.5: a Firebase initialization failure must not block boot;
/// the error is captured here so the settings UI can render a non-blocking
/// banner explaining that cloud sync is unavailable.
class AppBootError {
  AppBootError._();

  /// The exception thrown by [Firebase.initializeApp] (or by any subsequent
  /// step inside the same try block, e.g. [AuthService.init]) on the most
  /// recent boot. `null` when Firebase came up cleanly.
  static Object? firebase;
}

/// Entry point. We intentionally keep initialization lean so the app feels
/// fast on cold start. Heavy work (Isar open, timezone init) is awaited here
/// but kept to a minimum. Each step is wrapped in try/catch so a single
/// failure (e.g. Isar schema mismatch) doesn't leave the user on a black
/// screen forever.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await DatabaseService.instance.open();
  } catch (e) {
    debugPrint('[main] DatabaseService.open() failed: $e');
  }
  // One-time UUID / `updatedAt` backfill so cloud sync has stable
  // cross-device document ids and conflict-resolution keys for every
  // legacy row. Wrapped in its own try/catch — a migration failure must
  // not block boot; in the worst case the affected rows simply don't
  // sync until the user next edits them through the repository.
  try {
    await IsarMigrationService.instance.run();
  } catch (e) {
    debugPrint('[main] IsarMigrationService.run() failed: $e');
  }
  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('[main] NotificationService.init() failed: $e');
  }
  try {
    // Warm the custom-category cache so widgets can resolve synchronously.
    await CategoryService.instance.loadCustom();
  } catch (e) {
    debugPrint('[main] CategoryService.loadCustom() failed: $e');
  }

  // Firebase + Auth bootstrap. Wrapped in a single try/catch so any failure
  // here (Firebase init, Firestore settings, AuthService silent restore, or
  // FirestoreSyncService bootstrap) is captured in [AppBootError.firebase]
  // without blocking app launch. Sync stays effectively disabled when this
  // block fails because FirestoreSyncService.init() is skipped and the
  // settings screen treats the boot error as a non-blocking banner.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    await AuthService.instance.init();
    await FirestoreSyncService.instance.init();
  } catch (e) {
    debugPrint('[main] Firebase / AuthService init failed: $e');
    AppBootError.firebase = e;
  }

  runApp(const ProviderScope(child: MnemoApp()));
}
