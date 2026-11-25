import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';

/// Where on-device snapshots are kept. Only the screens the caching plan
/// lists are snapshotted, and everything is deleted on sign-out.
abstract interface class SnapshotStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Snapshots in the platform's encrypted storage (Android Keystore, DPAPI
/// on Windows), like the auth session: they hold health data (what was
/// eaten, weigh-ins, targets), so they're never written to plain files.
class SecureSnapshotStore implements SnapshotStore {
  const new(this._storage);

  static const String _prefix = 'trendline.snapshot.';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');
}

/// Where snapshots are kept. Overridden in tests.
final snapshotStoreProvider = Provider<SnapshotStore>(
  (ref) => const SecureSnapshotStore(FlutterSecureStorage()),
);

/// Every snapshot the app keeps, so signing out can delete them all.
abstract final class SnapshotKeys {
  static const String today = 'today';
  static const String foods = 'foods';
  static const String recipes = 'recipes';
  static const String weighIns = 'weigh_ins';
  static const String openFoodFacts = 'off';

  static const List<String> all = [
    today,
    foods,
    recipes,
    weighIns,
    openFoodFacts,
  ];
}

/// Deletes every snapshot: nothing of a signed-out user stays on the device.
Future<void> deleteAllSnapshots(SnapshotStore store) async {
  for (final key in SnapshotKeys.all) {
    await store.delete(key);
  }
}

/// A list as last loaded (foods, recipes, weigh-ins), stored as the rows
/// the database returned so the repositories' own parsers read it back.
@immutable
class ListSnapshot {
  const new({
    required this.userId,
    required this.savedAt,
    required this.rows,
  });

  /// Bump when the format changes: older snapshots are then ignored.
  static const int version = 1;

  /// Whose it is. A snapshot is never shown to another account.
  final String userId;
  final DateTime savedAt;
  final List<Map<String, dynamic>> rows;

  String encode() => jsonEncode({
    'v': version,
    'user': userId,
    'saved': savedAt.toUtc().toIso8601String(),
    'rows': rows,
  });

  /// The snapshot in [source], or null if it's missing, from another
  /// format version or damaged in any way (it's only ever a convenience).
  static ListSnapshot? decode(String? source) {
    if (source == null) return null;
    try {
      final m = jsonDecode(source) as Map<String, dynamic>;
      if (m['v'] != version) return null;
      return ListSnapshot(
        userId: m['user'] as String,
        savedAt: DateTime.parse(m['saved'] as String).toLocal(),
        rows: [
          for (final r in m['rows'] as List) r as Map<String, dynamic>,
        ],
      );
    } on Object {
      return null;
    }
  }
}
