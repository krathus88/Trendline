import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';

/// Raised when a library recipe uses a basic food the database doesn't
/// have (the app and its data are out of step).
class LibraryFoodMissing implements Exception {
  const new(this.food);

  final String food;

  String get message =>
      'This recipe needs a basic food that isn’t available ($food). '
      'Try updating the app.';
}

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

  /// The user's copy of a library recipe, if they've added it.
  Recipe? copyOf(LibraryRecipe library) {
    for (final r in state.value ?? const <Recipe>[]) {
      if (r.origin == RecipeOrigin.library && r.sourceId == library.id) {
        return r;
      }
    }
    return null;
  }

  /// Copies [library] into the user's recipes: its basic foods are saved to
  /// their foods (reusing ones already saved), so the copy, its logs and
  /// its prep only ever point at the user's own data. A dish made from a
  /// template is copied the same way, with [origin] template, its basic
  /// foods in [foods] and its expected cooked weight.
  Future<Recipe> addFromLibrary(
    LibraryRecipe library, {
    RecipeOrigin origin = RecipeOrigin.library,
    Map<FoodKey, FoodDraft>? foods,
    double? estimatedCookedWeightG,
  }) async {
    final drafts = switch (foods) {
      final given? => given,
      null => await ref.read(libraryFoodsProvider.future),
    };
    final saved = ref.read(foodsProvider.notifier);
    final ingredients = <RecipeIngredient>[];
    for (final i in library.ingredients) {
      final draft = drafts[i.key];
      if (draft == null) throw LibraryFoodMissing(i.cofidName);
      final food = await saved.save(draft);
      ingredients.add(RecipeIngredient(foodId: food.id, rawGrams: i.rawGrams));
    }
    return await save(
      Recipe(
        id: '',
        name: library.name,
        ingredients: ingredients,
        portions: library.portions,
        fridgeDays: library.fridgeDays,
        freezable: library.freezable,
        method: library.method,
        origin: origin,
        sourceId: library.id,
        sourceVersion: library.version,
        estimatedCookedWeightG: estimatedCookedWeightG,
      ),
    );
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
