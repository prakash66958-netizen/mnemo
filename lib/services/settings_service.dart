import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';

/// Lightweight wrapper around SharedPreferences for small app settings.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;
  Future<SharedPreferences> _ensure() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<ThemeMode> getThemeMode() async {
    final prefs = await _ensure();
    final raw = prefs.getString(AppConstants.prefThemeMode);
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await _ensure();
    await prefs.setString(AppConstants.prefThemeMode, mode.name);
  }

  Future<bool> getClipboardWatch() async {
    final prefs = await _ensure();
    return prefs.getBool(AppConstants.prefClipboardWatch) ?? false;
  }

  Future<void> setClipboardWatch(bool enabled) async {
    final prefs = await _ensure();
    await prefs.setBool(AppConstants.prefClipboardWatch, enabled);
  }

  Future<bool> getOnboardingDone() async {
    final prefs = await _ensure();
    return prefs.getBool(AppConstants.prefOnboardingDone) ?? false;
  }

  Future<void> setOnboardingDone(bool done) async {
    final prefs = await _ensure();
    await prefs.setBool(AppConstants.prefOnboardingDone, done);
  }

  Future<String> getLanguage() async {
    final prefs = await _ensure();
    return prefs.getString(AppConstants.prefLanguage) ?? 'en';
  }

  Future<void> setLanguage(String code) async {
    final prefs = await _ensure();
    await prefs.setString(AppConstants.prefLanguage, code);
  }

  Future<bool> getInboxCheckboxEnabled() async {
    final prefs = await _ensure();
    return prefs.getBool(AppConstants.prefInboxCheckboxEnabled) ?? true;
  }

  Future<void> setInboxCheckboxEnabled(bool enabled) async {
    final prefs = await _ensure();
    await prefs.setBool(AppConstants.prefInboxCheckboxEnabled, enabled);
  }

  Future<int> getInboxDeleteAfterHours() async {
    final prefs = await _ensure();
    // New key stores minutes; fall back to old hours key × 60.
    final minutes = prefs.getInt(AppConstants.prefInboxDeleteAfterMinutes);
    if (minutes != null) return minutes; // caller treats this as minutes now
    final hours = prefs.getInt(AppConstants.prefInboxDeleteAfterHours) ?? 24;
    return hours * 60; // convert legacy hours → minutes
  }

  Future<void> setInboxDeleteAfterHours(int minutes) async {
    final prefs = await _ensure();
    await prefs.setInt(AppConstants.prefInboxDeleteAfterMinutes, minutes);
  }
}
