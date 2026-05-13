import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/design_tokens.dart';
import '../../services/database_service.dart';
import '../../services/google_drive_service.dart';
import '../../services/memory_repository.dart';
import '../../services/settings_service.dart';
import '../../services/share_out_service.dart';
import '../../services/update_service.dart';
import '../shared/providers.dart';

/// "Me" tab — settings, theme, backup, privacy reassurance.
/// Follows the same app-bar and surface conventions as the other tabs.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(themeModeProvider);
    // Live version from the installed package — auto-updates with pubspec.
    final version = ref.watch(appVersionProvider).maybeWhen(
          data: (v) => v,
          orElse: () => AppConstants.appVersion, // fallback while loading
        );

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Me',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Your settings',
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
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                children: [
                  _PrivacyHero(),
                  const SizedBox(height: 14),
                  _Group(
                    title: 'Appearance',
                    children: [
                      _Row(
                        icon: Icons.palette_outlined,
                        iconColor: const Color(0xFF8B5CF6),
                        title: 'Theme',
                        trailing: SegmentedButton<ThemeMode>(
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_rounded),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_rounded),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_rounded),
                            ),
                          ],
                          selected: {mode},
                          onSelectionChanged: (s) =>
                              ref.read(themeModeProvider.notifier).set(s.first),
                        ),
                      ),
                    ],
                  ),
                  _Group(
                    title: 'Inbox',
                    children: [
                      _CheckboxToggleRow(),
                      _AutoDeleteRow(),
                    ],
                  ),
                  _Group(
                    title: 'Data',
                    children: [
                      _GoogleDriveRow(),
                      _Row(
                        icon: Icons.upload_rounded,
                        iconColor: const Color(0xFF10B981),
                        title: 'Export backup',
                        subtitle: 'Save a local JSON backup file.',
                        onTap: () => _exportBackup(context),
                      ),
                      _Row(
                        icon: Icons.download_rounded,
                        iconColor: const Color(0xFF3B82F6),
                        title: 'Import backup',
                        subtitle: 'Restore from a Mnemo JSON file.',
                        onTap: () => _importBackup(context),
                      ),
                      _Row(
                        icon: Icons.delete_forever_rounded,
                        iconColor: const Color(0xFFEF4444),
                        title: 'Clear all data',
                        subtitle: 'Permanently delete every saved memory.',
                        onTap: () => _confirmClear(context),
                      ),
                    ],
                  ),
                  _Group(
                    title: 'About',
                    children: [
                      _UpdateCheckRow(version: version),
                      _Row(
                        icon: Icons.language_rounded,
                        iconColor: const Color(0xFF0EA5E9),
                        title: 'Visit website',
                        subtitle: 'getmnemo.web.app',
                        onTap: () => _openWebsite(context),
                      ),
                      _Row(
                        icon: Icons.info_outline_rounded,
                        iconColor: const Color(0xFF64748B),
                        title: AppConstants.appName,
                        subtitle:
                            '${AppConstants.appTagline} · v$version',
                        onTap: null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context) async {
    try {
      final data = await MemoryRepository.instance.exportAll();
      final dir = await getTemporaryDirectory();
      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final file = File(p.join(dir.path, 'mnemo_backup_$dateStr.json'));
      await file.writeAsString(jsonEncode(data));
      final memCount = (data['memories'] as List?)?.length ?? 0;
      final habitCount = (data['habits'] as List?)?.length ?? 0;
      final remindCount = (data['reminders'] as List?)?.length ?? 0;
      final result = await ShareOutService.instance.shareFile(
        file,
        subject: 'Mnemo backup',
        text:
            'Mnemo backup · $memCount memories · $remindCount reminders · '
            '$habitCount habits · $dateStr',
      );
      if (!context.mounted) return;
      if (result.status == ShareResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup shared')),
        );
      }
      // Clean up temp file after sharing.
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final raw = await File(path).readAsString();
      // Accepts both legacy format (top-level array) and new v2 format
      // (object with memories/reminders/habits/habitCompletions keys).
      final decoded = jsonDecode(raw);
      final count = await MemoryRepository.instance.importFromJson(decoded);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $count items')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  Future<void> _openWebsite(BuildContext context) async {
    final uri = Uri.parse('https://getmnemo.web.app/');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser')),
        );
      }
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'Every saved memory and reminder will be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseService.instance.clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared')),
        );
      }
    }
  }
}

// ── Google Drive backup row ───────────────────────────────────────────────────

