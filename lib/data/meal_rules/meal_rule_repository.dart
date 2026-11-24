import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/meal_rules.dart';

abstract interface class MealRuleRepository {
  Future<List<MealRule>> fetchAll();

  /// Creates [rule] (empty ID) or updates it; returns it as saved.
  Future<MealRule> save(MealRule rule);

  Future<void> delete(String id);
}

class SupabaseMealRuleRepository implements MealRuleRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, food_id, recipe_id, slot, frequency, times_per_week, amount_min, '
      'amount_max';

  @override
  Future<List<MealRule>> fetchAll() async {
    final rows = await _db
        .from('meal_rules')
        .select(_columns)
        .order('created_at');
    return [for (final r in rows) ?mealRuleFromRow(r)];
  }

  @override
  Future<MealRule> save(MealRule rule) async {
    final row = rule.id.isEmpty
        ? await _db
              .from('meal_rules')
              .insert(mealRuleToRow(rule))
              .select(_columns)
              .single()
        : await _db
              .from('meal_rules')
              .update(mealRuleToRow(rule))
              .eq('id', rule.id)
              .select(_columns)
              .single();
    return mealRuleFromRow(row)!;
  }

  @override
  Future<void> delete(String id) async {
    await _db.from('meal_rules').delete().eq('id', id);
  }
}

const Map<String, RuleFrequency> _frequencies = {
  'daily': RuleFrequency.daily,
  'min_per_week': RuleFrequency.minPerWeek,
  'max_per_week': RuleFrequency.maxPerWeek,
};

/// A rule row, or null if it can't be read.
MealRule? mealRuleFromRow(Map<String, dynamic> row) {
  final frequency = _frequencies[row['frequency']];
  final min = readDoubleOrNull(row['amount_min']);
  final max = readDoubleOrNull(row['amount_max']);
  if (frequency == null || min == null || max == null) return null;
  return MealRule(
    id: row['id'] as String,
    foodId: row['food_id'] as String?,
    recipeId: row['recipe_id'] as String?,
    slot: MealSlot.values.asNameMap()[row['slot']],
    frequency: frequency,
    timesPerWeek: row['times_per_week'] as int?,
    amountMin: min,
    amountMax: max,
  );
}

Map<String, dynamic> mealRuleToRow(MealRule r) => {
  'food_id': r.foodId,
  'recipe_id': r.recipeId,
  'slot': r.slot?.name,
  'frequency': _frequencies.entries
      .firstWhere((e) => e.value == r.frequency)
      .key,
  'times_per_week': r.frequency == RuleFrequency.daily ? null : r.timesPerWeek,
  'amount_min': (r.amountMin * 10).round() / 10,
  'amount_max': (r.amountMax * 10).round() / 10,
};
