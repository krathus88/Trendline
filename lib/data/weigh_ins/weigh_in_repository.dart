import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/weigh_in.dart';

abstract interface class WeighInRepository {
  /// Weigh-ins measured on or after [since], newest first.
  Future<List<WeighIn>> fetchSince(DateTime since);

  Future<WeighIn> add({
    required DateTime measuredAt,
    required double weightKg,
    double? bodyFatPct,
  });

  Future<void> delete(String id);
}

class SupabaseWeighInRepository implements WeighInRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, measured_at, weight_kg, body_fat_pct, lean_mass_kg, source';

  @override
  Future<List<WeighIn>> fetchSince(DateTime since) async {
    final rows = await _db
        .from('weigh_ins')
        .select(_columns)
        .gte('measured_at', writeTimestamp(since))
        .order('measured_at', ascending: false);
    return rows.map(weighInFromRow).toList();
  }

  @override
  Future<WeighIn> add({
    required DateTime measuredAt,
    required double weightKg,
    double? bodyFatPct,
  }) async {
    final row = await _db
        .from('weigh_ins')
        .insert({
          'measured_at': writeTimestamp(measuredAt),
          'weight_kg': _round2(weightKg),
          'body_fat_pct': ?bodyFatPct,
          'source': 'manual',
        })
        .select(_columns)
        .single();
    return weighInFromRow(row);
  }

  @override
  Future<void> delete(String id) async {
    await _db.from('weigh_ins').delete().eq('id', id);
  }
}

WeighIn weighInFromRow(Map<String, dynamic> row) => WeighIn(
  id: row['id'] as String,
  measuredAt: readDateTime(row['measured_at']),
  weightKg: readDouble(row['weight_kg']),
  bodyFatPct: readDoubleOrNull(row['body_fat_pct']),
  leanMassKg: readDoubleOrNull(row['lean_mass_kg']),
  source: row['source'] == 'health_connect'
      ? WeighInSource.healthConnect
      : WeighInSource.manual,
);

double _round2(double v) => (v * 100).round() / 100;
