import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants/app_constants.dart';

/// Drawable resource name (without the `@drawable/` prefix) used for the
/// status-bar / lockscreen small icon. Android requires this to be a
/// monochrome, alpha-only drawable — see
/// `android/app/src/main/res/drawable/ic_notification.xml`.
const String _kSmallIcon = 'ic_notification';

/// Brand accent color used to tint the mono small icon on the lockscreen and
/// in the notification shade. Matches the indigo used across the Mnemo UI.
const Color _kAccentColor = Color(0xFF4F46E5);

/// Encapsulates local (offline) reminder notifications.
///
/// All scheduling happens on-device. We never call a cloud push service.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      // If we can't detect the local zone, fall back to UTC so schedules still
      // work — they'll just be based on UTC offsets.
    }

    const androidInit = AndroidInitializationSettings('@drawable/$_kSmallIcon');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(initSettings);

    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // On Android 8+ (API 26+), notifications posted to a channel that hasn't
    // been registered are silently dropped. Create it up-front so the first
    // reminder actually surfaces. We also opt in to heads-up (Importance.max),
    // sound, and a branded LED so the lockscreen presentation matches the
    // status-bar icon's tint.
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notificationChannelId,
        AppConstants.notificationChannelName,
        description: AppConstants.notificationChannelDesc,
        importance: Importance.max,
        enableLights: true,
        ledColor: _kAccentColor,
        playSound: true,
      ),
    );

    // Pomodoro / Focus notifications get their own channel so the user can
    // adjust priority/sound independently of regular reminders.
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.focusChannelId,
        AppConstants.focusChannelName,
        description: AppConstants.focusChannelDesc,
        importance: Importance.max,
        enableLights: true,
        enableVibration: true,
        ledColor: _kAccentColor,
        playSound: true,
      ),
    );

    // Request POST_NOTIFICATIONS on Android 13+ (no-op below).
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Returns true if the OS currently allows us to post notifications.
  ///
  /// On Android < 13 and on platforms that don't expose the query this
  /// defaults to `true` (historically notifications were always on).
  Future<bool> hasNotificationPermission() async {
    if (!_initialized) await init();
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await androidImpl?.areNotificationsEnabled() ?? true;
  }

  /// Shared `AndroidNotificationDetails` for all Mnemo notifications. Kept as
  /// a getter (rather than `const`) so the branded accent color / icon flow
  /// through every `schedule` / `showNow` call without duplication.
  AndroidNotificationDetails _androidDetails() {
    return const AndroidNotificationDetails(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      channelDescription: AppConstants.notificationChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: _kSmallIcon,
      color: _kAccentColor,
      colorized: false,
    );
  }

  /// Schedules a one-shot reminder. Returns the notification id used so the
  /// caller can persist it.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_initialized) await init();
    final scheduled = tz.TZDateTime.from(when, tz.local);

    final details = NotificationDetails(android: _androidDetails());

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'reminder:$id',
      );
    } catch (e) {
      // If exact alarms are not permitted, fall back to inexact so the user at
      // least gets a nudge close to the requested time.
      debugPrint(
        '[NotificationService] exact alarm scheduling failed ($e); '
        'falling back to inexactAllowWhileIdle for id=$id',
      );
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'reminder:$id',
      );
    }
  }

  /// Shows a notification immediately. Used for reminders whose due time is
  /// already in the past on app launch (the "missed while offline" case).
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    final details = NotificationDetails(android: _androidDetails());
    await _plugin.show(id, title, body, details, payload: 'reminder:$id');
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// Schedules a daily repeating local notification at the given time-of-day.
  /// Uses `matchDateTimeComponents: DateTimeComponents.time` so the OS
  /// re-fires it every day at the same hour/minute.
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    if (!_initialized) await init();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final details = NotificationDetails(android: _androidDetails());

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'habit:$id',
      );
    } catch (e) {
      debugPrint(
        '[NotificationService] daily exact alarm failed ($e); '
        'falling back to inexact for id=$id',
      );
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'habit:$id',
      );
    }
  }

  /// Schedules multiple notifications throughout the day at a fixed interval.
  /// Used for habits like "drink water every 2 hours". Notifications are
  /// scheduled from [startHour] to [endHour] at [intervalMinutes] apart.
  /// Each gets a unique id derived from [baseId] + slot index.
  Future<void> scheduleInterval({
    required int baseId,
    required String title,
    required String body,
    required int startHour,
    required int endHour,
    required int intervalMinutes,
  }) async {
    if (!_initialized) await init();
    // Cancel any previously scheduled slots for this base id (up to 24 slots).
    for (var i = 0; i < 24; i++) {
      await _plugin.cancel(baseId + i);
    }

    final details = NotificationDetails(android: _androidDetails());
    var slot = 0;
    var hour = startHour;
    var minute = 0;

    while (hour < endHour || (hour == endHour && minute == 0)) {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      try {
        await _plugin.zonedSchedule(
          baseId + slot,
          title,
          body,
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'habit_interval:$baseId:$slot',
        );
      } catch (_) {
        await _plugin.zonedSchedule(
          baseId + slot,
          title,
          body,
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'habit_interval:$baseId:$slot',
        );
      }

      slot++;
      minute += intervalMinutes;
      while (minute >= 60) {
        minute -= 60;
        hour++;
      }
    }
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ── Pomodoro / Focus notifications ─────────────────────────────────────────

  /// Shared Android details for Focus end notifications. Uses the dedicated
  /// focus channel and the alarm category so the OS treats it like an alarm
  /// (full-volume, bypass DND when the user grants the permission).
  AndroidNotificationDetails _focusDetails() {
    return const AndroidNotificationDetails(
      AppConstants.focusChannelId,
      AppConstants.focusChannelName,
      channelDescription: AppConstants.focusChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      icon: _kSmallIcon,
      color: _kAccentColor,
      fullScreenIntent: false,
      enableVibration: true,
      vibrationPattern: null,
      playSound: true,
    );
  }

  /// Schedules a Focus end notification at [when]. Uses an exact alarm so the
  /// notification fires even if the app is killed.
  Future<void> scheduleFocusEnd({
    required DateTime when,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    final scheduled = tz.TZDateTime.from(when, tz.local);
    final details = NotificationDetails(android: _focusDetails());
    try {
      await _plugin.zonedSchedule(
        AppConstants.focusNotificationId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'focus',
      );
    } catch (e) {
      debugPrint('[NotificationService] focus exact alarm failed ($e); '
          'falling back to inexact');
      await _plugin.zonedSchedule(
        AppConstants.focusNotificationId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'focus',
      );
    }
  }

  /// Cancels any scheduled focus end notification.
  Future<void> cancelFocusEnd() async {
    await _plugin.cancel(AppConstants.focusNotificationId);
  }
}
