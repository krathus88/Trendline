import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/food_logs/food_log_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipe_repository.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

void main() {
  group('recipe rows', () {
    test('ingredients come back in their saved order', () {
      final r = recipeFromRow({
        'id': 'r1',
        'name': 'Chicken rice',
        'method': null,
        'portions': 4,
        'cooked_weight_g': '1425.0',
        'fridge_days': 3,
        'freezable': true,
        'recipe_ingredients': [
          {'food_id': 'chicken', 'raw_grams': '600.0', 'position': 1},
          {'food_id': 'rice', 'raw_grams': 300, 'position': 0},
        ],
      });
      expect(r.ingredients.map((i) => i.foodId), ['rice', 'chicken']);
      expect(r.cookedWeightG, 1425);
      expect(r.portionG, closeTo(356.25, 1e-9));
    });

    test('an unweighed recipe has no cooked weight', () {
      final r = recipeFromRow({
        'id': 'r1',
        'name': 'Stew',
        'portions': 2,
        'cooked_weight_g': null,
        'fridge_days': 4,
        'freezable': false,
        'recipe_ingredients': <Object>[],
      });
      expect(r.cookedWeightG, isNull);
      expect(r.portionG, isNull);
    });

    test('saving sends a new recipe without an ID, trimmed and rounded', () {
      final params = saveRecipeParams(
        const Recipe(
          id: '',
          name: '  Chicken rice ',
          method: '   ',
          cookedWeightG: 1425.04,
          ingredients: [RecipeIngredient(foodId: 'rice', rawGrams: 299.96)],
        ),
      );
      expect(params['recipe_id'], isNull);
      expect(params['name'], 'Chicken rice');
      expect(params['method'], isNull);
      expect(params['cooked_weight_g'], 1425.0);
      expect(params['ingredients'], [
        {'food_id': 'rice', 'raw_grams': 300.0},
      ]);
    });

    test('a logged recipe portion snapshots the recipe', () {
      final row = recipeLogToRow(
        day: DateTime(2026, 11, 24),
        eatenAt: DateTime(2026, 11, 24, 19),
        slot: MealSlot.dinner,
        recipe: const Recipe(id: 'r1', name: 'Chicken rice', ingredients: []),
        per100gCooked: const Nutrition(
          kcal: 120,
          proteinG: 11.8,
          carbsG: 16,
          fatG: 0.7,
          fibreUnknown: true,
        ),
        grams: 350,
      );
      expect(row['recipe_id'], 'r1');
      expect(row.containsKey('food_id'), isFalse);
      expect(row['food_name'], 'Chicken rice');
      expect(row['kcal'], 420);
      expect(row['fibre_g'], isNull, reason: 'unknown fibre stays unknown');

      final entry = foodLogFromRow({
        ...row,
        'id': 'l1',
        'eaten_at': '2026-11-24T19:00:00Z',
      });
      expect(entry.recipeId, 'r1');
      expect(entry.foodId, isNull);
    });
  });

  group('RecipesNotifier', () {
    late FakeAuthRepository auth;
    late FakeRecipeRepository recipes;
    late ProviderContainer container;

    setUp(() async {
      auth = FakeAuthRepository(initial: const SignedIn('user-1'));
      recipes = FakeRecipeRepository();
      container = ProviderContainer.test(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          recipeRepositoryProvider.overrideWithValue(recipes),
          foodRepositoryProvider.overrideWithValue(FakeFoodRepository()),
        ],
      )..listen(authStatusProvider, (_, _) {});
      await container.read(authStatusProvider.future);
      container.listen(recipesProvider, (_, _) {});
    });

    tearDown(() => auth.dispose());

    const stew = Recipe(
      id: '',
      name: 'Stew',
      ingredients: [RecipeIngredient(foodId: 'f1', rawGrams: 500)],
    );

    test('saving adds the recipe, in name order', () async {
      await container.read(recipesProvider.future);
      final n = container.read(recipesProvider.notifier);
      await n.save(stew);
      await n.save(
        const Recipe(
          id: '',
          name: 'apple crumble',
          ingredients: [RecipeIngredient(foodId: 'f1', rawGrams: 100)],
        ),
      );
      expect(container.read(recipesProvider).value!.map((r) => r.name), [
        'apple crumble',
        'Stew',
      ]);
    });

    test('saving an existing recipe replaces it', () async {
      await container.read(recipesProvider.future);
      final n = container.read(recipesProvider.notifier);
      final saved = await n.save(stew);
      await n.save(
        Recipe(
          id: saved.id,
          name: 'Stew',
          ingredients: saved.ingredients,
          cookedWeightG: 900,
        ),
      );
      final list = container.read(recipesProvider).value!;
      expect(list, hasLength(1));
      expect(list.single.cookedWeightG, 900);
    });

    test('deleting removes it', () async {
      await container.read(recipesProvider.future);
      final n = container.read(recipesProvider.notifier);
      final saved = await n.save(stew);
      await n.delete(saved.id);
      expect(container.read(recipesProvider).value, isEmpty);
      expect(recipes.items, isEmpty);
    });
  });
}
