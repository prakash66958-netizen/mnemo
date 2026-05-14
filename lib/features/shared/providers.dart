import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/category.dart';
import '../../models/habit.dart';
import '../../models/memory_item.dart';
import '../../models/reminder.dart';
import '../../services/auth_service.dart';
import '../../services/category_service.dart';
import '../../services/habit_repository.dart';
import '../../services/memory_repository.dart';
import '../../services/reminder_repository.dart';
import '../../services/settings_service.dart';

/// ---------------------------------------------------------------------------
/// Repository providers (singletons; easy to override in tests).
/// ---------------------------------------------------------------------------

final memoryRepoProvider = Provider<MemoryRepository>(
  (ref) => MemoryRepository.instance,
);

final reminderRepoProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepository.instance,
);

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => SettingsService.instance,
);

final categoryServiceProvider = Provider<CategoryService>(
  (ref) => CategoryService.instance,
);

/// Streams the full list of browsable categories (built-in + custom) so any
/// widget watching it rebuilds when the user adds, renames, or removes one.
final categoryListProvider = StreamProvider<List<CategoryDef>>((ref) async* {
  final service = ref.watch(categoryServiceProvider);
  yield await service.loadAllBrowsable();
  await for (final _ in service.changes) {
    yield await service.loadAllBrowsable();
  }
});

/// ---------------------------------------------------------------------------
/// Streaming data providers.
/// ---------------------------------------------------------------------------

final inboxStreamProvider = StreamProvider<List<MemoryItem>>((ref) {
  return ref.watch(memoryRepoProvider).watchInbox();
});

final archivedStreamProvider = StreamProvider<List<MemoryItem>>((ref) {
  return ref.watch(memoryRepoProvider).watchArchived();
});

final categoryMemoriesProvider = StreamProvider.family
    .autoDispose<List<MemoryItem>, String>((ref, categoryId) {
  return ref.watch(memoryRepoProvider).watchByCategoryId(categoryId);
});

final activeRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  return ref.watch(reminderRepoProvider).watchAllActive();
});

final completedRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  return ref.watch(reminderRepoProvider).watchCompleted();
});

/// Counts of items per category id for the Categories tab grid. Keyed by
/// the stored [MemoryItem.categoryId] so both built-in and custom categories
/// are represented with a single scan.
final categoryCountsProvider = FutureProvider<Map<String, int>>(
  (ref) {
    // Re-fetch when inbox changes — cheap because category counts derive
    // from the same collection.
    ref.watch(inboxStreamProvider);
    return ref.watch(memoryRepoProvider).categoryCountsById();
  },
);

/// ---------------------------------------------------------------------------
/// UI state providers.
/// ---------------------------------------------------------------------------

/// Currently selected bottom-nav tab (0=inbox, 1=browse, 2=remind, 3=me).
/// Mockup uses a 4-tab shell — search is reached from the app-bar icon, not
/// the bottom navigation.
final shellTabProvider = StateProvider<int>((ref) => 0);

/// Inbox segment filter (All / Today / Pinned / Archive).
enum InboxFilter { all, today, pinned, archive }

final inboxFilterProvider =
    StateProvider<InboxFilter>((ref) => InboxFilter.all);

/// Theme mode, loaded from SharedPreferences.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(settingsServiceProvider));
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._settings) : super(ThemeMode.system) {
    _load();
  }

  final SettingsService _settings;

  Future<void> _load() async {
    state = await _settings.getThemeMode();
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _settings.setThemeMode(mode);
  }
}

/// Search query, filters, and async results.
class SearchState {
  const SearchState({
    this.query = '',
    this.category,
    this.results = const [],
    this.isSearching = false,
  });

  final String query;
  final CategoryDef? category;
  final List<MemoryItem> results;
  final bool isSearching;

  SearchState copyWith({
    String? query,
    CategoryDef? category,
    bool clearCategory = false,
    List<MemoryItem>? results,
    bool? isSearching,
  }) {
    return SearchState(
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._repo) : super(const SearchState());

  final MemoryRepository _repo;

  Future<void> setQuery(String q) async {
    state = state.copyWith(query: q, isSearching: true);
    if (q.trim().isEmpty) {
      state = state.copyWith(results: const [], isSearching: false);
      return;
    }
    final results = await _repo.search(q);
    // If the user kept typing while we ran the query, don't clobber their
    // newer state.
    if (state.query != q) return;
    final filtered = state.category == null
        ? results
        : results
            .where((m) => m.categoryId == state.category!.id)
            .toList(growable: false);
    state = state.copyWith(results: filtered, isSearching: false);
  }

  void setCategory(CategoryDef? c) {
    state = state.copyWith(category: c, clearCategory: c == null);
    if (state.query.isNotEmpty) {
      // Re-run with same query to re-apply filter.
      setQuery(state.query);
    }
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(memoryRepoProvider));
});


/// UI notification stream. Widgets buried inside bottom sheets / dialogs can
/// emit toasts here and the [HomeShell] will surface them on its own
/// ScaffoldMessenger — fixes the "stuck snackbar" issue where
/// messenger-key-based snackbars never auto-dismissed.
class AppToast {
  const AppToast(this.message, {this.actionLabel, this.onAction});
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
}

final appToastProvider = StreamController<AppToast>.broadcast();

