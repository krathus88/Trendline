import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/prep.dart';

/// Prep sessions and their portions. Sessions are laid out by the database
/// when a plan is saved; the app marks them cooked and updates portions.
abstract interface class PrepRepository {
  /// Sessions cooked on or after [from], with their portions: the user's
  /// own, and their household's (with every member's portions).
  Future<List<PrepSession>> fetchFrom(DateTime from);

  /// Marks [sessionId] cooked now, with the batch's measured weight.
  Future<PrepSession> markCooked(String sessionId, double cookedWeightG);

  /// Saves where [portion] is kept, when it's for and what became of it.
  Future<void> updatePortion(PrepPortion portion);
}

class SupabasePrepRepository implements PrepRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, plan_id, household_id, recipe_id, cook_on, portions, cooked_at, '
      'cooked_weight_g, prep_portions(id, session_id, eater_id, day, slot, '
      'amount, use_by, storage, status, food_log_id)';

  @override
  Future<List<PrepSession>> fetchFrom(DateTime from) async {
    final rows = await _db
        .from('prep_sessions')
        .select(_columns)
        .gte('cook_on', writeDate(from))
        .order('cook_on');
    return rows.map(prepSessionFromRow).toList();
  }

  @override
  Future<PrepSession> markCooked(String sessionId, double cookedWeightG) async {
    final row = await _db
        .from('prep_sessions')
        .update({
          'cooked_at': writeTimestamp(DateTime.now()),
          'cooked_weight_g': (cookedWeightG * 10).round() / 10,
        })
        .eq('id', sessionId)
        .select(_columns)
        .single();
    return prepSessionFromRow(row);
  }

  @override
  Future<void> updatePortion(PrepPortion portion) async {
    await _db
        .from('prep_portions')
        .update(prepPortionToRow(portion))
        .eq('id', portion.id);
  }
}

PrepSession prepSessionFromRow(Map<String, dynamic> row) {
  final cookedAt = row['cooked_at'];
  return PrepSession(
    id: row['id'] as String,
    planId: row['plan_id'] as String?,
    householdId: row['household_id'] as String?,
    recipeId: row['recipe_id'] as String,
    cookOn: readDate(row['cook_on']),
    portionCount: readDouble(row['portions']),
    cookedAt: cookedAt == null ? null : readDateTime(cookedAt),
    cookedWeightG: readDoubleOrNull(row['cooked_weight_g']),
    portions: [
      for (final p in (row['prep_portions'] as List? ?? const []))
        ?_portionFromRow(p as Map<String, dynamic>),
    ]..sort(_byMeal),
  );
}

int _byMeal(PrepPortion a, PrepPortion b) {
  final ad = a.day;
  final bd = b.day;
  if (ad == null || bd == null) {
    // Leftovers after planned meals.
    return (ad == null ? 1 : 0) - (bd == null ? 1 : 0);
  }
  final byDay = ad.compareTo(bd);
  return byDay != 0 ? byDay : a.slot!.index.compareTo(b.slot!.index);
}

PrepPortion? _portionFromRow(Map<String, dynamic> row) {
  final amount = readDoubleOrNull(row['amount']);
  final storage = PrepStorage.values.asNameMap()[row['storage']];
  final status = PortionStatus.values.asNameMap()[row['status']];
  if (amount == null || storage == null || status == null) return null;
  final day = row['day'];
  final slot = MealSlot.values.asNameMap()[row['slot']];
  if ((day == null) != (slot == null)) return null;
  return PrepPortion(
    id: row['id'] as String,
    sessionId: row['session_id'] as String,
    eaterId: row['eater_id'] as String?,
    day: day == null ? null : readDate(day),
    slot: slot,
    amount: amount,
    useBy: readDate(row['use_by']),
    storage: storage,
    status: status,
    foodLogId: row['food_log_id'] as String?,
  );
}

Map<String, dynamic> prepPortionToRow(PrepPortion p) => {
  'day': p.day == null ? null : writeDate(p.day!),
  'slot': p.day == null ? null : p.slot?.name,
  'use_by': writeDate(p.useBy),
  'storage': p.storage.name,
  'status': p.status.name,
  'food_log_id': p.foodLogId,
};
