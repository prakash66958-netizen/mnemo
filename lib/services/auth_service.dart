import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firestore_sync_service.dart';
import 'settings_service.dart';

/// Thin wrapper around [GoogleSignIn] and [FirebaseAuth].
///
/// Owns the Google sign-in flow and the credential exchange that produces a
/// [FirebaseAuth] user. Persists the resulting `syncEnabled`, `ownerUid`, and
/// `googleEmail` values via [SettingsService] so the rest of the app can react
/// to auth state without depending on Firebase directly.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final GoogleSignIn _googleSignIn =
      GoogleSignIn(scopes: const ['email', 'profile']);
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  /// Stream of auth state changes. Emits the current [User] (or `null` when
  /// signed out) on every transition.
  Stream<User?> get userStream => _firebaseAuth.authStateChanges();

  /// Synchronous accessor for the current Firebase user, or `null` when
  /// signed out. Used by repository sync hooks that need a non-async check.
  User? get currentUser => _firebaseAuth.currentUser;

  /// Best-effort silent restore of a previously cached Google account.
  ///
  /// Safe to call on every cold start. Any failure (no cached account,
  /// transient network error) is swallowed because silent sign-in is purely
  /// an optimization — the user can still tap "Enable cloud backup" to sign
  /// in interactively.
  Future<void> init() async {
    try {
      await _googleSignIn.signInSilently();
    } catch (_) {
      // Best-effort: silent sign-in failures must not block app boot.
    }
  }

  /// Interactive Google sign-in followed by a Firebase credential exchange.
  ///
  /// Returns:
  /// - `null` when the user cancels the Google chooser (Requirement 3.5).
  /// - The signed-in [User] on success.
  ///
  /// Throws [FirebaseAuthException] (or any underlying exception) on real
  /// failures so the caller can surface the message in the settings UI
  /// (Requirement 3.6).
  Future<User?> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      // User dismissed the chooser — leave sync state untouched.
      return null;
    }
    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
    final result = await _firebaseAuth.signInWithCredential(credential);
    final user = result.user;
    if (user != null) {
      await SettingsService.instance.setSyncEnabled(true);
      await SettingsService.instance.setOwnerUid(user.uid);
      await SettingsService.instance.setGoogleEmail(user.email);
    }
    return user;
  }

  /// Signs out of Firebase and Google and clears the cached identity.
  ///
  /// The local Isar database is left untouched (Requirement 3.8); only the
  /// auth-related preferences are cleared.
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await _googleSignIn.signOut();
    await SettingsService.instance.setSyncEnabled(false);
    await SettingsService.instance.setOwnerUid(null);
    await SettingsService.instance.setGoogleEmail(null);
    await FirestoreSyncService.instance.stop();
  }
}
