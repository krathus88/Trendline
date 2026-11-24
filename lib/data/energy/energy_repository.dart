import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/adaptive_tdee.dart';

/// Days marked complete, and the weekly energy estimates learned from them.
abstract interface class EnergyRepository {
  /// Complete days from [from] to [to], inclusive.
  Future<Set<DateTime>> fetchCompleteDays(DateTime from, DateTime to);

  Future<void> setComplete(DateTime day, {required bool complete});

  /// The latest learned estimate, or null before the first one.
  Future<EnergyEstimate?> fetchLatest();

  /// Stores an update. A second update on the same day is ignored.
  Future<void> save(EnergyEstimate estimate);
}

class SupabaseEnergyRepository implements EnergyRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _estimateColumns =
      'computed_on, tdee_kcal, confidence, window_days, complete_share, '
      'observed_kcal';

  @override
  Future<Set<DateTime>> fetchCompleteDays(DateTime from, DateTime to) async {
    final rows = await _db
        .from('day_logs')
        .select('day')
        .eq('complete', true)
        .gte('day', writeDate(from))
        .lte('day', writeDate(to));
    return {for (final r in rows) readDate(r['day'])};
  }

  @override
  Future<void> setComplete(DateTime day, {required bool complete}) async {
    await _db.from('day_logs').upsert({
      'day': writeDate(day),
      'complete': complete,
    }, onConflict: 'user_id,day');
  }

  @override
  Future<EnergyEstimate?> fetchLatest() async {
    final row = await _db
        .from('energy_estimates')
        .select(_estimateColumns)
        .order('computed_on', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : estimateFromRow(row);
  }

  @override
  Future<void> save(EnergyEstimate e) async {
    await _db
        .from('energy_estimates')
        .upsert(
          {
            'computed_on': writeDate(e.computedOn),
            'tdee_kcal': _round1(e.tdeeKcal),
            'confidence': _round2(e.confidence),
            'window_days': e.windowDays,
            'complete_share': _round2(e.completeShare),
            'observed_kcal': _round1(e.observedKcal),
          },
          onConflict: 'user_id,computed_on',
          ignoreDuplicates: true,
        );
  }
}

EnergyEstimate estimateFromRow(Map<String, dynamic> row) => EnergyEstimate(
  computedOn: readDate(row['computed_on']),
  tdeeKcal: readDouble(row['tdee_kcal']),
  confidence: readDouble(row['confidence']),
  windowDays: (row['window_days'] as num).toInt(),
  completeShare: readDouble(row['complete_share']),
  observedKcal: readDouble(row['observed_kcal']),
);

double _round1(double v) => (v * 10).round() / 10;
double _round2(double v) => (v * 100).round() / 100;
