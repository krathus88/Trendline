import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';

/// Raised when deleting a food that a recipe still uses.
class FoodInUse implements Exception {
  const new();

  String get message =>
      'This food is in a recipe. Take it out of the recipe first.';
}

abstract interface class FoodRepository {
  /// All the user's own saved foods, by name.
  Future<List<Food>> fetchAll();

  /// The foods in the household's shared recipes (none outside one).
  Future<List<Food>> fetchShared();

  /// Saves a food. If one with the same barcode, or a copy of the same
  /// basic food, is already saved, returns that instead of a duplicate.
  Future<Food> save(FoodDraft draft);

  Future<void> delete(String id);
}

class SupabaseFoodRepository implements FoodRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, barcode, name, brand, kcal_100g, protein_100g, carbs_100g, '
      'fat_100g, fibre_100g, sugar_100g, salt_100g, serving_g, source, '
      'reference_code';

  // RLS shows the household's shared foods too, so each query says which.
  @override
  Future<List<Food>> fetchAll() async {
    final rows = await _db
        .from('foods')
        .select(_columns)
        .isFilter('household_id', null)
        .order('name');
    return rows.map(foodFromRow).toList();
  }

  @override
  Future<List<Food>> fetchShared() async {
    final rows = await _db
        .from('foods')
        .select(_columns)
        .not('household_id', 'is', null)
        .order('name');
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
          .isFilter('household_id', null)
          .maybeSingle();
      if (existing != null) return foodFromRow(existing);
    }
    final code = draft.referenceCode;
    if (code != null) {
      // CoFID codes aren't unique on their own, so the name must match too.
      final existing = await _db
          .from('foods')
          .select(_columns)
          .eq('reference_code', code)
          .eq('name', draft.name.trim())
          .isFilter('household_id', null)
          .limit(1)
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
    // Recipes block it (foreign key), so an ingredient never disappears.
    try {
      await _db.from('foods').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (e.code == '23503') throw const FoodInUse();
      rethrow;
    }
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
    fibreUnknown: readDoubleOrNull(row['fibre_100g']) == null,
  ),
  sugarG: readDoubleOrNull(row['sugar_100g']),
  saltG: readDoubleOrNull(row['salt_100g']),
  servingG: readDoubleOrNull(row['serving_g']),
  source: switch (row['source']) {
    'off' => FoodSource.openFoodFacts,
    'cofid' => FoodSource.cofid,
    _ => FoodSource.manual,
  },
  referenceCode: row['reference_code'] as String?,
);

/// [f] as the row [foodFromRow] reads, for the on-device snapshot.
Map<String, dynamic> foodToRow(Food f) => {
  'id': f.id,
  'barcode': f.barcode,
  'name': f.name,
  'brand': f.brand,
  'kcal_100g': f.per100g.kcal,
  'protein_100g': f.per100g.proteinG,
  'carbs_100g': f.per100g.carbsG,
  'fat_100g': f.per100g.fatG,
  'fibre_100g': f.per100g.fibreUnknown ? null : f.per100g.fibreG,
  'sugar_100g': f.sugarG,
  'salt_100g': f.saltG,
  'serving_g': f.servingG,
  'source': switch (f.source) {
    FoodSource.openFoodFacts => 'off',
    FoodSource.cofid => 'cofid',
    FoodSource.manual => 'manual',
  },
  'reference_code': f.referenceCode,
};

Map<String, dynamic> foodDraftToRow(FoodDraft d) => {
  'barcode': d.barcode,
  'name': d.name.trim(),
  'brand': _blankToNull(d.brand),
  'kcal_100g': _round1(d.per100g.kcal),
  'protein_100g': _round1(d.per100g.proteinG),
  'carbs_100g': _round1(d.per100g.carbsG),
  'fat_100g': _round1(d.per100g.fatG),
  'fibre_100g': d.per100g.fibreUnknown ? null : _round1(d.per100g.fibreG),
  'sugar_100g': d.sugarG == null ? null : _round1(d.sugarG!),
  'salt_100g': d.saltG == null ? null : _round1(d.saltG!),
  'serving_g': d.servingG == null ? null : _round1(d.servingG!),
  'source': switch (d.source) {
    FoodSource.openFoodFacts => 'off',
    FoodSource.manual => 'manual',
    FoodSource.cofid => 'cofid',
  },
  'reference_code': d.source == FoodSource.cofid ? d.referenceCode : null,
};

String? _blankToNull(String? s) {
  final trimmed = s?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

double _round1(double v) => (v * 10).round() / 10;