class _GoogleDriveRow extends ConsumerStatefulWidget {
  @override
  ConsumerState<_GoogleDriveRow> createState() => _GoogleDriveRowState();
}

class _GoogleDriveRowState extends ConsumerState<_GoogleDriveRow> {
  bool _syncing = false;
  bool _signInFailed = false; // true after a sign-in failure, reset on retry

  String _syncLabel(DateTime? last) {
    if (last == null) return 'Never synced';
    final diff = DateTime.now().difference(last);
    if (diff.inSeconds < 60) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Synced yesterday';
    return 'Synced ${diff.inDays}d ago';
  }

  Future<void> _signIn() async {
    setState(() {
      _syncing = true;
      _signInFailed = false;
    });
    try {
      final account = await GoogleDriveService.instance.signIn();
      if (account == null || !mounted) {
        setState(() => _syncing = false);
        return; // user cancelled
      }
      ref.read(googleEmailProvider.notifier).set(account.email);

      // Restore from Drive first, then upload merged result.
      final restore = await GoogleDriveService.instance.restoreFromDrive();
      final sync = await GoogleDriveService.instance.syncNow();
      if (!mounted) return;
      ref.read(lastDriveSyncProvider.notifier).set(DateTime.now());
      final total = restore.mergedItems + sync.mergedItems;
      if (total > 0) {
        showAppToast('Restored $total items from Drive');
      } else {
        showAppToast('Google Drive backup linked');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _signInFailed = true);
      final msg = e.toString();
      final friendly = msg.contains('sign_in_canceled')
          ? null
          : msg.contains('network_error')
              ? 'No internet connection'
              : 'Sign-in failed: $msg';
      if (friendly != null) showAppToast(friendly);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final result = await GoogleDriveService.instance.syncNow();
      if (!mounted) return;
      if (result.success) {
        ref.read(lastDriveSyncProvider.notifier).set(DateTime.now());
        showAppToast(result.mergedItems > 0
            ? 'Synced — ${result.mergedItems} new items restored'
            : 'Drive backup up to date');
      } else {
        showAppToast('Sync failed: ${result.error}');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of Google?'),
        content: const Text(
          'Your local data stays on this device. '
          'Automatic Drive backup will stop until you sign in again.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await GoogleDriveService.instance.signOut();
    ref.read(googleEmailProvider.notifier).set(null);
    ref.read(lastDriveSyncProvider.notifier).set(null);
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(googleEmailProvider);
    final lastSync = ref.watch(lastDriveSyncProvider);
    final scheme = Theme.of(context).colorScheme;

    // ── Not signed in ────────────────────────────────────────────────────────
    if (email == null) {
      return _Row(
        icon: _signInFailed
            ? Icons.error_outline_rounded
            : Icons.add_to_drive_rounded,
        iconColor: _signInFailed
            ? scheme.error
            : const Color(0xFF4285F4),
        title: 'Back up to Google Drive',
        subtitle: _signInFailed
            ? 'Sign-in failed — tap to retry'
            : 'Auto-sync your data across devices',
        onTap: _syncing ? null : _signIn,
        trailing: _syncing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: scheme.primary),
              )
            : _signInFailed
                ? Icon(Icons.close_rounded, color: scheme.error, size: 22)
                : null,
      );
    }

    // ── Signed in ────────────────────────────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Drive icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_to_drive_rounded,
                color: Color(0xFF4285F4), size: 20),
          ),
          const SizedBox(width: 12),
          // Email + sync status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      lastSync != null
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      size: 13,
                      color: lastSync != null
                          ? const Color(0xFF4285F4)
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _syncLabel(lastSync),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action buttons
          if (_syncing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: scheme.primary),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  tooltip: 'Sync now',
                  color: const Color(0xFF4285F4),
                  onPressed: _syncNow,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.logout_rounded,
                      color: scheme.onSurfaceVariant),
                  tooltip: 'Sign out',
                  onPressed: _signOut,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Update check row with "last checked" subtitle ────────────────────────────

class _UpdateCheckRow extends StatefulWidget {
  const _UpdateCheckRow({required this.version});
  final String version;

  @override
  State<_UpdateCheckRow> createState() => _UpdateCheckRowState();
}

