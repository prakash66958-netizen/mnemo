import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../../models/memory_item.dart';
import '../../services/memory_repository.dart';
import '../../services/promise_detector.dart';

/// Outcome of [maybePromptForReminder].
///
/// `accepted` means the user explicitly agreed to set a reminder and the
/// helper has navigated to `/reminder/new`. `declined` covers every other
/// outcome — explicit "No thanks", scrim/back dismiss, the helper being
/// short-circuited by `reminderPromptHandled`, or no future-time hint
/// available.
enum ReminderPromptOutcome { accepted, declined }

/// Offers to set a reminder for [memory] when the offline
/// [PromiseDetector] surfaces a future-time hint in [contentForDetection].
///
/// Behavior:
///   * Returns `declined` immediately and does NOT mutate [memory] when
///     `memory.reminderPromptHandled == true` (Req 5.6).
///   * Returns `declined` immediately and does NOT mutate [memory] when
///     the detector's `suggestedTime` is null or is not strictly after
///     `DateTime.now()` (Req 5.7).
///   * Otherwise shows a non-blocking modal bottom sheet with two explicit
///     actions (accept / decline). A scrim or back-button dismiss (sheet
///     returns `null`) is treated as a decline (Req 5.3).
///   * On accept, navigates to `/reminder/new` via [appRouter] with
///     `extra: {'memoryId', 'text', 'time'}` matching the contract used
///     elsewhere (Req 5.4) and returns `accepted`.
///   * On decline (or dismiss), persists `reminderPromptHandled = true`
///     via [MemoryRepository.markReminderPromptHandled] before returning
///     `declined` (Req 5.5 / 5.6).
Future<ReminderPromptOutcome> maybePromptForReminder(
  BuildContext context, {
  required MemoryItem memory,
  required String contentForDetection,
}) async {
  // Already handled in a previous session — never re-prompt, never mutate.
  if (memory.reminderPromptHandled) {
    return ReminderPromptOutcome.declined;
  }

  final detection = PromiseDetector.instance.detect(contentForDetection);
  final suggestedTime = detection.suggestedTime;
  if (suggestedTime == null || !suggestedTime.isAfter(DateTime.now())) {
    return ReminderPromptOutcome.declined;
  }

  if (!context.mounted) {
    return ReminderPromptOutcome.declined;
  }

  final actionText = detection.action ?? memory.content;

  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReminderPromptSheet(
      action: actionText,
      time: suggestedTime,
    ),
  );

  if (accepted == true) {
    appRouter.push('/reminder/new', extra: {
      'memoryId': memory.id,
      'text': actionText,
      'time': suggestedTime,
    });
    return ReminderPromptOutcome.accepted;
  }

  // Explicit decline OR scrim/back dismiss — both persist the handled
  // flag so we don't re-prompt on a subsequent edit-save.
  await MemoryRepository.instance.markReminderPromptHandled(memory);
  return ReminderPromptOutcome.declined;
}

/// Two-button bottom sheet surface used by [maybePromptForReminder].
///
/// Pops `true` on accept, `false` on explicit decline. A scrim/back
/// dismiss leaves the result as `null`, which the caller maps to
/// [ReminderPromptOutcome.declined].
class _ReminderPromptSheet extends StatelessWidget {
  const _ReminderPromptSheet({
    required this.action,
    required this.time,
  });

  final String action;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final whenLabel = _formatWhen(time);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle.
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.alarm_rounded,
                      color: scheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Set a reminder?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            whenLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('No thanks'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.alarm_add_rounded, size: 18),
                      label: const Text('Yes, set a reminder'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatWhen(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = day.difference(today).inDays;
    final hm = DateFormat('h:mm a').format(t);
    if (diff == 0) return 'Today · $hm';
    if (diff == 1) return 'Tomorrow · $hm';
    if (diff > 1 && diff < 7) return '${DateFormat('EEEE').format(t)} · $hm';
    return '${DateFormat('MMM d, y').format(t)} · $hm';
  }
}
