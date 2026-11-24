import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';

abstract interface class FoodRepository {
  /// All saved foods, by name.
  Future<List<Food>> fetchAll();

  /// Saves a food. If one with the same barcode is already saved, returns
  /// that instead of creating a duplicate.
  Future<Food> save(FoodDraft draft);

  Future<void> delete(String id);
}

class SupabaseFoodRepository implements FoodRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, barcode, name, brand, kcal_100g, protein_100g, carbs_100g, '
      'fat_100g, fibre_100g, sugar_100g, salt_100g, serving_g, source';

  @override
  Future<List<Food>> fetchAll() async {
    final rows = await _db.from('foods').select(_columns).order('name');
    return rows.map(foodFromRow).toList();
  }

  @override
  Future<Food> save(FoodDraft draft) async {
    final barcode = draft.barcode;
    if (barcode != null) {
      final existing = await _db
          .from('foods')
          .select(_columns)
          .eq('barcode', barcode)
          .maybeSingle();
      if (existing != null) return foodFromRow(existing);
    }
    final row = await _db
        .from('foods')
        .insert(foodDraftToRow(draft))
        .select(_columns)
        .single();
    return foodFromRow(row);
  }

  @override
  Future<void> delete(String id) async {
    // Log entries keep their snapshot; their food_id is set to null.
    await _db.from('foods').delete().eq('id', id);
  }
}

Food foodFromRow(Map<String, dynamic> row) => Food(
  id: row['id'] as String,
  barcode: row['barcode'] as String?,
  name: row['name'] as String,
  brand: row['brand'] as String?,
  per100g: Nutrition(
    kcal: readDouble(row['kcal_100g']),
    proteinG: readDouble(row['protein_100g']),
    carbsG: readDouble(row['carbs_100g']),
    fatG: readDouble(row['fat_100g']),
    fibreG: readDoubleOrNull(row['fibre_100g']) ?? 0,
  ),
  sugarG: readDoubleOrNull(row['sugar_100g']),
  saltG: readDoubleOrNull(row['salt_100g']),
  servingG: readDoubleOrNull(row['serving_g']),
  source: row['source'] == 'off' ? FoodSource.openFoodFacts : FoodSource.manual,
);

Map<String, dynamic> foodDraftToRow(FoodDraft d) => {
  'barcode': d.barcode,
  'name': d.name.trim(),
  'brand': _blankToNull(d.brand),
  'kcal_100g': _round1(d.per100g.kcal),
  'protein_100g': _round1(d.per100g.proteinG),
  'carbs_100g': _round1(d.per100g.carbsG),
  'fat_100g': _round1(d.per100g.fatG),
  'fibre_100g': _round1(d.per100g.fibreG),
  'sugar_100g': d.sugarG == null ? null : _round1(d.sugarG!),
  'salt_100g': d.saltG == null ? null : _round1(d.saltG!),
  'serving_g': d.servingG == null ? null : _round1(d.servingG!),
  'source': d.source == FoodSource.openFoodFacts ? 'off' : 'manual',
};

String? _blankToNull(String? s) {
  final trimmed = s?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

double _round1(double v) => (v * 10).round() / 10;
