import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/supabase/secure_session_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('SecureSessionStorage', () {
    const storage = SecureSessionStorage(FlutterSecureStorage());

    test('starts empty', () async {
      await storage.initialize();
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    });

    test('round-trips a session and removes it', () async {
      await storage.persistSession('{"access_token":"t"}');
      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), '{"access_token":"t"}');

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
    });
  });

  group('SecurePkceStorage', () {
    const pkce = SecurePkceStorage(FlutterSecureStorage());

    test('round-trips and removes items', () async {
      await pkce.setItem(key: 'verifier', value: 'v1');
      expect(await pkce.getItem(key: 'verifier'), 'v1');

      await pkce.removeItem(key: 'verifier');
      expect(await pkce.getItem(key: 'verifier'), isNull);
    });

    test('does not collide with the session key', () async {
      const session = SecureSessionStorage(FlutterSecureStorage());
      await session.persistSession('session');
      await pkce.setItem(key: 'trendline.auth.session', value: 'pkce');

      expect(await session.accessToken(), 'session');
    });
  });
}
