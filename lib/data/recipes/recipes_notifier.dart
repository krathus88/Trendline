import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/recipe.dart';

/// The user's recipes, by name, cached in memory.
final recipesProvider = AsyncNotifierProvider<RecipesNotifier, List<Recipe>>(
  RecipesNotifier.new,
);

/// The user's foods by ID, for ingredient names and recipe nutrition.
final foodsByIdProvider = Provider<Map<String, Food>>((ref) {
  final foods = ref.watch(foodsProvider).value ?? const <Food>[];
  return {for (final f in foods) f.id: f};
});

class RecipesNotifier extends AsyncNotifier<List<Recipe>> {
  @override
  Future<List<Recipe>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    return await ref.watch(recipeRepositoryProvider).fetchAll();
  }

  /// Creates or updates [recipe] (an empty ID creates it) and returns it as
  /// saved.
  Future<Recipe> save(Recipe recipe) async {
    final saved = await ref.read(recipeRepositoryProvider).save(recipe);
    final current = state.value ?? const <Recipe>[];
    state = AsyncData(
      _byName([
        for (final r in current)
          if (r.id != saved.id) r,
        saved,
      ]),
    );
    return saved;
  }

  /// Removes the recipe straight away; puts it back if the delete fails.
  /// Past log entries keep their own copy of its details.
  Future<void> delete(String id) async {
    final before = state.value ?? const <Recipe>[];
    state = AsyncData([
      for (final r in before)
        if (r.id != id) r,
    ]);
    try {
      await ref.read(recipeRepositoryProvider).delete(id);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }

  static List<Recipe> _byName(List<Recipe> list) =>
      list
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
