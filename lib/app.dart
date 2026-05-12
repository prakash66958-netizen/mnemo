import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/shared/providers.dart';
import 'features/home/home_shell.dart';
import 'features/home/share_preview_sheet.dart';
import 'features/memory/memory_detail_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/reminder/reminder_edit_screen.dart';
import 'features/save/save_screen.dart';
import 'services/reminder_repository.dart';
import 'services/settings_service.dart';
import 'services/share_intent_service.dart';
import 'services/habit_repository.dart';

/// App-level messenger key so bottom sheets / screens that dismiss themselves
/// before showing a snackbar can still reach a live Messenger (the root one)
/// instead of the already-popped screen's local one.
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// App-level navigator key — currently unused but kept for future use.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// The app's GoRouter instance, exposed so code that runs after a sheet/screen
/// has popped (e.g. snackbar action callbacks) can still navigate without
/// needing a live BuildContext.
late final GoRouter appRouter;

/// Root widget. Sets up MaterialApp.router, Riverpod, theme, and the initial
/// share-intent + reminder rescheduling.
class MnemoApp extends ConsumerStatefulWidget {
  const MnemoApp({super.key});

  @override
  ConsumerState<MnemoApp> createState() => _MnemoAppState();
}

class _MnemoAppState extends ConsumerState<MnemoApp> {
  late final GoRouter _router;
  bool _bootstrapDone = false;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
    appRouter = _router;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Reschedule any active reminders after restart.
    await ReminderRepository.instance.rescheduleAll();
    // Reschedule daily habit notifications.
    await HabitRepository.instance.rescheduleAll();
    // Subscribe to pending shares BEFORE starting the service so cold-start
    // shares (which fire synchronously during start()) aren't missed.
    ShareIntentService.instance.pendingShare.listen(_showSharePreview);
    // Kick off share-intent listening.
    await ShareIntentService.instance.start();
    // Check whether to show onboarding.
    final done = await SettingsService.instance.getOnboardingDone();
    if (mounted) {
      setState(() {
        _showOnboarding = !done;
        _bootstrapDone = true;
      });
    }
  }

  void _showSharePreview(PendingShare pending) {
    _tryShowSheet(pending, 0);
  }

  void _tryShowSheet(PendingShare pending, int attempt) {
    if (attempt > 30) return; // give up after ~30 frames (~500ms)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Use the router's navigator context — it has both a Navigator ancestor
      // (for showModalBottomSheet) and the GoRouter (for push/pop).
      final navContext = _router.routerDelegate.navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) {
        _tryShowSheet(pending, attempt + 1);
        return;
      }
      showModalBottomSheet<bool>(
        context: navContext,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SharePreviewSheet(pending: pending),
      );
    });
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const HomeShell(),
        ),
        GoRoute(
          path: '/save',
          builder: (_, state) {
            final extra = state.extra;
            if (extra is String) {
              return SaveScreen(prefillText: extra);
            }
            if (extra is Map) {
              return SaveScreen(
                prefillText: extra['text'] as String?,
                prefillCategoryId: extra['categoryId'] as String?,
                editMemoryId: extra['editMemoryId'] as int?,
              );
            }
            return const SaveScreen();
          },
        ),
        GoRoute(
          path: '/memory/:id',
          builder: (_, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return MemoryDetailScreen(memoryId: id);
          },
        ),
        GoRoute(
          path: '/reminder/new',
          builder: (_, state) {
            final extra = state.extra;
            return ReminderEditScreen(
              memoryId:
                  extra is Map ? extra['memoryId'] as int? : null,
              initialText:
                  extra is Map ? extra['text'] as String? : null,
              initialTime:
                  extra is Map ? extra['time'] as DateTime? : null,
            );
          },
        ),
        GoRoute(
          path: '/reminder/edit/:id',
          builder: (_, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return ReminderEditScreen(reminderId: id);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    if (!_bootstrapDone) {
      // Minimal splash — keeps cold start feeling instant.
      return MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: const _SplashScreen(),
        debugShowCheckedModeBanner: false,
      );
    }

    if (_showOnboarding) {
      return MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        home: OnboardingScreen(
          onDone: () {
            setState(() => _showOnboarding = false);
          },
        ),
      );
    }

    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      scaffoldMessengerKey: appMessengerKey,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.bolt_rounded,
                size: 44,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              AppConstants.appTagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
