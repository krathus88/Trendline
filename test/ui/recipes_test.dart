import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

void main() {
  const riceDraft = FoodDraft(
    name: 'Basmati rice',
    per100g: Nutrition(kcal: 350, proteinG: 8, carbsG: 76, fatG: 0.5),
    source: FoodSource.manual,
  );
  const chickenDraft = FoodDraft(
    name: 'Chicken breast',
    per100g: Nutrition(kcal: 110, proteinG: 24, carbsG: 0, fatG: 1.5),
    source: FoodSource.manual,
  );

  Future<void> addIngredient(
    WidgetTester tester,
    String name,
    String grams,
  ) async {
    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, grams);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add to recipe'));
    await tester.pumpAndSettle();
  }

  testWidgets('creates a recipe from saved foods', (tester) async {
    final backend = TestBackend(profile: testProfile);
    await backend.foods.save(riceDraft);
    await backend.foods.save(chickenDraft);
    await backend.pump(tester);

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    expect(find.text('No recipes yet'), findsOneWidget);

    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Chicken rice',
    );
    await addIngredient(tester, 'Basmati rice', '300');
    await addIngredient(tester, 'Chicken breast', '600');

    // (1,050 + 660) / 4 portions.
    expect(find.text('428 kcal per portion'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Cooked weight'),
      '1400',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('A portion is 350 g cooked'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save recipe'));
    await tester.pumpAndSettle();

    final saved = backend.recipes.items.single;
    expect(saved.name, 'Chicken rice');
    expect(saved.ingredients.map((i) => i.rawGrams), [300, 600]);
    expect(saved.cookedWeightG, 1400);
    expect(find.text('Chicken rice'), findsOneWidget, reason: 'in the list');
  });

  testWidgets('warns about an unlikely cooked weight', (tester) async {
    final backend = TestBackend(profile: testProfile);
    await backend.foods.save(riceDraft);
    await backend.pump(tester);

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();
    await addIngredient(tester, 'Basmati rice', '300');
    await tester.enterText(
      find.widgetWithText(TextField, 'Cooked weight'),
      '5000',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Did you include the pot?'), findsOneWidget);
  });

  testWidgets('needs a name and ingredients to save', (tester) async {
    final backend = TestBackend(profile: testProfile);
    await backend.pump(tester);
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Give the recipe a name.'), findsOneWidget);
    expect(backend.recipes.saves, 0);
  });

  group('logging', () {
    Future<TestBackend> withRecipe(
      WidgetTester tester, {
      double? cookedWeightG,
    }) async {
      final backend = TestBackend(profile: testProfile);
      final rice = await backend.foods.save(riceDraft);
      final chicken = await backend.foods.save(chickenDraft);
      await backend.recipes.save(
        Recipe(
          id: '',
          name: 'Chicken rice',
          cookedWeightG: cookedWeightG,
          ingredients: [
            RecipeIngredient(foodId: rice.id, rawGrams: 300),
            RecipeIngredient(foodId: chicken.id, rawGrams: 600),
          ],
        ),
      );
      await backend.pump(tester);
      await tester.tap(find.text('Add food').first);
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('logs a portion by cooked weight', (tester) async {
      final backend = await withRecipe(tester, cookedWeightG: 1400);
      expect(find.text('Your recipes'), findsOneWidget);

      await tester.tap(find.text('Chicken rice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 portion (350 g)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to breakfast'));
      await tester.pumpAndSettle();

      final entry = backend.foodLogs.items.single;
      expect(entry.recipeId, backend.recipes.items.single.id);
      expect(entry.foodId, isNull);
      expect(entry.grams, 350);
      expect(entry.nutrition.kcal, closeTo(427.5, 0.1));
      expect(entry.eatenOn, dayOf(DateTime.now()));
    });

    testWidgets('an unweighed recipe asks for its cooked weight', (
      tester,
    ) async {
      final backend = await withRecipe(tester);
      await tester.tap(find.text('Chicken rice'));
      await tester.pump();
      expect(
        find.textContaining('Weigh Chicken rice after cooking'),
        findsOneWidget,
      );
      expect(backend.foodLogs.items, isEmpty);
    });
  });

  testWidgets('a food used in a recipe cannot be removed', (tester) async {
    final backend = TestBackend(profile: testProfile);
    final rice = await backend.foods.save(riceDraft);
    backend.foods.inUse.add(rice.id);
    await backend.pump(tester);

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basmati rice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from my foods'));
    await tester.pumpAndSettle();

    expect(find.textContaining('This food is in a recipe'), findsOneWidget);
    expect(backend.foods.items, hasLength(1));
  });

  group('Favourites', () {
    Future<TestBackend> withTwoRecipes(WidgetTester tester) async {
      final backend = TestBackend(profile: testProfile);
      final rice = await backend.foods.save(riceDraft);
      for (final (id, name) in [('r-a', 'Apple rice'), ('r-b', 'Bean rice')]) {
        backend.recipes.items.add(
          Recipe(
            id: id,
            name: name,
            ingredients: [RecipeIngredient(foodId: rice.id, rawGrams: 300)],
          ),
        );
      }
      await backend.pump(tester);
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recipes'));
      await tester.pumpAndSettle();
      return backend;
    }

    Finder starOf(String name) => find.descendant(
      of: find.widgetWithText(ListTile, name),
      matching: find.byType(IconButton),
    );

    testWidgets('a starred recipe is saved and moves to the top', (
      tester,
    ) async {
      final backend = await withTwoRecipes(tester);
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('Apple rice'), lessThan(y('Bean rice')));

      await tester.tap(starOf('Bean rice'));
      await tester.pumpAndSettle();
      expect(backend.favourites.ids, {'r-b'});
      expect(y('Bean rice'), lessThan(y('Apple rice')));
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);

      await tester.tap(starOf('Bean rice'));
      await tester.pumpAndSettle();
      expect(backend.favourites.ids, isEmpty);
      expect(y('Apple rice'), lessThan(y('Bean rice')));
    });

    testWidgets('a star that can’t be saved is taken back', (tester) async {
      final backend = await withTwoRecipes(tester);
      backend.favourites.fail = true;
      await tester.tap(starOf('Bean rice'));
      await tester.pumpAndSettle();
      expect(backend.favourites.ids, isEmpty);
      expect(find.byTooltip('Remove from favourites'), findsNothing);
      expect(find.byTooltip('Add to favourites'), findsNWidgets(2));
    });
  });
}
