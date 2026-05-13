import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../services/google_drive_service.dart';
import '../../services/settings_service.dart';
import '../shared/providers.dart';

/// Four-step onboarding. The first three pages pitch the app; the last
/// page asks the user to make an explicit, informed choice about backup
/// (Google sign-in is flagged as upcoming — we ship offline-first today).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  final _pages = const [
    _OnboardData(
      icon: Icons.bolt_rounded,
      title: 'Save anything in seconds',
      body:
          'Notes, links, screenshots, chat messages — drop them into Mnemo '
          'from anywhere with the share sheet.',
      accent: Color(0xFF4F46E5),
    ),
    _OnboardData(
      icon: Icons.auto_awesome_rounded,
      title: 'Understands everyday life',
      body:
          "Mnemo quietly spots promises like \u201cI'll send tomorrow\u201d "
          'and offers to set a reminder, all on your device.',
      accent: Color(0xFFF59E0B),
    ),
    _OnboardData(
      icon: Icons.lock_rounded,
      title: 'Private by default',
      body:
          'No cloud. No accounts. No analytics. Your memories live only on '
          "this phone \u2014 that's the whole point.",
      accent: Color(0xFF10B981),
    ),
  ];

  int get _totalPages => _pages.length + 1; // +1 for the backup choice page

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackupPage = _page == _pages.length;
    final showNext = !isBackupPage;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: _totalPages,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  if (i < _pages.length) {
                    return _OnboardPage(data: _pages[i]);
                  }
                  return _BackupChoicePage(onContinue: _finish);
                },
              ),
            ),
            // Page indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 6,
                  width: active ? 22 : 6,
                  decoration: BoxDecoration(
                    color: active
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: Row(
                children: [
                  if (showNext)
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Skip'),
                    ),
                  const Spacer(),
                  if (showNext)
                    FilledButton(
                      onPressed: () => _pc.nextPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      ),
                      child: const Text('Next'),
                    ),
                ],
              ),
            ),
            if (showNext)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${AppConstants.appName} works offline. No account required.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish() async {
    await SettingsService.instance.setOnboardingDone(true);
    widget.onDone();
  }
}

class _OnboardPage extends StatelessWidget {
  const _OnboardPage({required this.data});
  final _OnboardData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: data.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(data.icon, size: 48, color: data.accent),
          ),
          const SizedBox(height: 28),
          Text(
            data.title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            data.body,
            style: TextStyle(
              fontSize: 16,
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Final onboarding step: the user picks how they want their data backed up.
class _BackupChoicePage extends ConsumerStatefulWidget {
  const _BackupChoicePage({required this.onContinue});
  final VoidCallback onContinue;

  @override
  ConsumerState<_BackupChoicePage> createState() => _BackupChoicePageState();
}

class _BackupChoicePageState extends ConsumerState<_BackupChoicePage> {
  bool _signingIn = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _signingIn = true);
    try {
      final account = await GoogleDriveService.instance.signIn();
      if (account == null || !mounted) {
        setState(() => _signingIn = false);
        return;
      }
      // Persist the email in the provider.
      ref.read(googleEmailProvider.notifier).set(account.email);

      // Restore any existing Drive backup before finishing onboarding.
      await GoogleDriveService.instance.restoreFromDrive();
      // Full sync to upload local data too.
      final sync = await GoogleDriveService.instance.syncNow();
      if (sync.success && mounted) {
        ref.read(lastDriveSyncProvider.notifier).set(DateTime.now());
      }
    } catch (_) {
      // Sign-in failure is non-fatal — fall through to finish onboarding.
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.backup_rounded,
              size: 40,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'How do you want to back up?',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Sign in with Google to automatically back up and sync your data '
            'across devices. Or continue offline — you can always connect '
            'later from Settings.',
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          _BackupOptionCard(
            icon: Icons.add_to_drive_rounded,
            iconColor: const Color(0xFF4285F4),
            title: 'Sign in with Google',
            body:
                'Automatic backup to Google Drive. Restore your data on any '
                'device by signing in with the same account.',
            trailingBadge: 'Recommended',
            onTap: _signingIn ? null : _signInWithGoogle,
            primary: true,
            loading: _signingIn,
          ),
          const SizedBox(height: 12),
          _BackupOptionCard(
            icon: Icons.cloud_off_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Continue without backup',
            body:
                'Your memories stay only on this phone. Fastest, fully private '
                '— but if you lose this device, your data goes with it.',
            trailingBadge: 'Offline',
            onTap: widget.onContinue,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Without backup your data will not be available if the app '
                    'is reinstalled or the device is lost. You can always '
                    'connect Google Drive from Settings.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _BackupOptionCard extends StatelessWidget {
  const _BackupOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.trailingBadge,
    required this.onTap,
    this.primary = false,
    this.loading = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String trailingBadge;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = onTap == null && !loading;
    return Opacity(
      opacity: disabled ? 0.7 : 1,
      child: Material(
        color: primary
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: iconColor),
                        )
                      : Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              trailingBadge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardData {
  const _OnboardData({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
}
