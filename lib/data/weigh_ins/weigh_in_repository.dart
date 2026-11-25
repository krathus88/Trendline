import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/domain/weigh_in.dart';

abstract interface class WeighInRepository {
  /// Weigh-ins measured on or after [since], newest first.
  Future<List<WeighIn>> fetchSince(DateTime since);

  Future<WeighIn> add({
    required DateTime measuredAt,
    required double weightKg,
    double? bodyFatPct,
  });

  /// Deleting an imported reading also stops it being imported again.
  Future<void> delete(String id);

  /// Saves readings from Health Connect. Readings already stored, or deleted
  /// by the user before, are skipped. Returns how many were added.
  Future<int> importHealthConnect(List<ImportedWeighIn> readings);
}

class SupabaseWeighInRepository implements WeighInRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, measured_at, weight_kg, body_fat_pct, lean_mass_kg, source, '
      'external_id';

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

  /// Rows per request, to keep request bodies small on a first full import.
  static const _importBatch = 200;

  @override
  Future<int> importHealthConnect(List<ImportedWeighIn> readings) async {
    var added = 0;
    for (var i = 0; i < readings.length; i += _importBatch) {
      final batch = readings.skip(i).take(_importBatch);
      // Every row has the same keys: a bulk insert requires it.
      final rows = [
        for (final r in batch)
          {
            'measured_at': writeTimestamp(r.measuredAt),
            'weight_kg': _round2(r.weightKg),
            'body_fat_pct': r.bodyFatPct,
            'lean_mass_kg': switch (r.leanMassKg) {
              final kg? => _round2(kg),
              null => null,
            },
            'source': 'health_connect',
            'external_id': r.externalId,
          },
      ];
      final inserted = await _db
          .from('weigh_ins')
          .upsert(
            rows,
            onConflict: 'user_id,source,external_id',
            ignoreDuplicates: true,
          )
          .select('id');
      added += inserted.length;
    }
    return added;
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
  externalId: row['external_id'] as String?,
);

/// [w] as the row [weighInFromRow] reads, for the on-device snapshot.
Map<String, dynamic> weighInToRow(WeighIn w) => {
  'id': w.id,
  'measured_at': writeTimestamp(w.measuredAt),
  'weight_kg': w.weightKg,
  'body_fat_pct': w.bodyFatPct,
  'lean_mass_kg': w.leanMassKg,
  'source': switch (w.source) {
    WeighInSource.healthConnect => 'health_connect',
    WeighInSource.manual => 'manual',
  },
  'external_id': w.externalId,
};

double _round2(double v) => (v * 100).round() / 100;