/// Helper: emit a toast. Safe to call from anywhere, even after the caller
/// has popped its own context.
void showAppToast(String message, {String? actionLabel, VoidCallback? onAction}) {
  appToastProvider.add(AppToast(message, actionLabel: actionLabel, onAction: onAction));
}


/// ---------------------------------------------------------------------------
/// Habit providers.
/// ---------------------------------------------------------------------------

final habitRepoProvider = Provider<HabitRepository>(
  (ref) => HabitRepository.instance,
);

final habitListProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepoProvider).watchActive(),
);

// ---------------------------------------------------------------------------
// Cloud sync state (Firebase Auth + Firestore).
// ---------------------------------------------------------------------------

/// Streams the currently signed-in Firebase user, or `null` when signed out.
///
/// Backed by [AuthService.userStream] which wraps `FirebaseAuth.authStateChanges()`.
/// Widgets that need to react to sign-in / sign-out should watch this provider
/// rather than polling [SettingsService].
final currentUserProvider = StreamProvider<User?>(
  (ref) => AuthService.instance.userStream,
);

/// Whether the device participates in Firestore cloud sync.
///
/// Derived from [currentUserProvider]: true iff a Firebase user is signed in.
/// Treats the loading / error states as `false` so consumers see the safe
/// "sync disabled" default until the first auth event arrives. The
/// `SettingsService.syncEnabled` preference is still written by [AuthService]
/// for non-reactive consumers (repository hooks); this provider is the
/// canonical reactive source for the UI.
final syncEnabledProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider).valueOrNull != null;
});

/// Holds the signed-in Google email, or null when signed out.
///
/// Reads from SharedPreferences on first access so the UI reflects the
/// persisted state immediately without waiting for a silent sign-in.
/// [AuthService.signIn] persists the email here on success, so this provider
/// stays in sync with [currentUserProvider] without depending on it directly.
final googleEmailProvider =
    StateNotifierProvider<GoogleEmailNotifier, String?>((ref) {
  return GoogleEmailNotifier(ref.watch(settingsServiceProvider));
});

class GoogleEmailNotifier extends StateNotifier<String?> {
  GoogleEmailNotifier(this._settings) : super(null) {
    _load();
  }
  final SettingsService _settings;

  Future<void> _load() async {
    state = await _settings.getGoogleEmail();
  }

  void set(String? email) {
    state = email;
    _settings.setGoogleEmail(email);
  }
}

/// Last successful Firestore sync ack timestamp.
///
/// Reads from [SettingsService.getLastCloudSync] on first access and is
/// updated by the settings UI / sync engine via the notifier's [set] method.
final lastCloudSyncProvider =
    StateNotifierProvider<LastCloudSyncNotifier, DateTime?>((ref) {
  return LastCloudSyncNotifier(ref.watch(settingsServiceProvider));
});

class LastCloudSyncNotifier extends StateNotifier<DateTime?> {
  LastCloudSyncNotifier(this._settings) : super(null) {
    _load();
  }
  final SettingsService _settings;

  Future<void> _load() async {
    final t = await _settings.getLastCloudSync();
    // Treat epoch (sign-out sentinel) as null.
    if (t != null && t.millisecondsSinceEpoch > 0) state = t;
  }

  void set(DateTime? t) {
    state = (t != null && t.millisecondsSinceEpoch > 0) ? t : null;
    _settings.setLastCloudSync(t);
  }
}


/// ---------------------------------------------------------------------------
/// Advanced inbox filter (date range + category).
/// ---------------------------------------------------------------------------

class AdvancedFilter {
  const AdvancedFilter({this.categoryId, this.dateRange});
  final String? categoryId;
  final DateTimeRange? dateRange;

  bool get isActive => categoryId != null || dateRange != null;
}

final inboxAdvancedFilterProvider =
    StateProvider<AdvancedFilter>((ref) => const AdvancedFilter());

/// Whether inbox checkboxes are visible.
final inboxCheckboxEnabledProvider =
    StateNotifierProvider<InboxCheckboxNotifier, bool>((ref) {
  return InboxCheckboxNotifier(ref.watch(settingsServiceProvider));
});

class InboxCheckboxNotifier extends StateNotifier<bool> {
  InboxCheckboxNotifier(this._settings) : super(true) {
    _load();
  }
  final SettingsService _settings;

  Future<void> _load() async {
    state = await _settings.getInboxCheckboxEnabled();
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    await _settings.setInboxCheckboxEnabled(enabled);
  }
}

/// Live app version read from the installed package (matches pubspec.yaml).
/// Returns e.g. "2.0.0" — updates automatically whenever pubspec version changes.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Auto-delete duration for checked-off inbox items (in hours).
final inboxDeleteAfterHoursProvider =
    StateNotifierProvider<InboxDeleteNotifier, int>((ref) {
  return InboxDeleteNotifier(ref.watch(settingsServiceProvider));
});

class InboxDeleteNotifier extends StateNotifier<int> {
  InboxDeleteNotifier(this._settings) : super(1440) {
    _load();
  }
  final SettingsService _settings;

  Future<void> _load() async {
    state = await _settings.getInboxDeleteAfterHours(); // returns minutes
  }

  Future<void> set(int minutes) async {
    state = minutes;
    await _settings.setInboxDeleteAfterHours(minutes); // stores minutes
  }
}
