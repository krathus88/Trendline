import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/snapshots/snapshot_store.dart';

/// Gives a list notifier an on-device snapshot: the signed-in user's list
/// as last loaded shows straight away while the live one loads, stands in
/// for it without signal, and is rewritten whenever the list changes (so
/// every write the notifier makes refreshes it).
///
/// Only for the lists the caching plan names: the food library and recent
/// weigh-ins. Deleted on sign-out with every other snapshot.
mixin ListSnapshotMixin<T> on AsyncNotifier<List<T>> {
  /// Which snapshot ([SnapshotKeys]).
  String get snapshotKey;

  /// [item] as the database row its repository reads.
  Map<String, dynamic> toSnapshotRow(T item);

  /// Reads a row back, with the repository's own parser.
  T fromSnapshotRow(Map<String, dynamic> row);

  /// What was last written, so an unchanged list isn't written again.
  String? _written;

  /// Loads [userId]'s list with [fetch], showing their snapshot first.
  /// Without signal (or any failure loading) the snapshot is the list; with
  /// no snapshot the failure stands. [keep], when given, drops snapshot
  /// items the live list wouldn't have (weigh-ins older than its window).
  Future<List<T>> loadWithSnapshot(
    String userId,
    Future<List<T>> Function() fetch, {
    bool Function(T item)? keep,
  }) async {
    final store = ref.read(snapshotStoreProvider);
    _written = null;
    final stored = await _read(store, userId);
    final cached = keep == null ? stored : stored?.where(keep).toList();
    // Every change from here on (the live list, then the notifier's own
    // writes) is saved, as long as the same user is signed in.
    listenSelf((_, next) {
      if (next case AsyncData(:final value)) {
        if (ref.read(currentUserIdProvider) == userId) {
          _save(store, userId, value);
        }
      }
    });
    if (cached != null) state = AsyncData(cached);
    try {
      return await fetch();
    } on Object {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<T>?> _read(SnapshotStore store, String userId) async {
    try {
      final stored = await store.read(snapshotKey);
      final snapshot = ListSnapshot.decode(stored);
      if (snapshot == null || snapshot.userId != userId) {
        // Another account's, or unreadable: never shown, so deleted.
        if (stored != null) await _forget(store);
        return null;
      }
      final items = snapshot.rows.map(fromSnapshotRow).toList();
      _written = _rowsOf(stored!);
      return items;
    } on Object {
      // A snapshot is only a convenience: a damaged one is dropped, and
      // storage that can't be read never stops the list loading.
      await _forget(store);
      return null;
    }
  }

  Future<void> _forget(SnapshotStore store) async {
    try {
      await store.delete(snapshotKey);
    } on Object {
      // Nothing more to do: it's never shown either way.
    }
  }

  void _save(SnapshotStore store, String userId, List<T> items) {
    final encoded = ListSnapshot(
      userId: userId,
      savedAt: DateTime.now(),
      rows: [for (final i in items) toSnapshotRow(i)],
    ).encode();
    final rows = _rowsOf(encoded);
    if (rows == _written) return;
    _written = rows;
    // Storage failing only costs the next start its head start.
    store.write(snapshotKey, encoded).ignore();
  }

  /// The snapshot without the time it was saved, for comparing.
  static String _rowsOf(String encoded) =>
      encoded.replaceFirst(RegExp('"saved":"[^"]*"'), '');
}
