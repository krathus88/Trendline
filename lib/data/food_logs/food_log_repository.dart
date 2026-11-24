import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

abstract interface class FoodLogRepository {
  /// Everything logged on the local calendar [day], oldest first.
  Future<List<FoodLogEntry>> fetchDay(DateTime day);

  /// Logs [grams] of [food] on [day], snapshotting its name and nutrition.
  Future<FoodLogEntry> add({
    required DateTime day,
    required MealSlot slot,
    required Food food,
    required double grams,
  });

  /// Logs [grams] (cooked) of [recipe] on [day], snapshotting its name and
  /// nutrition ([per100gCooked]), so editing the recipe never rewrites
  /// history.
  Future<FoodLogEntry> addRecipe({
    required DateTime day,
    required MealSlot slot,
    required Recipe recipe,
    required Nutrition per100gCooked,
    required double grams,
  });

  /// Changes the portion. Nutrition is rescaled from the entry's own
  /// snapshot, so it stays consistent even if the food has since changed.
  Future<FoodLogEntry> updateGrams(FoodLogEntry entry, double grams);

  Future<void> delete(String id);

  /// Total kcal logged on each day from [from] to [to], inclusive. Days with
  /// nothing logged are absent.
  Future<Map<DateTime, double>> fetchDailyKcal(DateTime from, DateTime to);
}

class SupabaseFoodLogRepository implements FoodLogRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, eaten_on, eaten_at, slot, food_id, recipe_id, food_name, '
      'food_brand, grams, '
      'kcal, protein_g, carbs_g, fat_g, fibre_g';

  @override
  Future<List<FoodLogEntry>> fetchDay(DateTime day) async {
    final rows = await _db
        .from('food_logs')
        .select(_columns)
        .eq('eaten_on', writeDate(day))
        .order('eaten_at');
    return rows.map(foodLogFromRow).toList();
  }

  @override
  Future<Map<DateTime, double>> fetchDailyKcal(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _db
        .from('food_logs')
        .select('eaten_on, kcal')
        .gte('eaten_on', writeDate(from))
        .lte('eaten_on', writeDate(to));
    final totals = <DateTime, double>{};
    for (final r in rows) {
      final day = readDate(r['eaten_on']);
      totals[day] = (totals[day] ?? 0) + readDouble(r['kcal']);
    }
    return totals;
  }

  @override
  Future<FoodLogEntry> add({
    required DateTime day,
    required MealSlot slot,
    required Food food,
    required double grams,
  }) async {
    final row = await _db
        .from('food_logs')
        .insert(
          foodLogToRow(
            day: day,
            eatenAt: DateTime.now(),
            slot: slot,
            food: food,
            grams: grams,
          ),
        )
        .select(_columns)
        .single();
    return foodLogFromRow(row);
  }

  @override
  Future<FoodLogEntry> addRecipe({
    required DateTime day,
    required MealSlot slot,
    required Recipe recipe,
    required Nutrition per100gCooked,
    required double grams,
  }) async {
    final row = await _db
        .from('food_logs')
        .insert(
          recipeLogToRow(
            day: day,
            eatenAt: DateTime.now(),
            slot: slot,
            recipe: recipe,
            per100gCooked: per100gCooked,
            grams: grams,
          ),
        )
        .select(_columns)
        .single();
    return foodLogFromRow(row);
  }

  @override
  Future<FoodLogEntry> updateGrams(FoodLogEntry entry, double grams) async {
    final n = rescale(entry.nutrition, from: entry.grams, to: grams);
    final row = await _db
        .from('food_logs')
        .update({'grams': _round1(grams), ..._nutritionColumns(n)})
        .eq('id', entry.id)
        .select(_columns)
        .single();
    return foodLogFromRow(row);
  }

  @override
  Future<void> delete(String id) async {
    await _db.from('food_logs').delete().eq('id', id);
  }
}

FoodLogEntry foodLogFromRow(Map<String, dynamic> row) => FoodLogEntry(
  id: row['id'] as String,
  eatenOn: readDate(row['eaten_on']),
  eatenAt: readDateTime(row['eaten_at']),
  slot: MealSlot.values.byName(row['slot'] as String),
  foodId: row['food_id'] as String?,
  recipeId: row['recipe_id'] as String?,
  foodName: row['food_name'] as String,
  foodBrand: row['food_brand'] as String?,
  grams: readDouble(row['grams']),
  nutrition: Nutrition(
    kcal: readDouble(row['kcal']),
    proteinG: readDouble(row['protein_g']),
    carbsG: readDouble(row['carbs_g']),
    fatG: readDouble(row['fat_g']),
    fibreG: readDoubleOrNull(row['fibre_g']) ?? 0,
    fibreUnknown: readDoubleOrNull(row['fibre_g']) == null,
  ),
);

Map<String, dynamic> foodLogToRow({
  required DateTime day,
  required DateTime eatenAt,
  required MealSlot slot,
  required Food food,
  required double grams,
}) => {
  'eaten_on': writeDate(day),
  'eaten_at': writeTimestamp(eatenAt),
  'slot': slot.name,
  'food_id': food.id,
  'food_name': food.name,
  'food_brand': food.brand,
  'grams': _round1(grams),
  ..._nutritionColumns(food.per100g.forGrams(grams)),
};

Map<String, dynamic> recipeLogToRow({
  required DateTime day,
  required DateTime eatenAt,
  required MealSlot slot,
  required Recipe recipe,
  required Nutrition per100gCooked,
  required double grams,
}) => {
  'eaten_on': writeDate(day),
  'eaten_at': writeTimestamp(eatenAt),
  'slot': slot.name,
  'recipe_id': recipe.id,
  'food_name': recipe.name.trim(),
  'grams': _round1(grams),
  ..._nutritionColumns(per100gCooked.forGrams(grams)),
};

/// [n] for [from] grams, rescaled to [to] grams.
Nutrition rescale(Nutrition n, {required double from, required double to}) {
  if (from <= 0) return Nutrition.zero;
  final f = to / from;
  return Nutrition(
    kcal: _round1(n.kcal * f),
    proteinG: _round1(n.proteinG * f),
    carbsG: _round1(n.carbsG * f),
    fatG: _round1(n.fatG * f),
    fibreG: _round1(n.fibreG * f),
    fibreUnknown: n.fibreUnknown,
  );
}

Map<String, dynamic> _nutritionColumns(Nutrition n) => {
  'kcal': n.kcal,
  'protein_g': n.proteinG,
  'carbs_g': n.carbsG,
  'fat_g': n.fatG,
  'fibre_g': n.fibreUnknown ? null : n.fibreG,
};

double _round1(double v) => (v * 10).round() / 10;
