import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/goals.dart';

abstract interface class GoalRepository {
  /// The active goal (the most recently set), or null if none yet.
  Future<Goal?> fetchActive();

  /// Sets a new goal. Earlier goals are kept as history.
  Future<Goal> save(Goal goal);
}

class SupabaseGoalRepository implements GoalRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'kind, target_weight_kg, pace_mode, pace_value, goal_date';

  @override
  Future<Goal?> fetchActive() async {
    final row = await _db
        .from('goals')
        .select(_columns)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : goalFromRow(row);
  }

  @override
  Future<Goal> save(Goal goal) async {
    final row = await _db
        .from('goals')
        .insert(goalToRow(goal))
        .select(_columns)
        .single();
    return goalFromRow(row);
  }
}

const Map<GoalKind, String> _kinds = {
  GoalKind.targetAndPace: 'target_and_pace',
  GoalKind.targetAndDate: 'target_and_date',
  GoalKind.paceAndDate: 'pace_and_date',
  GoalKind.maintain: 'maintain',
};

/// Only the two values the goal's kind fixes are stored.
Map<String, Object?> goalToRow(Goal g) {
  final usesTarget =
      g.kind == GoalKind.targetAndPace || g.kind == GoalKind.targetAndDate;
  final usesPace =
      g.kind == GoalKind.targetAndPace || g.kind == GoalKind.paceAndDate;
  final usesDate =
      g.kind == GoalKind.targetAndDate || g.kind == GoalKind.paceAndDate;
  return {
    'kind': _kinds[g.kind],
    'target_weight_kg': usesTarget ? g.targetWeightKg : null,
    'pace_mode': g.paceMode == PaceMode.percentPerWeek ? 'pct' : 'kg',
    'pace_value': usesPace ? g.paceValue : null,
    'goal_date': usesDate && g.goalDate != null ? writeDate(g.goalDate!) : null,
  };
}

Goal goalFromRow(Map<String, dynamic> row) => Goal(
  kind: _kinds.entries
      .firstWhere(
        (e) => e.value == row['kind'],
        orElse: () => const MapEntry(GoalKind.maintain, 'maintain'),
      )
      .key,
  targetWeightKg: readDoubleOrNull(row['target_weight_kg']),
  paceMode: row['pace_mode'] == 'pct'
      ? PaceMode.percentPerWeek
      : PaceMode.kgPerWeek,
  paceValue: readDoubleOrNull(row['pace_value']),
  goalDate: row['goal_date'] == null ? null : readDate(row['goal_date']),
);
