import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe_library.dart';

abstract interface class FoodPreferencesRepository {
  Future<FoodPreferences> fetch();

  /// Sets how the user feels about [cuisine]; null clears it.
  Future<void> setCuisine(Cuisine cuisine, Preference? preference);

  /// Sets how the user feels about a basic food; null clears it.
  Future<void> setIngredient(FoodKey food, Preference? preference);
}

class SupabaseFoodPreferencesRepository implements FoodPreferencesRepository {
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<FoodPreferences> fetch() async {
    final rows = await _db
        .from('food_preferences')
        .select('cuisine, cofid_code, cofid_name, preference');
    return foodPreferencesFromRows(rows);
  }

  @override
  Future<void> setCuisine(Cuisine cuisine, Preference? preference) async {
    // One row per cuisine (a unique index): clear, then set.
    await _db.from('food_preferences').delete().eq('cuisine', cuisine.name);
    if (preference == null) return;
    await _db.from('food_preferences').insert({
      'cuisine': cuisine.name,
      'preference': preference.name,
    });
  }

  @override
  Future<void> setIngredient(FoodKey food, Preference? preference) async {
    await _db
        .from('food_preferences')
        .delete()
        .eq('cofid_code', food.code)
        .eq('cofid_name', food.name);
    if (preference == null) return;
    await _db.from('food_preferences').insert({
      'cofid_code': food.code,
      'cofid_name': food.name,
      'preference': preference.name,
    });
  }
}

/// Preference rows as [FoodPreferences]. Unknown values are skipped.
FoodPreferences foodPreferencesFromRows(List<Map<String, dynamic>> rows) {
  final ingredients = <FoodKey, Preference>{};
  final cuisines = <Cuisine, Preference>{};
  for (final row in rows) {
    final preference = Preference.values.asNameMap()[row['preference']];
    if (preference == null) continue;
    final cuisine = Cuisine.values.asNameMap()[row['cuisine']];
    final code = row['cofid_code'];
    final name = row['cofid_name'];
    if (cuisine != null) {
      cuisines[cuisine] = preference;
    } else if (code is String && name is String) {
      ingredients[(code: code, name: name)] = preference;
    }
  }
  return FoodPreferences(ingredients: ingredients, cuisines: cuisines);
}