class _UpdateCheckRowState extends State<_UpdateCheckRow> {
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    _loadLastCheck();
  }

  Future<void> _loadLastCheck() async {
    final t = await SettingsService.instance.getLastUpdateCheck();
    if (mounted) setState(() => _lastCheck = t);
  }

  String get _subtitle {
    if (_lastCheck == null) {
      return 'Current version: ${widget.version} · Never checked';
    }
    final diff = DateTime.now().difference(_lastCheck!);
    final String ago;
    if (diff.inMinutes < 1) {
      ago = 'just now';
    } else if (diff.inMinutes < 60) {
      ago = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      ago = '${diff.inHours}h ago';
    } else {
      ago = '${diff.inDays}d ago';
    }
    return 'v${widget.version} · Last checked $ago';
  }

  @override
  Widget build(BuildContext context) {
    return _Row(
      icon: Icons.system_update_rounded,
      iconColor: const Color(0xFF4F46E5),
      title: 'Check for updates',
      subtitle: _subtitle,
      onTap: () async {
        await _checkForUpdates(context);
        _loadLastCheck(); // refresh the "last checked" label after manual check
      },
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CheckingDialog(),
    );
    try {
      final info = await UpdateService.instance.fetchLatest();
      await SettingsService.instance.setLastUpdateCheck(DateTime.now());
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (info.isNewer) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _UpdateSheet(info: info),
        );
      } else {
        showModalBottomSheet<void>(
          context: context,
          builder: (_) => _UpToDateSheet(version: info.version),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => _UpdateErrorSheet(error: e.toString()),
      );
    }
  }
}

class _PrivacyHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(DesignTokens.rCard),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.lock_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Private by default',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Everything stays on this device. No cloud, no accounts.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(DesignTokens.rCard),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.6,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                      indent: 56,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null)
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _CheckboxToggleRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(inboxCheckboxEnabledProvider);
    return _Row(
      icon: Icons.check_circle_outline_rounded,
      iconColor: const Color(0xFF10B981),
      title: 'Show checkboxes in inbox',
      subtitle: enabled
          ? 'Tap a checkbox to mark an item done'
          : 'Checkboxes are hidden',
      trailing: Switch(
        value: enabled,
        onChanged: (v) =>
            ref.read(inboxCheckboxEnabledProvider.notifier).set(v),
      ),
    );
  }
}

class _AutoDeleteRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(inboxDeleteAfterHoursProvider);

    return _Row(
      icon: Icons.auto_delete_rounded,
      iconColor: const Color(0xFFF59E0B),
      title: 'Auto-delete checked items',
      subtitle: 'Delete after: ${_labelFor(minutes)}',
      onTap: () => _showPicker(context, ref, minutes),
    );
  }

  static String _labelFor(int m) {
    if (m == 0) return 'Never';
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    if (h < 24) return h == 1 ? '1 hour' : '$h hours';
    final d = h ~/ 24;
    return d == 1 ? '1 day' : '$d days';
  }

  Future<void> _showPicker(
      BuildContext context, WidgetRef ref, int current) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _AutoDeleteDialog(current: current),
    );
    if (result != null) {
      ref.read(inboxDeleteAfterHoursProvider.notifier).set(result);
    }
  }
}

class _AutoDeleteDialog extends StatefulWidget {
  const _AutoDeleteDialog({required this.current});
  final int current; // stored in minutes

  @override
  State<_AutoDeleteDialog> createState() => _AutoDeleteDialogState();
}

class _AutoDeleteDialogState extends State<_AutoDeleteDialog> {
  // Presets in minutes: 0=Never, 30min, 1h, 6h, 12h, 1d, 2d, 3d, 1w
  static const _presets = [0, 30, 60, 360, 720, 1440, 2880, 4320, 10080];

  late int _selected;
  bool _isCustom = false;

