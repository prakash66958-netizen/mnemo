import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../services/share_intent_service.dart';
import '../../widgets/mnemo_nav_bar.dart';
import '../categories/categories_tab.dart';
import '../focus/focus_tab.dart';
import '../inbox/inbox_tab.dart';
import '../reminder/reminders_tab.dart';
import '../settings/settings_tab.dart';
import '../shared/providers.dart';
import 'quick_add_sheet.dart';

/// Root scaffold for the app's five primary sections.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final List<Widget> _tabs;
  StreamSubscription<AppToast>? _toastSub;

  @override
  void initState() {
    super.initState();
    _tabs = const [
      InboxTab(),
      CategoriesTab(),
      FocusTab(),
      RemindersTab(),
      SettingsTab(),
    ];
    _listenForShares();
    _listenForToasts();
  }

  @override
  void dispose() {
    _toastSub?.cancel();
    super.dispose();
  }

  void _listenForToasts() {
    _toastSub = appToastProvider.stream.listen((toast) {
      if (!mounted) return;
      // Show a centered overlay toast instead of a snackbar — snackbars
      // were getting stuck due to ScaffoldMessenger conflicts between
      // nested Scaffolds. An OverlayEntry is independent of all that.
      _showOverlayToast(toast);
    });
  }

  void _showOverlayToast(AppToast toast) {
    // Use the GoRouter's root navigator's overlay so the toast always lands
    // on the TOPMOST overlay, even when another screen (reminder edit,
    // habit editor, etc.) is pushed on top of the HomeShell.
    final navState = appRouter.routerDelegate.navigatorKey.currentState;
    final overlay = navState?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    Timer? dismissTimer;
    entry = OverlayEntry(
      builder: (ctx) => _OverlayToast(
        message: toast.message,
        actionLabel: toast.actionLabel,
        onAction: () {
          dismissTimer?.cancel();
          if (entry.mounted) entry.remove();
          toast.onAction?.call();
        },
        onDismiss: () {
          dismissTimer?.cancel();
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
    dismissTimer = Timer(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }

  void _listenForShares() {
    ShareIntentService.instance.onNewMemory.listen((mem) {
      showAppToast(
        'Saved to Mnemo',
        actionLabel: 'Open',
        onAction: () => appRouter.push('/memory/${mem.id}'),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(shellTabProvider);
    final scheme = Theme.of(context).colorScheme;
    const inboxTabIndex = 0;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: tab, children: _tabs),
      floatingActionButton: tab == inboxTabIndex
          ? SizedBox(
              width: 58,
              height: 58,
              child: FloatingActionButton(
                onPressed: () => _openQuickAdd(context),
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: MnemoNavBar(
        currentIndex: tab,
        onChanged: (i) => ref.read(shellTabProvider.notifier).state = i,
        items: const [
          MnemoNavItem(
            icon: Icons.inbox_outlined,
            activeIcon: Icons.inbox_rounded,
            label: 'Inbox',
          ),
          MnemoNavItem(
            icon: Icons.grid_view_outlined,
            activeIcon: Icons.grid_view_rounded,
            label: 'Browse',
          ),
          MnemoNavItem(
            icon: Icons.center_focus_weak_outlined,
            activeIcon: Icons.center_focus_strong_rounded,
            label: 'Focus',
          ),
          MnemoNavItem(
            icon: Icons.alarm_outlined,
            activeIcon: Icons.alarm_rounded,
            label: 'Remind',
          ),
          MnemoNavItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'Me',
          ),
        ],
      ),
    );
  }

  Future<void> _openQuickAdd(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const QuickAddSheet(),
    );
  }
}

/// Centered overlay toast that appears in the middle of the screen and
/// auto-dismisses. Completely independent of ScaffoldMessenger so it never
/// gets stuck.
class _OverlayToast extends StatefulWidget {
  const _OverlayToast({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  // Currently unused — reserved for a tap-to-dismiss gesture in a future
  // iteration. Keep the field so callers that already pass it stay valid.
  // ignore: unused_element, unused_element_parameter
  final VoidCallback? onDismiss;

  @override
  State<_OverlayToast> createState() => _OverlayToastState();
}

class _OverlayToastState extends State<_OverlayToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..forward();
    // Start fade-out before auto-dismiss.
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _anim.reverse();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 32,
      right: 32,
      top: MediaQuery.of(context).size.height * 0.42,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _anim, curve: Curves.easeOut),
        child: Material(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(16),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 20, color: scheme.inversePrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: scheme.onInverseSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.actionLabel != null) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: widget.onAction,
                    child: Text(
                      widget.actionLabel!,
                      style: TextStyle(
                        color: scheme.inversePrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
