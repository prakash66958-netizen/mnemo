/// App-wide constants for Mnemo.
///
/// Keep these small and semantic so the rest of the codebase can evolve without
/// magic strings / numbers scattered around.
library;

class AppConstants {
  AppConstants._();

  static const String appName = 'Mnemo';
  static const String appTagline = 'Your private second brain';

  /// Current app version — must match pubspec.yaml.
  static const String appVersion = '2.6.0';

  /// GitHub repo used for release checks.
  static const String githubRepo = 'prakash66958-netizen/mnemo';

  /// Isar database identifier used across the app.
  static const String dbName = 'mnemo_db';

  /// Notification channel ids / names for flutter_local_notifications.
  static const String notificationChannelId = 'mnemo_reminders';
  static const String notificationChannelName = 'Mnemo Reminders';
  static const String notificationChannelDesc =
      'Offline reminders created from your saved memories.';

  /// Pomodoro/Focus notification channel — separate from reminders so users
  /// can mute one without the other.
  static const String focusChannelId = 'mnemo_focus';
  static const String focusChannelName = 'Mnemo Focus Timer';
  static const String focusChannelDesc =
      'Notifications when a focus or break session ends.';

  /// Stable notification ids reserved for Pomodoro events.
  static const int focusNotificationId = 900001;

  /// Preference keys.
  static const String prefThemeMode = 'pref_theme_mode';
  static const String prefClipboardWatch = 'pref_clipboard_watch';
  static const String prefOnboardingDone = 'pref_onboarding_done';
  static const String prefLanguage = 'pref_language';

  /// Whether inbox checkboxes are shown (default true).
  static const String prefInboxCheckboxEnabled = 'pref_inbox_checkbox_enabled';

  /// How long (in hours) before a checked-off inbox item is auto-deleted.
  /// Default is 24 hours.
  static const String prefInboxDeleteAfterHours = 'pref_inbox_delete_after_hours';

  /// How long (in minutes) before a checked-off inbox item is auto-deleted.
  /// Supersedes [prefInboxDeleteAfterHours] when present.
  /// 0 = Never.
  static const String prefInboxDeleteAfterMinutes = 'pref_inbox_delete_after_minutes';

  /// ISO-8601 timestamp of the last successful update check.
  static const String prefLastUpdateCheck = 'pref_last_update_check';

  /// Google account email when signed in, null when signed out.
  static const String prefGoogleEmail = 'pref_google_email';

  /// ISO-8601 timestamp of the last successful Drive sync.
  static const String prefLastDriveSync = 'pref_last_drive_sync';

  // ── Pomodoro persistence ────────────────────────────────────────────────
  /// PomPhase enum name (work, shortBreak, longBreak).
  static const String prefPomPhase = 'pref_pom_phase';
  /// ISO-8601 timestamp of when the current phase will end. Null if paused.
  static const String prefPomEndsAt = 'pref_pom_ends_at';
  /// Seconds remaining when paused.
  static const String prefPomSecsLeft = 'pref_pom_secs_left';
  /// Current session number 1..4.
  static const String prefPomSession = 'pref_pom_session';
  /// Whether the timer is running (true) or paused (false).
  static const String prefPomRunning = 'pref_pom_running';

  /// Custom durations (in seconds) for each phase. Defaults: 25/5/15 min.
  static const String prefPomWorkSecs = 'pref_pom_work_secs';
  static const String prefPomShortSecs = 'pref_pom_short_secs';
  static const String prefPomLongSecs = 'pref_pom_long_secs';
}
