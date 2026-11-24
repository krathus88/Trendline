import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:trendline/data/supabase/supabase_config.dart';

/// Whether someone is signed in. Deliberately carries only the user ID:
/// screens never need tokens.
sealed class AuthStatus {
  const new();
}

class SignedIn extends AuthStatus {
  const new(this.userId);

  final String userId;
}

class SignedOut extends AuthStatus {
  const new();
}

/// A sign-in problem, with a message that is safe to show the user.
class AuthFailure implements Exception {
  const new(this.message, {this.notInvited = false});

  final String message;

  /// True when the allowlist hook rejected the Discord account.
  final bool notInvited;

  @override
  String toString() => 'AuthFailure: $message';
}

abstract interface class AuthRepository {
  /// The current status, followed by every change. Never emits errors.
  Stream<AuthStatus> watchStatus();

  /// Sign-in failures that arrive after the browser returns to the app (for
  /// example the allowlist rejecting the account). Kept apart from
  /// [watchStatus] so a failed attempt doesn't leave the status in an error
  /// state: the user is simply still signed out.
  Stream<AuthFailure> watchFailures();

  /// Opens Discord in the browser. Completes once the browser has launched;
  /// the result arrives later through [watchStatus] or [watchFailures].
  Future<void> signInWithDiscord();

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  new(this._auth);

  final sb.GoTrueClient _auth;
  final _failures = StreamController<AuthFailure>.broadcast();

  @override
  Stream<AuthStatus> watchStatus() async* {
    yield _statusOf(_auth.currentSession);
    yield* _auth.onAuthStateChange
        .map((data) => _statusOf(data.session))
        .handleError((Object error) => _failures.add(toAuthFailure(error)));
  }

  @override
  Stream<AuthFailure> watchFailures() => _failures.stream;

  @override
  Future<void> signInWithDiscord() async {
    try {
      final launched = await _auth.signInWithOAuth(
        sb.OAuthProvider.discord,
        redirectTo: SupabaseConfig.authRedirectUrl,
        authScreenLaunchMode: sb.LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const AuthFailure('Could not open the browser to sign in.');
      }
    } on AuthFailure {
      rethrow;
    } on Object catch (error) {
      throw toAuthFailure(error);
    }
  }

  @override
  Future<void> signOut() async {
    // Later milestones also clear on-device caches here, so no personal data
    // is left on the device after sign-out.
    await _auth.signOut();
  }

  static AuthStatus _statusOf(sb.Session? session) =>
      session == null ? const SignedOut() : SignedIn(session.user.id);
}

/// Maps any sign-in error to a message that's safe to show. Never includes
/// tokens or personal details.
AuthFailure toAuthFailure(Object error) {
  if (error is AuthFailure) return error;
  final message = error is sb.AuthException ? error.message : '';
  if (message.contains('not on the invite list')) {
    return const AuthFailure(
      "This Discord account isn't on the invite list yet. "
      'Ask the app owner to add you.',
      notInvited: true,
    );
  }
  if (message.contains('only available with Discord')) {
    return const AuthFailure('Sign-in is only available with Discord.');
  }
  return const AuthFailure('Sign-in failed. Please try again.');
}
