import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/recipe.dart';

abstract interface class RecipeRepository {
  /// All the user's recipes, by name, with their ingredients in order.
  Future<List<Recipe>> fetchAll();

  /// Saves [recipe] and its ingredients together. A recipe with an empty
  /// [Recipe.id] is created; otherwise it's updated. Returns it as saved.
  Future<Recipe> save(Recipe recipe);

  Future<void> delete(String id);
}

class SupabaseRecipeRepository implements RecipeRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'id, name, method, portions, cooked_weight_g, fridge_days, freezable, '
      'origin, source_id, source_version, '
      'recipe_ingredients(food_id, raw_grams, position)';

  @override
  Future<List<Recipe>> fetchAll() async {
    final rows = await _db
        .from('recipes')
        .select(_columns)
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
  'source_id': r.origin == RecipeOrigin.user ? null : r.sourceId,
  'source_version': r.origin == RecipeOrigin.user ? null : r.sourceVersion,
  'ingredients': [
    for (final i in r.ingredients)
      {'food_id': i.foodId, 'raw_grams': (i.rawGrams * 10).round() / 10},
  ],
};

String? _blankToNull(String? s) {
  final trimmed = s?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
