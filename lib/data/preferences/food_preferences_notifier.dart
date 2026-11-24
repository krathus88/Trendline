import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe_library.dart';

/// The user's likes, dislikes and nevers, cached in memory.
final foodPreferencesProvider =
    AsyncNotifierProvider<FoodPreferencesNotifier, FoodPreferences>(
      FoodPreferencesNotifier.new,
    );

class FoodPreferencesNotifier extends AsyncNotifier<FoodPreferences> {
  @override
  Future<FoodPreferences> build() async {
    if (ref.watch(currentUserIdProvider) == null) return FoodPreferences.none;
    return await ref.watch(foodPreferencesRepositoryProvider).fetch();
  }

  /// Sets or (with null) clears a cuisine preference. Shows the change
  /// straight away; reverts if saving fails.
  Future<void> setCuisine(Cuisine cuisine, Preference? preference) => _change(
    (p) => FoodPreferences(
      ingredients: p.ingredients,
      cuisines: _with(p.cuisines, cuisine, preference),
    ),
    () => ref
        .read(foodPreferencesRepositoryProvider)
        .setCuisine(cuisine, preference),
  );

  /// Sets or (with null) clears a basic-food preference. Shows the change
  /// straight away; reverts if saving fails.
  Future<void> setIngredient(FoodKey food, Preference? preference) => _change(
    (p) => FoodPreferences(
      ingredients: _with(p.ingredients, food, preference),
      cuisines: p.cuisines,
    ),
    () => ref
        .read(foodPreferencesRepositoryProvider)
        .setIngredient(food, preference),
  );

  Future<void> _change(
    FoodPreferences Function(FoodPreferences) apply,
    Future<void> Function() save,
  ) async {
    final before = state.value ?? FoodPreferences.none;
    state = AsyncData(apply(before));
    try {
      await save();
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}

Map<K, Preference> _with<K>(Map<K, Preference> map, K key, Preference? p) {
  final copy = {...map};
  if (p == null) {
    copy.remove(key);
  } else {
    copy[key] = p;
  }
  return copy;
}
