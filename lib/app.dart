import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
import 'services/update_service.dart';
import 'services/google_drive_service.dart';

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
    try {
      // Reschedule any active reminders after restart.
      await ReminderRepository.instance.rescheduleAll();
    } catch (_) {
      // Non-fatal: reminders won't fire until next app start, but the app
      // must not hang on the splash screen.
    }
    try {
      // Reschedule daily habit notifications.
      await HabitRepository.instance.rescheduleAll();
    } catch (_) {}
    try {
      // Subscribe to pending shares BEFORE starting the service so cold-start
      // shares (which fire synchronously during start()) aren't missed.
      ShareIntentService.instance.pendingShare.listen(_showSharePreview);
      // Kick off share-intent listening.
      await ShareIntentService.instance.start();
    } catch (_) {}
    // Check whether to show onboarding.
    bool done = false;
    try {
      done = await SettingsService.instance.getOnboardingDone();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _showOnboarding = !done;
        _bootstrapDone = true;
      });
    }

    // Auto update check — runs on every launch after the UI is ready.
    // We delay slightly so the first frame is painted before the network call.
    if (done) {
      Future.delayed(const Duration(seconds: 2), _autoCheckForUpdate);
      // Auto Drive sync — runs silently if the user is signed in.
      Future.delayed(const Duration(seconds: 4), _autoSync);
    }
  }

  /// Silently syncs with Google Drive on launch if the user is signed in.
  Future<void> _autoSync() async {
    if (!GoogleDriveService.instance.isSignedIn) return;
    try {
      final result = await GoogleDriveService.instance.syncNow();
      if (result.success && mounted) {
        // Update the provider so the settings tab reflects the new timestamp.
        final ctx = _router.routerDelegate.navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          final container = ProviderScope.containerOf(ctx);
          container.read(lastDriveSyncProvider.notifier)
              .set(DateTime.now());
          if (result.mergedItems > 0) {
            appMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text(
                    'Drive sync: ${result.mergedItems} new items restored'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (_) {
      // Sync errors are silently swallowed on auto-sync.
    }
  }

  /// Checks for a new release on every app launch.
  /// Shows the full update sheet when a newer version is available.
  /// Network errors are silently swallowed — this is best-effort.
  Future<void> _autoCheckForUpdate() async {
    try {
      final info = await UpdateService.instance.fetchLatest();
      await SettingsService.instance.setLastUpdateCheck(DateTime.now());

      if (!info.isNewer || !mounted) return;

      // Use the router's navigator context so the sheet has a proper
      // Navigator ancestor even if the user has already navigated.
      final navContext =
          _router.routerDelegate.navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;

      await showModalBottomSheet<void>(
        context: navContext,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: true,
        builder: (_) => _AutoUpdateSheet(info: info),
      );
    } catch (_) {
      // Network / parse errors are silently ignored.
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

// ── Auto-update sheet shown on launch when a newer version is available ───────

class _AutoUpdateSheet extends StatelessWidget {
  const _AutoUpdateSheet({required this.info});
  final ReleaseInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateStr = DateFormat('MMM d, y').format(info.publishedAt);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle.
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.system_update_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'v${info.version} available',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Released $dateStr · you have v${AppConstants.appVersion}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Release notes.
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Text(
                    "What's new",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      info.body.isEmpty
                          ? 'No release notes provided.'
                          : info.body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            // Action buttons.
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.paddingOf(context).bottom + 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        final url = info.apkUrl.isNotEmpty
                            ? info.apkUrl
                            : info.htmlUrl;
                        if (url.isEmpty) return;
                        try {
                          await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download update'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
