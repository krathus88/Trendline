import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:trendline/data/auth/auth_repository.dart';

void main() {
  group('toAuthFailure', () {
    test('recognises the allowlist rejection from the hook', () {
      final failure = toAuthFailure(
        const sb.AuthException(
          'This Discord account is not on the invite list.',
          statusCode: '403',
        ),
      );
      expect(failure.notInvited, isTrue);
      expect(failure.message, contains("isn't on the invite list"));
    });

    test('recognises the wrong-provider rejection', () {
      final failure = toAuthFailure(
        const sb.AuthException('Sign-in is only available with Discord.'),
      );
      expect(failure.notInvited, isFalse);
      expect(failure.message, 'Sign-in is only available with Discord.');
    });

    test('hides unknown error details from the user', () {
      final failure = toAuthFailure(
        const sb.AuthException('refresh_token abc123 invalid for user x'),
      );
      expect(failure.message, 'Sign-in failed. Please try again.');
      expect(failure.message, isNot(contains('abc123')));
    });

    test('handles non-auth errors', () {
      expect(
        toAuthFailure(StateError('boom')).message,
        'Sign-in failed. Please try again.',
      );
    });

    test('passes AuthFailure through unchanged', () {
      const original = AuthFailure('custom');
      expect(toAuthFailure(original), same(original));
    });
  });
}
