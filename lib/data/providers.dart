import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/auth/auth_repository.dart';

/// Overridden in `main.dart` with the Supabase implementation, and in tests
/// with a fake.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('authRepositoryProvider not overridden'),
);

final authStatusProvider = StreamProvider<AuthStatus>(
  (ref) => ref.watch(authRepositoryProvider).watchStatus(),
);

final authFailuresProvider = StreamProvider<AuthFailure>(
  (ref) => ref.watch(authRepositoryProvider).watchFailures(),
);
