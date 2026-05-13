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
import '../../services/memory_repository.dart';
import '../../services/share_out_service.dart';
import '../shared/providers.dart';

/// "Me" tab — settings, theme, backup, privacy reassurance.
/// Follows the same app-bar and surface conventions as the other tabs.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(themeModeProvider);

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
                      _Row(
                        icon: Icons.upload_rounded,
                        iconColor: const Color(0xFF10B981),
                        title: 'Export backup',
                        subtitle: 'Choose where to save your backup file.',
                        onTap: () => _exportBackup(context),
                      ),
                      _Row(
                        icon: Icons.cloud_upload_rounded,
                        iconColor: const Color(0xFF0EA5E9),
                        title: 'Back up to cloud',
                        subtitle:
                            'Send the backup to Google Drive, Gmail or any cloud app.',
                        onTap: () => _exportBackup(context),
                      ),
                      _Row(
                        icon: Icons.download_rounded,
                        iconColor: const Color(0xFF3B82F6),
                        title: 'Import backup',
                        subtitle: 'Restore memories from a Mnemo JSON file.',
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
                      _Row(
                        icon: Icons.language_rounded,
                        iconColor: const Color(0xFF4F46E5),
                        title: 'Visit website',
                        subtitle: 'getmnemo.web.app',
                        onTap: () => _openWebsite(context),
                      ),
                      _Row(
                        icon: Icons.info_outline_rounded,
                        iconColor: const Color(0xFF64748B),
                        title: AppConstants.appName,
                        subtitle:
                            '${AppConstants.appTagline} · Version 2.0.0',
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
