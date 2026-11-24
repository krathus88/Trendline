import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session in the platform's encrypted storage (Android
/// Keystore, Windows Credential Manager) instead of the default plain
/// shared preferences, which anything with file access could read.
class SecureSessionStorage extends LocalStorage {
  const new(this._storage);

  static const String _sessionKey = 'trendline.auth.session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _sessionKey);

  /// Despite the name, Supabase stores and expects the whole serialised
  /// session here, not just the access token.
  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);
}

/// Keeps the short-lived PKCE code verifier used during Discord sign-in in
/// encrypted storage too, rather than the default shared preferences.
class SecurePkceStorage extends GotrueAsyncStorage {
  const new(this._storage);

  static const String _prefix = 'trendline.auth.pkce.';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: '$_prefix$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: '$_prefix$key');
}
