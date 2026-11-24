import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/snapshots/today_snapshot.dart';

/// Where snapshots are kept. Overridden in tests.
final snapshotStoreProvider = Provider<SnapshotStore>(
  (ref) => const SecureSnapshotStore(FlutterSecureStorage()),
);

/// The Today snapshot of the signed-in user, or null. Kept alive by the
/// auth gate, so signing out (or another account signing in) deletes it.
final todaySnapshotProvider =
    AsyncNotifierProvider<TodaySnapshotNotifier, TodaySnapshot?>(
      TodaySnapshotNotifier.new,
    );

class TodaySnapshotNotifier extends AsyncNotifier<TodaySnapshot?> {
  static const String _key = 'today';

  /// What was last written, so an unchanged screen isn't written again.
  String? _written;

  @override
  Future<TodaySnapshot?> build() async {
    final store = ref.watch(snapshotStoreProvider);
    _written = null;
    final String userId;
    switch (ref.watch(authStatusProvider)) {
      case AsyncData(value: SignedIn(userId: final id)):
        userId = id;
      case AsyncData(value: SignedOut()):
        // Signed out: nothing of theirs stays on the device.
        await store.delete(_key);
        return null;
      default:
        // Still finding out who's signed in: keep it, show nothing yet.
        return null;
    }
    final stored = await store.read(_key);
    final snapshot = TodaySnapshot.decode(stored);
    if (snapshot == null || snapshot.userId != userId) {
      // Another account's, or unreadable: never shown, so deleted.
      if (stored != null) await store.delete(_key);
      return null;
    }
    _written = stored;
    return snapshot;
  }

  /// Saves [snapshot] if it's the signed-in user's and has changed.
  Future<void> save(TodaySnapshot snapshot) async {
    if (snapshot.userId != ref.read(currentUserIdProvider)) return;
    final encoded = snapshot.encode();
    // Ignore the time it was saved when comparing.
    if (_sameApartFromTime(encoded, _written)) return;
    _written = encoded;
    await ref.read(snapshotStoreProvider).write(_key, encoded);
    state = AsyncData(snapshot);
  }

  static bool _sameApartFromTime(String a, String? b) {
    if (b == null) return false;
    final pattern = RegExp('"saved":"[^"]*"');
    return a.replaceFirst(pattern, '') == b.replaceFirst(pattern, '');
  }
}