  final _numCtrl = TextEditingController();
  String _unit = 'hours'; // 'minutes', 'hours', 'days'

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    if (!_presets.contains(widget.current)) {
      _isCustom = true;
      _initCustomFromMinutes(widget.current);
    }
  }

  void _initCustomFromMinutes(int m) {
    if (m <= 0) {
      _numCtrl.text = '';
      _unit = 'hours';
    } else if (m % (60 * 24) == 0) {
      _numCtrl.text = '${m ~/ (60 * 24)}';
      _unit = 'days';
    } else if (m % 60 == 0) {
      _numCtrl.text = '${m ~/ 60}';
      _unit = 'hours';
    } else {
      _numCtrl.text = '$m';
      _unit = 'minutes';
    }
  }

  @override
  void dispose() {
    _numCtrl.dispose();
    super.dispose();
  }

  String _label(int m) {
    if (m == 0) return 'Never';
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    if (h < 24) return h == 1 ? '1 hour' : '$h hours';
    final d = h ~/ 24;
    return d == 1 ? '1 day' : '$d days';
  }

  int? _customToMinutes() {
    final n = int.tryParse(_numCtrl.text.trim());
    if (n == null || n <= 0) return null;
    switch (_unit) {
      case 'minutes':
        return n;
      case 'hours':
        return n * 60;
      case 'days':
        return n * 60 * 24;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Auto-delete after'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _presets)
                  ChoiceChip(
                    label: Text(_label(m)),
                    selected: !_isCustom && _selected == m,
                    onSelected: (_) => setState(() {
                      _selected = m;
                      _isCustom = false;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Custom…'),
                  selected: _isCustom,
                  onSelected: (_) => setState(() {
                    _isCustom = true;
                    if (_numCtrl.text.isEmpty) {
                      _numCtrl.text = '2';
                      _unit = 'hours';
                    }
                  }),
                ),
              ],
            ),
            if (_isCustom) ...[
              const SizedBox(height: 16),
              Text(
                'CUSTOM DURATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _numCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ToggleButtons(
                      isSelected: [
                        _unit == 'minutes',
                        _unit == 'hours',
                        _unit == 'days',
                      ],
                      onPressed: (i) => setState(() {
                        _unit = ['minutes', 'hours', 'days'][i];
                      }),
                      borderRadius: BorderRadius.circular(10),
                      constraints: const BoxConstraints(
                        minHeight: 38,
                        minWidth: 52,
                      ),
                      children: const [
                        Text('min',  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('hrs',  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('days', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Builder(builder: (ctx) {
                if (_numCtrl.text.trim().isEmpty) return const SizedBox.shrink();
                final m = _customToMinutes();
                if (m == null) {
                  return Text('Enter a valid number',
                      style: TextStyle(fontSize: 12, color: scheme.error));
                }
                return Text('Items will delete after ${_label(m)}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant));
              }),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            int value;
            if (_isCustom) {
              final m = _customToMinutes();
              if (m == null) return;
              value = m;
            } else {
              value = _selected;
            }
            Navigator.pop(context, value);
          },
          child: const Text('Set'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Update-check UI
// ---------------------------------------------------------------------------

/// Small centered dialog shown while the GitHub API call is in flight.
class _CheckingDialog extends StatelessWidget {
  const _CheckingDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: scheme.primary),
            const SizedBox(height: 18),
            const Text(
              'Checking for updates…',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet shown when a newer version is available.
class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.info});
  final ReleaseInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateStr = DateFormat('MMM d, y').format(info.publishedAt);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
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
            Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5)),
            // Changelog
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    'WHAT\'S NEW',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Render the markdown-ish release notes as plain text,
                  // converting ## headings and bullet points nicely.
                  _ChangelogBody(markdown: info.body),
                ],
              ),
            ),
            // CTA buttons
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _download(context),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download update'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Not now'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    // Prefer the direct APK asset; fall back to the release page.
    final url = info.apkUrl.isNotEmpty ? info.apkUrl : info.htmlUrl;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open download link')),
        );
      }
    }
  }
}

/// Renders GitHub-flavoured markdown release notes as styled Flutter widgets.
/// Handles ## headings, ### headings, - bullet points, and plain paragraphs.
class _ChangelogBody extends StatelessWidget {
  const _ChangelogBody({required this.markdown});
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (markdown.trim().isEmpty) {
      return Text(
        'No release notes provided.',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      );
    }

    final lines = markdown.split('\n');
    final widgets = <Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(
            line.substring(3),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ));
      } else if (line.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(
            line.substring(4),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        final text = line.substring(2);
        // Strip **bold** markers for plain display
        final clean = text.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  clean,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ),
            ],
          ),
        ));
      } else if (line.trim().isNotEmpty) {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            line,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: scheme.onSurface,
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

/// Bottom sheet shown when the app is already on the latest version.
class _UpToDateSheet extends StatelessWidget {
  const _UpToDateSheet({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'You\'re up to date',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Mnemo v$version is the latest version.',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Great'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet shown when the update check fails (no internet, API error, etc.)
class _UpdateErrorSheet extends StatelessWidget {
  const _UpdateErrorSheet({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off_rounded,
                  color: scheme.onErrorContainer, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not check for updates',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Make sure you\'re connected to the internet and try again.',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final uri = Uri.parse(
                          'https://github.com/${AppConstants.githubRepo}/releases/latest');
                      try {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open GitHub'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
