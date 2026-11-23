import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// tAsikaso's Supabase project: accounts, plans and daily limits (see
/// `supabase/migrations/0001_accounts.sql` and `server/src/accounts.ts`).
/// The URL and publishable key are public by design: they only let the app
/// sign users in; what a user may read is set by row-level security.
const kSupabaseUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://zwresopjspwugugikrqt.supabase.co');
const kSupabaseKey = String.fromEnvironment('SUPABASE_KEY',
    defaultValue: 'sb_publishable_dTGsBPMT_7QfOZS4RBntww_6y0DGv4A');

/// What the app needs from Supabase Auth; the real one wraps
/// supabase_flutter, tests use a stand-in.
abstract class AccountsBackend {
  /// The signed-in user's id, or null before the first sign-in.
  String? get userId;

  /// Signed in without an account ("Continue without an account").
  bool get isAnonymous;

  /// The current access token, refreshed first if it has run out; null
  /// when there's no session.
  Future<String?> accessToken();

  Future<void> signInAnonymously();

  /// A fresh access token (e.g. after the server said it had expired).
  Future<void> refresh();

  /// Signs in with Google's ID token. An anonymous user's account becomes
  /// the Google one (same id, so usage and plan carry over), unless that
  /// Google account already has a tAsikaso account: then that one is used.
  Future<void> signInWithGoogle({required String idToken, String? accessToken});

  Future<void> signOut();
}

/// The user's tAsikaso account. Until [init] runs (and in tests) accounts
/// are off: the app talks to the study server with its built-in token, as
/// before accounts existed.
class Accounts {
  Accounts._(this._backend);

  static Accounts instance = Accounts._(null);

  final AccountsBackend? _backend;

  /// Supabase started. (Whether the study server is asked with the
  /// account's token is `StudyAi.usesAccounts`.)
  bool get enabled => _backend != null;

  String? get userId => _backend?.userId;
  bool get isAnonymous => _backend?.isAnonymous ?? true;

  /// Starts Supabase (the saved session comes back by itself). A failure
  /// leaves accounts off for this run; the app works as before.
  static Future<void> init() async {
    if (kSupabaseUrl.isEmpty || kSupabaseKey.isEmpty) return;
    try {
      await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseKey);
      instance = Accounts._(_SupabaseBackend());
    } catch (e) {
      debugPrint('Accounts could not start: $e');
    }
  }

  @visibleForTesting
  static void useForTesting(AccountsBackend? backend) =>
      instance = Accounts._(backend);

  /// The token to send to the study server: the signed-in user's, made
  /// anonymously the first time. Null when accounts are off or Supabase
  /// can't be reached (the caller falls back to the built-in token).
  Future<String?> token() async {
    final backend = _backend;
    if (backend == null) return null;
    try {
      if (backend.userId == null) await backend.signInAnonymously();
      return await backend.accessToken();
    } catch (e) {
      debugPrint('No account token: $e');
      return null;
    }
  }

  /// After the server said the token had expired.
  Future<void> refresh() async {
    try {
      await _backend?.refresh();
    } catch (e) {
      debugPrint('Refreshing the account token failed: $e');
    }
  }

  /// After signing in with Google on the phone: the tAsikaso account
  /// becomes that Google account. Quietly does nothing when accounts are
  /// off or this account already is a Google one; false if it failed.
  Future<bool> signInWithGoogle({required String? idToken, String? accessToken}) async {
    final backend = _backend;
    if (backend == null || idToken == null || idToken.isEmpty) return false;
    if (backend.userId != null && !backend.isAnonymous) return true;
    try {
      await backend.signInWithGoogle(idToken: idToken, accessToken: accessToken);
      return true;
    } catch (e) {
      debugPrint('Linking the Google account failed: $e');
      return false;
    }
  }

  /// Log Out or Delete Account: the next request starts a new anonymous
  /// account.
  Future<void> signOut() async {
    try {
      await _backend?.signOut();
    } catch (e) {
      debugPrint('Signing out of the account failed: $e');
    }
  }
}

class _SupabaseBackend implements AccountsBackend {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  String? get userId => _auth.currentUser?.id;

  @override
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  @override
  Future<String?> accessToken() async {
    var session = _auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      session = (await _auth.refreshSession()).session;
    }
    return session?.accessToken;
  }

  @override
  Future<void> signInAnonymously() => _auth.signInAnonymously();

  @override
  Future<void> refresh() => _auth.refreshSession();

  @override
  Future<void> signInWithGoogle({required String idToken, String? accessToken}) async {
    if (_auth.currentUser?.isAnonymous ?? false) {
      try {
        await _auth.linkIdentityWithIdToken(
            provider: OAuthProvider.google, idToken: idToken, accessToken: accessToken);
        return;
      } on AuthException catch (e) {
        // This Google account already has a tAsikaso account (e.g. from
        // another phone): sign in to that one instead.
        if (e.code != 'identity_already_exists') rethrow;
      }
    }
    await _auth.signInWithIdToken(
        provider: OAuthProvider.google, idToken: idToken, accessToken: accessToken);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
