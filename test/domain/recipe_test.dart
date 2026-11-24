import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

void main() {
  const rice = Food(
    id: 'rice',
    name: 'Basmati rice, raw',
    per100g: Nutrition(
      kcal: 350,
      proteinG: 8,
      carbsG: 76,
      fatG: 0.5,
      fibreG: 1,
    ),
    source: FoodSource.cofid,
    referenceCode: '11-857',
  );
  const chicken = Food(
    id: 'chicken',
    name: 'Chicken breast, raw',
    per100g: Nutrition(kcal: 110, proteinG: 24, carbsG: 0, fatG: 1.5),
    source: FoodSource.cofid,
    referenceCode: '18-001',
  );
  const curryPaste = Food(
    id: 'paste',
    name: 'Curry paste',
    per100g: Nutrition(
      kcal: 200,
      proteinG: 3,
      carbsG: 10,
      fatG: 15,
      fibreUnknown: true,
    ),
    source: FoodSource.manual,
  );
  final foods = {
    for (final f in [rice, chicken, curryPaste]) f.id: f,
  };

  Recipe recipe({
    List<RecipeIngredient> ingredients = const [
      RecipeIngredient(foodId: 'rice', rawGrams: 300),
      RecipeIngredient(foodId: 'chicken', rawGrams: 600),
    ],
    int portions = 4,
    double? cookedWeightG,
    String name = 'Chicken rice',
    int fridgeDays = 3,
  }) => Recipe(
    id: 'r1',
    name: name,
    ingredients: ingredients,
    portions: portions,
    cookedWeightG: cookedWeightG,
    fridgeDays: fridgeDays,
  );

  group('recipeNutrition', () {
    test('adds up the batch from raw grams', () {
      final n = recipeNutrition(recipe(), foods);
      expect(n.batch.kcal, 1050 + 660);
      expect(n.batch.proteinG, 24 + 144);
      expect(n.complete, isTrue);
    });

    test('splits the batch into portions', () {
      final n = recipeNutrition(recipe(), foods);
      expect(n.perPortion.kcal, closeTo(427.5, 1e-9));
      expect(n.perPortion.proteinG, closeTo(42, 1e-9));
    });

    test('per 100 g cooked needs the cooked weight', () {
      expect(recipeNutrition(recipe(), foods).per100gCooked, isNull);

      // Rice gains water, chicken loses some: 900 g raw -> 1,425 g cooked.
      final n = recipeNutrition(recipe(cookedWeightG: 1425), foods);
      expect(n.per100gCooked!.kcal, closeTo(1710 * 100 / 1425, 1e-9));
      // A 356 g portion is a quarter of the batch.
      expect(
        n.per100gCooked!.forGrams(1425 / 4).kcal,
        closeTo(n.perPortion.kcal, 0.1),
      );
    });

    test('a missing food makes the totals incomplete', () {
      final n = recipeNutrition(
        recipe(
          ingredients: const [
            RecipeIngredient(foodId: 'rice', rawGrams: 100),
            RecipeIngredient(foodId: 'gone', rawGrams: 100),
          ],
        ),
        foods,
      );
      expect(n.complete, isFalse);
      expect(n.missingFoods, 1);
      expect(n.batch.kcal, 350);
    });

    test(
      'unknown fibre in one ingredient makes the recipe’s fibre unknown',
      () {
        final n = recipeNutrition(
          recipe(
            ingredients: const [
              RecipeIngredient(foodId: 'rice', rawGrams: 300),
              RecipeIngredient(foodId: 'paste', rawGrams: 50),
            ],
          ),
          foods,
        );
        expect(n.batch.fibreG, 3);
        expect(n.batch.fibreUnknown, isTrue);
        expect(n.perPortion.fibreUnknown, isTrue);
      },
    );

    test('a single portion is the whole batch', () {
      final n = recipeNutrition(recipe(portions: 1), foods);
      expect(n.perPortion, n.batch);
    });
  });

  group('validateRecipe', () {
    test('accepts a normal recipe', () {
      expect(validateRecipe(recipe()), isNull);
      expect(validateRecipe(recipe(cookedWeightG: 1425)), isNull);
    });

    test('needs a name and an ingredient', () {
      expect(validateRecipe(recipe(name: '  ')), isNotNull);
      expect(validateRecipe(recipe(ingredients: const [])), isNotNull);
    });

    test('refuses impossible amounts', () {
      for (final grams in [0.0, -5.0, 5000.0, double.nan]) {
        expect(
          validateRecipe(
            recipe(
              ingredients: [RecipeIngredient(foodId: 'rice', rawGrams: grams)],
            ),
          ),
          isNotNull,
          reason: '$grams g',
        );
      }
    });

    test('refuses portions, cooked weights and fridge days out of range', () {
      expect(validateRecipe(recipe(portions: 0)), isNotNull);
      expect(validateRecipe(recipe(portions: 51)), isNotNull);
      expect(validateRecipe(recipe(cookedWeightG: 0)), isNotNull);
      expect(validateRecipe(recipe(cookedWeightG: 50001)), isNotNull);
      expect(validateRecipe(recipe(fridgeDays: 8)), isNotNull);
      expect(validateRecipe(recipe(fridgeDays: -1)), isNotNull);
    });
  });

  group('cookedWeightWarning', () {
    test('is quiet for normal cooking', () {
      expect(cookedWeightWarning(recipe()), isNull, reason: 'not weighed');
      expect(cookedWeightWarning(recipe(cookedWeightG: 1425)), isNull);
      expect(cookedWeightWarning(recipe(cookedWeightG: 700)), isNull);
    });

    test('warns about likely weighing mistakes', () {
      expect(cookedWeightWarning(recipe(cookedWeightG: 200)), isNotNull);
      expect(cookedWeightWarning(recipe(cookedWeightG: 4000)), isNotNull);
    });
  });

  test('a portion’s cooked weight', () {
    expect(recipe().portionG, isNull);
    expect(recipe(cookedWeightG: 1400).portionG, 350);
  });
}
