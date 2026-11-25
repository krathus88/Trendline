import 'dart:convert';

import 'package:trendline/data/off/off_client.dart';
import 'package:trendline/data/off/off_product.dart';
import 'package:trendline/data/snapshots/snapshot_store.dart';

/// Open Food Facts barcode lookups kept on the device, for the signed-in
/// user only.
///
/// Product data is public, but which products someone looks up says what
/// they eat, so it's kept like the other snapshots: in encrypted storage,
/// tagged with the user, deleted on sign-out. Products are kept for
/// [keepFound] (labels change now and then), "not found" for [keepMissing]
/// (products get added), and only the latest [maxEntries]. Each is read
/// back through [parseOffProduct], with the same checks as a fresh lookup.
class DeviceOffLookupCache implements OffLookupCache {
  new({
    required this._store,
    required this._userId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const int version = 1;
  static const int maxEntries = 100;
  static const Duration keepFound = Duration(days: 30);
  static const Duration keepMissing = Duration(days: 1);

  final SnapshotStore _store;
  final String? Function() _userId;
  final DateTime Function() _clock;

  /// Loaded once per user: barcode → (when, product JSON or null).
  Map<String, ({DateTime at, Map<String, dynamic>? product})>? _entries;
  String? _loadedFor;

  @override
  Future<({OffProduct? product})?> get(String barcode) async {
    final entries = await _load();
    final entry = entries?[barcode];
    if (entry == null) return null;
    final age = _clock().difference(entry.at);
    if (age > (entry.product == null ? keepMissing : keepFound)) return null;
    final json = entry.product;
    if (json == null) return (product: null);
    final product = parseOffProduct(json);
    // Unreadable now (the checks got stricter): look it up again.
    return product == null ? null : (product: product);
  }

  @override
  Future<void> put(String barcode, OffProduct? product) async {
    final entries = await _load();
    final user = _loadedFor;
    if (entries == null || user == null) return;
    entries[barcode] = (
      at: _clock(),
      product: product == null ? null : offProductToJson(product),
    );
    if (entries.length > maxEntries) {
      final oldest = entries.entries.toList()
        ..sort((a, b) => a.value.at.compareTo(b.value.at));
      for (final e in oldest.take(entries.length - maxEntries)) {
        entries.remove(e.key);
      }
    }
    await _store.write(
      SnapshotKeys.openFoodFacts,
      jsonEncode({
        'v': version,
        'user': user,
        'entries': {
          for (final MapEntry(key: code, value: e) in entries.entries)
            code: {'at': e.at.toUtc().toIso8601String(), 'p': e.product},
        },
      }),
    );
  }

  /// The signed-in user's entries, or null when nobody is signed in.
  Future<Map<String, ({DateTime at, Map<String, dynamic>? product})>?>
  _load() async {
    final user = _userId();
    if (user == null) return null;
    if (_loadedFor == user && _entries != null) return _entries;
    _loadedFor = user;
    return _entries = await _read(user);
  }

  Future<Map<String, ({DateTime at, Map<String, dynamic>? product})>> _read(
    String user,
  ) async {
    final empty = <String, ({DateTime at, Map<String, dynamic>? product})>{};
    final stored = await _store.read(SnapshotKeys.openFoodFacts);
    if (stored == null) return empty;
    try {
      final m = jsonDecode(stored) as Map<String, dynamic>;
      if (m['v'] == version && m['user'] == user) {
        return {
          for (final MapEntry(key: code, value: e)
              in (m['entries'] as Map<String, dynamic>).entries)
            code: (
              at: DateTime.parse((e as Map<String, dynamic>)['at'] as String),
              product: e['p'] as Map<String, dynamic>?,
            ),
        };
      }
    } on Object {
      // Damaged: dropped below.
    }
    // Another account's, an old format or damaged: never used, so deleted.
    await _store.delete(SnapshotKeys.openFoodFacts);
    return empty;
  }
}
