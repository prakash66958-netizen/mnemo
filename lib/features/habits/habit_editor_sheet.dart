import 'package:flutter/material.dart';

import '../../models/habit.dart';
import '../../services/habit_repository.dart';
import '../shared/providers.dart';

/// Bottom sheet for creating or editing a habit.
class HabitEditorSheet extends StatefulWidget {
  const HabitEditorSheet({super.key, this.existing});
  final Habit? existing;

  @override
  State<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<HabitEditorSheet> {
  final _nameCtrl = TextEditingController();
  String? _emoji;
  Color _color = const Color(0xFF14B8A6);
  bool _remind = false;
  bool _useInterval = false;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  int _intervalMinutes = 120; // default: every 2 hours
  int _endHour = 22;
  bool _saving = false;

  static const _palette = <Color>[
    Color(0xFF14B8A6),
    Color(0xFF22C55E),
    Color(0xFFF97316),
    Color(0xFFA855F7),
    Color(0xFFE11D48),
    Color(0xFF0EA5E9),
    Color(0xFFFACC15),
    Color(0xFFEC4899),
  ];

  static const _emojis = ['💧', '🏃', '📚', '🧘', '✍️', '💤', '🍎', '🎯'];

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    if (h != null) {
      _nameCtrl.text = h.name;
      _emoji = h.emoji;
      _color = Color(h.colorValue);
      _remind = h.remindHour != null;
      _useInterval = h.intervalMinutes > 0;
      _intervalMinutes = h.intervalMinutes > 0 ? h.intervalMinutes : 120;
      _endHour = h.intervalEndHour;
      if (h.remindHour != null) {
        _time = TimeOfDay(hour: h.remindHour!, minute: h.remindMinute ?? 0);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      if (widget.existing != null) {
        final h = widget.existing!
          ..name = name
          ..emoji = _emoji
          ..colorValue = _color.toARGB32()
          ..remindHour = _remind ? _time.hour : null
          ..remindMinute = _remind ? _time.minute : null
          ..intervalMinutes = (_remind && _useInterval) ? _intervalMinutes : 0
          ..intervalEndHour = _endHour;
        await HabitRepository.instance.update(h);
      } else {
        final h = await HabitRepository.instance.create(
          name: name,
          emoji: _emoji,
          color: _color,
          remindAt: _remind ? _time : null,
        );
        // If interval mode, update the habit with interval fields and
        // reschedule.
        if (_remind && _useInterval) {
          h.intervalMinutes = _intervalMinutes;
          h.intervalEndHour = _endHour;
          await HabitRepository.instance.update(h);
        }
      }
      if (mounted) {
        showAppToast(
          widget.existing == null ? 'Habit created' : 'Habit updated',
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.existing == null ? 'New habit' : 'Edit habit',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            // Emoji picker
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _emojis.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final e = _emojis[i];
                  final active = _emoji == e;
                  return GestureDetector(
                    onTap: () => setState(() => _emoji = active ? null : e),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? _color.withValues(alpha: 0.2)
                            : scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? _color : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Name
            TextField(
              controller: _nameCtrl,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Habit name'),
            ),
            const SizedBox(height: 12),
            // Color picker
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  for (final c in _palette)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Reminder toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Daily reminder'),
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
            ),
            if (_remind) ...[
              // Interval toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeat throughout the day'),
                subtitle: Text(
                  _useInterval
                      ? 'Every ${_intervalMinutes ~/ 60}h${_intervalMinutes % 60 > 0 ? ' ${_intervalMinutes % 60}m' : ''} from ${_time.hour}:00 to $_endHour:00'
                      : 'e.g. drink water every 2 hours',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _useInterval,
                onChanged: (v) => setState(() => _useInterval = v),
              ),
              if (_useInterval) ...[
                // Interval picker
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('Every ${_intervalMinutes ~/ 60}h${_intervalMinutes % 60 > 0 ? ' ${_intervalMinutes % 60}m' : ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: _intervalMinutes > 15
                            ? () => setState(() => _intervalMinutes -= 15)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: _intervalMinutes < 480
                            ? () => setState(() => _intervalMinutes += 15)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_rounded),
                        tooltip: 'Custom interval',
                        onPressed: _pickCustomInterval,
                      ),
                    ],
                  ),
                ),
                // Quick presets
                Wrap(
                  spacing: 8,
                  children: [
                    _IntervalPreset(label: '30m', minutes: 30, current: _intervalMinutes, onTap: () => setState(() => _intervalMinutes = 30)),
                    _IntervalPreset(label: '1h', minutes: 60, current: _intervalMinutes, onTap: () => setState(() => _intervalMinutes = 60)),
                    _IntervalPreset(label: '2h', minutes: 120, current: _intervalMinutes, onTap: () => setState(() => _intervalMinutes = 120)),
                    _IntervalPreset(label: '3h', minutes: 180, current: _intervalMinutes, onTap: () => setState(() => _intervalMinutes = 180)),
                    _IntervalPreset(label: '4h', minutes: 240, current: _intervalMinutes, onTap: () => setState(() => _intervalMinutes = 240)),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time_rounded),
                  title: Text('Start ${_time.hour}:00 · End $_endHour:00'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickStartEndTime,
                ),
              ] else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time_rounded),
                  title: Text(
                    '${_time.hourOfPeriod == 0 ? 12 : _time.hourOfPeriod}:'
                    '${_time.minute.toString().padLeft(2, '0')} '
                    '${_time.period == DayPeriod.am ? 'AM' : 'PM'}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final t = await showTimePicker(initialEntryMode: TimePickerEntryMode.input,
                      context: context,
                      initialTime: _time,
                    );
                    if (t != null) setState(() => _time = t);
                  },
                ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.existing == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomInterval() async {
    final controller = TextEditingController(text: '$_intervalMinutes');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom interval'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Minutes (e.g. 45, 90, 150)',
            suffixText: 'min',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, v);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null && result >= 10 && result <= 720) {
      setState(() => _intervalMinutes = result);
    }
  }

  Future<void> _pickStartEndTime() async {
    final start = await showTimePicker(initialEntryMode: TimePickerEntryMode.input,
      context: context,
      initialTime: _time,
      helpText: 'Start time',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(initialEntryMode: TimePickerEntryMode.input,
      context: context,
      initialTime: TimeOfDay(hour: _endHour, minute: 0),
      helpText: 'End time',
    );
    if (end == null) return;
    setState(() {
      _time = start;
      _endHour = end.hour;
    });
  }
}

class _IntervalPreset extends StatelessWidget {
  const _IntervalPreset({
    required this.label,
    required this.minutes,
    required this.current,
    required this.onTap,
  });
  final String label;
  final int minutes;
  final int current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = current == minutes;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      selected: active,
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: scheme.primaryContainer,
    );
  }
}
