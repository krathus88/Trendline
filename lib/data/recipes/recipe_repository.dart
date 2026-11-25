import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/recipe.dart';

abstract interface class RecipeRepository {
  /// All the user's own recipes, by name, with their ingredients in order.
  Future<List<Recipe>> fetchAll();

  /// The recipes shared with the user's household (none outside one).
  Future<List<Recipe>> fetchShared();

  /// Saves [recipe] and its ingredients together. A recipe with an empty
  /// [Recipe.id] is created (shared with [Recipe.householdId] if set);
  /// otherwise it's updated. The database swaps each ingredient for the
  /// recipe owner's copy of its food, making one if needed. Returns it as
  /// saved.
  Future<Recipe> save(Recipe recipe);

  Future<void> delete(String id);

  /// Shows or hides a recipe in the Recipes list.
  Future<void> setListed(String id, {required bool listed});
}

class SupabaseRecipeRepository implements RecipeRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, name, method, portions, cooked_weight_g, fridge_days, freezable, '
      'origin, source_id, source_version, estimated_cooked_weight_g, listed, '
      'household_id, recipe_ingredients(food_id, raw_grams, position)';

  // RLS shows the household's shared recipes too, so each list says which.
  @override
  Future<List<Recipe>> fetchAll() async {
    final rows = await _db
        .from('recipes')
        .select(_columns)
        .isFilter('household_id', null)
        .order('name')
        .order('position', referencedTable: 'recipe_ingredients');
    return rows.map(recipeFromRow).toList();
  }

  @override
  Future<List<Recipe>> fetchShared() async {
    final rows = await _db
        .from('recipes')
        .select(_columns)
        .not('household_id', 'is', null)
        .order('name')
        .order('position', referencedTable: 'recipe_ingredients');
    return rows.map(recipeFromRow).toList();
  }

  @override
  Future<Recipe> save(Recipe recipe) async {
    // One database function saves the recipe and replaces its ingredients
    // in a single transaction, so a failed save leaves nothing half-done.
    final id = await _db.rpc<String>(
      'save_recipe',
      params: saveRecipeParams(recipe),
    );
    final row = await _db
        .from('recipes')
        .select(_columns)
        .eq('id', id)
        .order('position', referencedTable: 'recipe_ingredients')
        .single();
    return recipeFromRow(row);
  }

  @override
  Future<void> delete(String id) async {
    // Log entries keep their snapshot; their recipe_id is set to null.
    await _db.from('recipes').delete().eq('id', id);
  }

  @override
  Future<void> setListed(String id, {required bool listed}) async {
    await _db.from('recipes').update({'listed': listed}).eq('id', id);
  }
}

Recipe recipeFromRow(Map<String, dynamic> row) {
  final items = [
    for (final i in (row['recipe_ingredients'] as List? ?? const []))
      i as Map<String, dynamic>,
  ]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
  return Recipe(
    id: row['id'] as String,
    name: row['name'] as String,
    method: row['method'] as String?,
    portions: row['portions'] as int,
    cookedWeightG: readDoubleOrNull(row['cooked_weight_g']),
    fridgeDays: row['fridge_days'] as int,
    freezable: row['freezable'] as bool,
    origin: RecipeOrigin.values.byName(row['origin'] as String? ?? 'user'),
    sourceId: row['source_id'] as String?,
    sourceVersion: row['source_version'] as int?,
    estimatedCookedWeightG: readDoubleOrNull(row['estimated_cooked_weight_g']),
    listed: row['listed'] as bool? ?? true,
    householdId: row['household_id'] as String?,
    ingredients: [
      for (final i in items)
        RecipeIngredient(
          foodId: i['food_id'] as String,
          rawGrams: readDouble(i['raw_grams']),
        ),
    ],
  );
}

Map<String, dynamic> saveRecipeParams(Recipe r) => {
  'recipe_id': r.id.isEmpty ? null : r.id,
  'name': r.name.trim(),
  'portions': r.portions,
  'cooked_weight_g': r.cookedWeightG == null
      ? null
      : (r.cookedWeightG! * 10).round() / 10,
  'fridge_days': r.fridgeDays,
  'freezable': r.freezable,
  'method': _blankToNull(r.method),
  // Kept by the database on updates; only used when the recipe is created.
  'origin': r.origin.name,
  'source_id': r.origin.hasSource ? r.sourceId : null,
  'source_version': r.origin.hasSource ? r.sourceVersion : null,
  'estimated_cooked_weight_g': r.estimatedCookedWeightG == null
      ? null
      : (r.estimatedCookedWeightG! * 10).round() / 10,
  // Only used when the recipe is created; a recipe never changes owner.
  'household_id': r.householdId,
  'ingredients': [
    for (final i in r.ingredients)
      {'food_id': i.foodId, 'raw_grams': (i.rawGrams * 10).round() / 10},
  ],
};

String? _blankToNull(String? s) {
  final trimmed = s?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
