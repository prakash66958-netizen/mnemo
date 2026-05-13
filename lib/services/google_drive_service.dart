import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'memory_repository.dart';
import 'settings_service.dart';

/// Result returned by [GoogleDriveService.syncNow].
class SyncResult {
  const SyncResult({
    required this.uploaded,
    required this.mergedItems,
    this.error,
  });

  /// True when the local backup was successfully uploaded to Drive.
  final bool uploaded;

  /// Number of items merged from Drive into the local DB.
  final int mergedItems;

  /// Non-null when the sync failed.
  final String? error;

  bool get success => error == null;
}

/// Handles Google Sign-In and Drive backup/restore for Mnemo.
///
/// Backup file lives in the app's private `appDataFolder` on Drive —
/// invisible to the user in their Drive UI, never clutters their storage.
/// File name: `mnemo_backup.json`.
///
/// Sync strategy (merge, not overwrite):
///   1. Download the Drive backup (if it exists).
///   2. Import it into the local DB — existing items with the same content
///      are skipped by Isar's upsert; newer remote items win.
///   3. Export the now-merged local DB and upload it back to Drive.
///
/// This means data entered offline is never lost — it gets pushed up on the
/// next sync, and data from another device gets pulled down.
class GoogleDriveService {
  GoogleDriveService._();
  static final GoogleDriveService instance = GoogleDriveService._();

  static const _backupFileName = 'mnemo_backup.json';
  static const _backupMimeType = 'application/json';

  // Drive appDataFolder scope + email scope.
  static const _scopes = [
    drive.DriveApi.driveAppdataScope,
    'email',
    'profile',
  ];

  final _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// Initialises the service — restores the previously signed-in account
  /// silently (no UI). Call this from main() or app bootstrap.
  Future<void> init() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await SettingsService.instance.setGoogleEmail(_currentUser!.email);
      }
    } catch (_) {
      // Silent sign-in failure is non-fatal.
    }
  }

  /// Shows the Google account picker. Returns the signed-in account or null
  /// if the user cancelled. Throws a descriptive [Exception] on failure so
  /// callers can surface the error to the user.
  Future<GoogleSignInAccount?> signIn() async {
    _currentUser = await _googleSignIn.signIn();
    if (_currentUser != null) {
      await SettingsService.instance.setGoogleEmail(_currentUser!.email);
    }
    return _currentUser;
  }

  /// Signs out and clears the stored email.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    await SettingsService.instance.setGoogleEmail(null);
    await SettingsService.instance.setLastDriveSync(
        DateTime.fromMillisecondsSinceEpoch(0));
  }

  /// Full sync: download → merge → upload.
  /// Safe to call even when not signed in — returns an error result.
  Future<SyncResult> syncNow() async {
    if (!isSignedIn) {
      return const SyncResult(
          uploaded: false, mergedItems: 0, error: 'Not signed in');
    }
    if (_isSyncing) {
      return const SyncResult(
          uploaded: false, mergedItems: 0, error: 'Sync already in progress');
    }
    _isSyncing = true;
    try {
      final client = await _authClient();
      if (client == null) {
        return const SyncResult(
            uploaded: false, mergedItems: 0, error: 'Auth failed');
      }
      final driveApi = drive.DriveApi(client);

      // 1. Download existing backup from Drive and merge into local DB.
      int merged = 0;
      final existing = await _findBackupFile(driveApi);
      if (existing != null) {
        final json = await _downloadFile(driveApi, existing.id!);
        if (json != null) {
          merged = await MemoryRepository.instance.importFromJson(json);
        }
      }

      // 2. Export the now-merged local DB.
      final exportData = await MemoryRepository.instance.exportAll();
      final jsonBytes = utf8.encode(jsonEncode(exportData));

      // 3. Upload (create or update) the backup file.
      await _uploadFile(driveApi, existing?.id, jsonBytes);

      await SettingsService.instance.setLastDriveSync(DateTime.now());
      client.close();

      return SyncResult(uploaded: true, mergedItems: merged);
    } catch (e) {
      return SyncResult(uploaded: false, mergedItems: 0, error: e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  // ── Debounced auto-sync ────────────────────────────────────────────────────

  Timer? _debounceTimer;
  bool _isSyncing = false; // prevents re-entrant sync loops

  /// Call this after every local write (create, update, delete).
  /// Waits [delay] (default 3 s) for further writes to settle, then runs
  /// a full sync. Rapid consecutive writes are coalesced into one upload.
  /// Does nothing when the user is not signed in or a sync is already running.
  void scheduleSync({Duration delay = const Duration(seconds: 3)}) {
    if (!isSignedIn || _isSyncing) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () async {
      if (_isSyncing) return;
      _isSyncing = true;
      try {
        final result = await syncNow();
        if (result.success) {
          await SettingsService.instance.setLastDriveSync(DateTime.now());
        }
      } catch (_) {
        // Silent — auto-sync failures must never surface to the user.
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Downloads the Drive backup and imports it, without uploading.
  /// Used on first sign-in to restore data from another device.
  Future<SyncResult> restoreFromDrive() async {
    if (!isSignedIn) {
      return const SyncResult(
          uploaded: false, mergedItems: 0, error: 'Not signed in');
    }
    try {
      final client = await _authClient();
      if (client == null) {
        return const SyncResult(
            uploaded: false, mergedItems: 0, error: 'Auth failed');
      }
      final driveApi = drive.DriveApi(client);
      final existing = await _findBackupFile(driveApi);
      if (existing == null) {
        client.close();
        return const SyncResult(uploaded: false, mergedItems: 0);
      }
      final json = await _downloadFile(driveApi, existing.id!);
      client.close();
      if (json == null) {
        return const SyncResult(uploaded: false, mergedItems: 0);
      }
      final merged = await MemoryRepository.instance.importFromJson(json);
      return SyncResult(uploaded: false, mergedItems: merged);
    } catch (e) {
      return SyncResult(uploaded: false, mergedItems: 0, error: e.toString());
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Returns an authenticated HTTP client for the current user.
  Future<_AuthClient?> _authClient() async {
    try {
      final headers = await _currentUser!.authHeaders;
      return _AuthClient(headers);
    } catch (_) {
      // Token expired — try refreshing.
      try {
        await _currentUser!.clearAuthCache();
        final headers = await _currentUser!.authHeaders;
        return _AuthClient(headers);
      } catch (_) {
        return null;
      }
    }
  }

  Future<drive.File?> _findBackupFile(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_backupFileName'",
      $fields: 'files(id, name, modifiedTime)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first;
  }

  Future<dynamic> _downloadFile(drive.DriveApi api, String fileId) async {
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  Future<void> _uploadFile(
      drive.DriveApi api, String? existingId, List<int> bytes) async {
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: _backupMimeType,
    );

    if (existingId != null) {
      // Update existing file.
      await api.files.update(
        drive.File()..name = _backupFileName,
        existingId,
        uploadMedia: media,
      );
    } else {
      // Create new file in appDataFolder.
      await api.files.create(
        drive.File()
          ..name = _backupFileName
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    }
  }
}

/// Minimal HTTP client that injects Google auth headers into every request.
class _AuthClient extends http.BaseClient {
  _AuthClient(this._headers);
  final Map<String, String> _headers;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
