import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/design_tokens.dart';
import '../../models/reminder.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_repository.dart';

/// Create or edit a reminder. Aligned with the detail screen's visual style.
class ReminderEditScreen extends StatefulWidget {
  const ReminderEditScreen({
    super.key,
    this.reminderId,
    this.memoryId,
    this.initialText,
    this.initialTime,
  });

  final int? reminderId;
  final int? memoryId;
  final String? initialText;
  final DateTime? initialTime;

  @override
  State<ReminderEditScreen> createState() => _ReminderEditScreenState();
}

class _ReminderEditScreenState extends State<ReminderEditScreen> {
  final _textCtrl = TextEditingController();
  DateTime _when = DateTime.now().add(const Duration(hours: 1));
  Reminder? _existing;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.reminderId != null) {
      final r = await DatabaseService.instance.isar.reminders
          .get(widget.reminderId!);
      if (r != null) {
        _existing = r;
        _textCtrl.text = r.text;
        _when = r.remindAt;
      }
    } else {
      _textCtrl.text = widget.initialText ?? '';
      if (widget.initialTime != null &&
          widget.initialTime!.isAfter(DateTime.now())) {
        _when = widget.initialTime!;
      }
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(DateTime.now()) ? DateTime.now() : _when,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (time == null) return;
    setState(() {
      _when =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (_existing != null) {
        _existing!
          ..text = text
          ..remindAt = _when;
        await ReminderRepository.instance.update(_existing!);
      } else {
        await ReminderRepository.instance.create(
          text: text,
          remindAt: _when,
          memoryId: widget.memoryId,
        );
      }
      // If the OS is blocking notifications, the reminder was still persisted
      // and scheduled — it just won't actually fire. Nudge the user once so
      // they know to flip the permission in system settings.
      final notificationsOk =
          await NotificationService.instance.hasNotificationPermission();
      if (!mounted) return;
      if (!notificationsOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are disabled. Enable them in system settings '
              'for Mnemo so reminders can alert you.',
            ),
          ),
        );
      }
      if (!mounted) return;
      context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            Text(_existing == null ? 'New reminder' : 'Edit reminder'),
        actions: [
          if (_existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ReminderRepository.instance.delete(_existing!);
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(DesignTokens.rInput),
            ),
            child: TextField(
              controller: _textCtrl,
              autofocus: _existing == null,
              maxLines: null,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'What should I remind you about?',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                fillColor: Colors.transparent,
                filled: false,
              ),
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(DesignTokens.rInput),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(DesignTokens.rInput),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.alarm_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Remind at',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          DateFormat('EEE, MMM d · h:mm a').format(_when),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_existing == null ? 'Create reminder' : 'Save'),
          ),
        ],
      ),
    );
  }
}
