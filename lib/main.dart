import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/category_service.dart';
import 'services/database_service.dart';
import 'services/google_drive_service.dart';
import 'services/notification_service.dart';

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
  try {
    // Restore the previously signed-in Google account silently.
    await GoogleDriveService.instance.init();
  } catch (e) {
    debugPrint('[main] GoogleDriveService.init() failed: $e');
  }

  runApp(const ProviderScope(child: MnemoApp()));
}
