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
  static const String appVersion = '2.2.0';

  /// GitHub repo used for release checks.
  static const String githubRepo = 'prakash66958-netizen/mnemo';

  /// Isar database identifier used across the app.
  static const String dbName = 'mnemo_db';

  /// Notification channel ids / names for flutter_local_notifications.
  static const String notificationChannelId = 'mnemo_reminders';
  static const String notificationChannelName = 'Mnemo Reminders';
  static const String notificationChannelDesc =
      'Offline reminders created from your saved memories.';

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
}
