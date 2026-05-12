/// Result of running the promise detector over a piece of text.
///
/// If [hasPromise] is true, [suggestedTime] may be non-null when we could
/// extract a concrete future time (e.g. "tomorrow 5pm"). Otherwise only the
/// action snippet is provided so the UI can still offer a reminder creation
/// prompt with a user-picked time.
class PromiseDetection {
  PromiseDetection({
    required this.hasPromise,
    this.action,
    this.suggestedTime,
  });

  final bool hasPromise;
  final String? action;
  final DateTime? suggestedTime;

  static PromiseDetection none() => PromiseDetection(hasPromise: false);
}

/// Detects future intent ("promises") in English + Hinglish text and, where
/// possible, extracts a concrete future time to pre-fill a reminder.
///
/// The implementation is intentionally simple and offline — no NLP models,
/// just regexes and keyword lists tuned for everyday chat patterns.
class PromiseDetector {
  PromiseDetector._();
  static final PromiseDetector instance = PromiseDetector._();

  // Patterns that strongly suggest the speaker is making a future commitment.
  static final List<RegExp> _promisePatterns = [
    RegExp(r"\bi'?ll\b", caseSensitive: false),
    RegExp(r'\bi will\b', caseSensitive: false),
    RegExp(r'\bi shall\b', caseSensitive: false),
    RegExp(r'\bi promise\b', caseSensitive: false),
    RegExp(r"\bi'?m gonna\b", caseSensitive: false),
    RegExp(r'\bgoing to (send|share|call|pay|do|finish|complete)\b',
        caseSensitive: false),
    RegExp(r'\bremind me\b', caseSensitive: false),
    RegExp(r"\b(don'?t|do not) forget\b", caseSensitive: false),
    // Hinglish: "bhej dunga", "kar dunga", etc.
    RegExp(
      r'\b(bhej|kar|de|bata|call|pay|submit|complete|finish)\s*(dunga|dungi|denge|dungaa|dungaa?)\b',
      caseSensitive: false,
    ),
    RegExp(r'\byaad dila(na|do|dena)\b', caseSensitive: false),
    RegExp(r'\bkal (tak|subah|shaam)\b', caseSensitive: false),
  ];

  PromiseDetection detect(String text) {
    if (text.trim().isEmpty) return PromiseDetection.none();

    final hasPromise = _promisePatterns.any((re) => re.hasMatch(text));
    if (!hasPromise) return PromiseDetection.none();

    final time = _extractTime(text);
    final action = _extractAction(text);

    return PromiseDetection(
      hasPromise: true,
      action: action,
      suggestedTime: time,
    );
  }

  /// Pulls a short human-readable action phrase from the text.
  String? _extractAction(String text) {
    // Grab the sentence containing the promise keyword, clipped to 80 chars.
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    for (final s in sentences) {
      if (_promisePatterns.any((re) => re.hasMatch(s))) {
        final trimmed = s.trim();
        if (trimmed.length <= 80) return trimmed;
        return '${trimmed.substring(0, 77)}...';
      }
    }
    return text.length <= 80 ? text.trim() : '${text.substring(0, 77)}...';
  }

  /// Attempts to extract a concrete future time.
  /// Handles: "tomorrow [at] 5pm", "today evening", "in 30 minutes",
  ///          "next monday", "kal", "aaj sham", "parso".
  DateTime? _extractTime(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();

    // "in N minutes|hours|days"
    final inMatch = RegExp(
      r'in\s+(\d+)\s*(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)\b',
    ).firstMatch(lower);
    if (inMatch != null) {
      final n = int.tryParse(inMatch.group(1)!) ?? 0;
      final unit = inMatch.group(2)!;
      if (unit.startsWith('min')) return now.add(Duration(minutes: n));
      if (unit.startsWith('hour') || unit.startsWith('hr')) {
        return now.add(Duration(hours: n));
      }
      if (unit.startsWith('day')) return now.add(Duration(days: n));
    }

    // Explicit clock times: "at 5pm", "at 17:30"
    final clockMatch = RegExp(
      r'(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
    ).firstMatch(lower);

    int? hour;
    int minute = 0;
    if (clockMatch != null &&
        (lower.contains('am') ||
            lower.contains('pm') ||
            lower.contains(':'))) {
      hour = int.tryParse(clockMatch.group(1)!);
      minute = int.tryParse(clockMatch.group(2) ?? '0') ?? 0;
      final ampm = clockMatch.group(3);
      if (hour != null) {
        if (ampm == 'pm' && hour < 12) hour = hour + 12;
        if (ampm == 'am' && hour == 12) hour = 0;
      }
    }

    DateTime? day;
    if (lower.contains('tomorrow') || RegExp(r'\bkal\b').hasMatch(lower)) {
      day = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    } else if (lower.contains('day after tomorrow') ||
        RegExp(r'\bparso\b').hasMatch(lower)) {
      day = DateTime(now.year, now.month, now.day).add(const Duration(days: 2));
    } else if (lower.contains('tonight') ||
        lower.contains('this evening') ||
        RegExp(r'\b(aaj sham|aaj shaam|aaj raat)\b').hasMatch(lower)) {
      day = DateTime(now.year, now.month, now.day);
      hour ??= 20; // 8pm default
    } else if (lower.contains('this afternoon')) {
      day = DateTime(now.year, now.month, now.day);
      hour ??= 15;
    } else if (lower.contains('morning') ||
        RegExp(r'\b(subah|subh)\b').hasMatch(lower)) {
      day = DateTime(now.year, now.month, now.day);
      hour ??= 9;
    }

    // "next monday" etc.
    const days = [
      'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
    ];
    for (var i = 0; i < days.length; i++) {
      if (lower.contains('next ${days[i]}')) {
        final target = i + 1; // DateTime.weekday is 1-7
        var delta = (target - now.weekday + 7) % 7;
        if (delta == 0) delta = 7;
        day = DateTime(now.year, now.month, now.day)
            .add(Duration(days: delta));
        break;
      }
    }

    if (day == null && hour == null) return null;

    day ??= DateTime(now.year, now.month, now.day);
    hour ??= 9; // default morning

    var candidate = DateTime(day.year, day.month, day.day, hour, minute);
    // Never suggest a time in the past — bump to the next day if we parsed
    // a clock-only time that's already passed today.
    if (candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}
