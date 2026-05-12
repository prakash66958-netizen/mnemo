import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/category_service.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';

/// Entry point. We intentionally keep initialization lean so the app feels
/// fast on cold start. Heavy work (Isar open, timezone init) is awaited here
/// but kept to a minimum.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DatabaseService.instance.open();
  await NotificationService.instance.init();
  // Warm the custom-category cache so widgets can resolve synchronously.
  await CategoryService.instance.loadCustom();

  runApp(const ProviderScope(child: MnemoApp()));
}
