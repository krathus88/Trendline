import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';

/// Where on-device snapshots are kept. Only the screens the caching plan
/// lists are snapshotted, and everything is deleted on sign-out.
abstract interface class SnapshotStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Snapshots in the platform's encrypted storage (Android Keystore), like
/// the auth session: they hold health data (what was eaten, targets), so
/// they're never written to plain files.
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

/// The last Today screen loaded: the day's log, targets and plan, so the app
/// can open on it straight away (or without signal) and then refresh.
@immutable
class TodaySnapshot {
  const new({
    required this.userId,
    required this.day,
    required this.savedAt,
    required this.entries,
    required this.targets,
    required this.planned,
  });

  /// Bump when the format changes: older snapshots are then ignored.
  static const int version = 1;

  /// Whose it is. A snapshot is never shown to another account.
  final String userId;
  final DateTime day;
  final DateTime savedAt;
  final List<FoodLogEntry> entries;
  final DailyTargets? targets;

  /// The saved plan's items for [day].
  final List<PlannedItem> planned;

  String encode() => jsonEncode({
    'v': version,
    'user': userId,
    'day': _date(day),
    'saved': savedAt.toUtc().toIso8601String(),
    'entries': [for (final e in entries) _entry(e)],
    'targets': switch (targets) {
      final t? => {
        'kcal': t.kcal,
        'p': t.proteinG,
        'pb': t.proteinBasis.name,
        'f': t.fatG,
        'c': t.carbsG,
        'fi': t.fibreG,
        'wk': t.weeklyChangeKg,
        'floor': t.floorKcal,
        'lim': t.limitedByFloor,
      },
      null => null,
    },
    'planned': [for (final i in planned) _item(i)],
  });

  /// The snapshot in [source], or null if it's missing, from another
  /// format version or damaged in any way (it's only ever a convenience).
  static TodaySnapshot? decode(String? source) {
    if (source == null) return null;
    try {
      final m = jsonDecode(source) as Map<String, dynamic>;
      if (m['v'] != version) return null;
      final t = m['targets'] as Map<String, dynamic>?;
      return TodaySnapshot(
        userId: m['user'] as String,
        day: DateTime.parse(m['day'] as String),
        savedAt: DateTime.parse(m['saved'] as String).toLocal(),
        entries: [
          for (final e in m['entries'] as List)
            _readEntry(e as Map<String, dynamic>),
        ],
        targets: t == null
            ? null
            : DailyTargets(
                kcal: _d(t['kcal']),
                proteinG: _d(t['p']),
                proteinBasis: ProteinBasis.values.byName(t['pb'] as String),
                fatG: _d(t['f']),
                carbsG: _d(t['c']),
                fibreG: _d(t['fi']),
                weeklyChangeKg: _d(t['wk']),
                floorKcal: _d(t['floor']),
                limitedByFloor: t['lim'] as bool,
              ),
        planned: [
          for (final i in m['planned'] as List)
            _readItem(i as Map<String, dynamic>),
        ],
      );
    } on Object {
      return null;
    }
  }
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

double _d(Object? v) => (v! as num).toDouble();

double? _dn(Object? v) => (v as num?)?.toDouble();

Map<String, dynamic> _nutrition(Nutrition n) => {
  'k': n.kcal,
  'p': n.proteinG,
  'c': n.carbsG,
  'f': n.fatG,
  'fi': n.fibreG,
  if (n.fibreUnknown) 'fu': true,
};

Nutrition _readNutrition(Map<String, dynamic> m) => Nutrition(
  kcal: _d(m['k']),
  proteinG: _d(m['p']),
  carbsG: _d(m['c']),
  fatG: _d(m['f']),
  fibreG: _d(m['fi']),
  fibreUnknown: m['fu'] == true,
);

Map<String, dynamic> _entry(FoodLogEntry e) => {
  'id': e.id,
  'on': _date(e.eatenOn),
  'at': e.eatenAt.toUtc().toIso8601String(),
  'slot': e.slot.name,
  'food': ?e.foodId,
  'recipe': ?e.recipeId,
  'name': e.foodName,
  'brand': ?e.foodBrand,
  'g': e.grams,
  'n': _nutrition(e.nutrition),
};

FoodLogEntry _readEntry(Map<String, dynamic> m) => FoodLogEntry(
  id: m['id'] as String,
  eatenOn: DateTime.parse(m['on'] as String),
  eatenAt: DateTime.parse(m['at'] as String).toLocal(),
  slot: MealSlot.values.byName(m['slot'] as String),
  foodId: m['food'] as String?,
  recipeId: m['recipe'] as String?,
  foodName: m['name'] as String,
  foodBrand: m['brand'] as String?,
  grams: _d(m['g']),
  nutrition: _readNutrition(m['n'] as Map<String, dynamic>),
);

Map<String, dynamic> _item(PlannedItem i) => {
  'day': i.day,
  'slot': i.slot.name,
  'key': i.key,
  'name': i.name,
  'a': i.amount,
  'dish': i.isDish,
  'u': _nutrition(i.perUnit),
  'min': ?i.minAmount,
  'max': ?i.maxAmount,
  if (i.locked) 'lock': true,
  'batch': ?i.batch,
  'rule': ?i.ruleId,
  'id': ?i.id,
};

PlannedItem _readItem(Map<String, dynamic> m) => PlannedItem(
  day: m['day'] as int,
  slot: MealSlot.values.byName(m['slot'] as String),
  key: m['key'] as String,
  name: m['name'] as String,
  amount: _d(m['a']),
  isDish: m['dish'] as bool,
  perUnit: _readNutrition(m['u'] as Map<String, dynamic>),
  minAmount: _dn(m['min']),
  maxAmount: _dn(m['max']),
  locked: m['lock'] == true,
  batch: m['batch'] as int?,
  ruleId: m['rule'] as String?,
  id: m['id'] as String?,
);
