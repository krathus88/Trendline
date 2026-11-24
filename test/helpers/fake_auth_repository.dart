import 'dart:async';

import 'package:trendline/data/auth/auth_repository.dart';

/// An in-memory [AuthRepository] for widget tests.
class FakeAuthRepository implements AuthRepository {
  new({AuthStatus initial = const SignedOut()}) : _current = initial;

  final _changes = StreamController<AuthStatus>.broadcast();
  final _failures = StreamController<AuthFailure>.broadcast();
  AuthStatus _current;

  int signInCalls = 0;
  int signOutCalls = 0;

  /// When set, [signInWithDiscord] throws it.
  AuthFailure? signInFailure;

  void emit(AuthStatus status) {
    _current = status;
    _changes.add(status);
  }

  void emitFailure(AuthFailure failure) => _failures.add(failure);

  @override
  Stream<AuthStatus> watchStatus() async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Stream<AuthFailure> watchFailures() => _failures.stream;

  @override
  Future<void> signInWithDiscord() async {
    signInCalls++;
    final failure = signInFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emit(const SignedOut());
  }

  Future<void> dispose() async {
    await _changes.close();
    await _failures.close();
  }
}
