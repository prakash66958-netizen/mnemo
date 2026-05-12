/// App-wide constants for Mnemo.
///
/// Keep these small and semantic so the rest of the codebase can evolve without
/// magic strings / numbers scattered around.
library;

class AppConstants {
  AppConstants._();

  static const String appName = 'Mnemo';
  static const String appTagline = 'Your private second brain';

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
}
