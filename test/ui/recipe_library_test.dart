import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

const _library = '''
{"format": 1, "recipes": [{
  "id": "overnight-oats", "version": 2, "name": "Overnight oats",
  "meals": ["breakfast"], "cuisine": "british", "portions": 2,
  "fridge_days": 3, "freezable": false,
  "ingredients": [
    {"cofid": "11-788", "name": "Porridge oats, unfortified", "grams": 100,
     "role": "carb"},
    {"cofid": "12-555", "name": "Yogurt, Greek style, plain", "grams": 200,
     "role": "protein"}
  ]
}]}
''';

const _oats = FoodDraft(
  name: 'Porridge oats, unfortified',
  per100g: Nutrition(kcal: 381, proteinG: 10.9, carbsG: 64.2, fatG: 8.1),
  source: FoodSource.cofid,
  referenceCode: '11-788',
);
const _yogurt = FoodDraft(
  name: 'Greek style yogurt, plain',
  per100g: Nutrition(kcal: 133, proteinG: 5.7, carbsG: 4.6, fatG: 10.2),
  source: FoodSource.cofid,
  referenceCode: '12-555',
);

TestBackend _backend({bool withYogurt = true}) {
  final backend = TestBackend(profile: testProfile)..library = _library;
  backend.referenceFoods.byKey[(
        code: '11-788',
        name: 'Porridge oats, unfortified',
      )] =
      _oats;
  if (withYogurt) {
    backend.referenceFoods.byKey[(
          code: '12-555',
          name: 'Yogurt, Greek style, plain',
        )] =
        _yogurt;
  }
  return backend;
}

Future<void> _openRecipes(WidgetTester tester) async {
  await tester.tap(find.text('Food'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Recipes'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists library recipes with their energy per portion', (
    tester,
  ) async {
    await _backend().pump(tester);
    await _openRecipes(tester);

    expect(find.text('From the library'), findsOneWidget);
    expect(find.text('Overnight oats'), findsOneWidget);
    expect(find.text('British · breakfast · 2 portions'), findsOneWidget);
    // (381 + 266) / 2 portions.
    expect(find.text('324 kcal\nper portion'), findsOneWidget);
  });

  testWidgets('adds a library recipe to my recipes, reusing saved foods', (
    tester,
  ) async {
    final backend = _backend();
    final savedOats = await backend.foods.save(_oats);
    await backend.pump(tester);
    await _openRecipes(tester);

    await tester.tap(find.text('Overnight oats'));
    await tester.pumpAndSettle();
    expect(find.text('Greek style yogurt, plain'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add to my recipes'));
    await tester.pumpAndSettle();

    final copy = backend.recipes.items.single;
    expect(copy.origin, RecipeOrigin.library);
    expect(copy.sourceId, 'overnight-oats');
    expect(copy.sourceVersion, 2);
    expect(copy.portions, 2);
    expect(copy.freezable, isFalse);
    expect(copy.ingredients.map((i) => i.rawGrams), [100, 200]);
    expect(
      copy.ingredients.first.foodId,
      savedOats.id,
      reason: 'the already-saved basic food is reused',
    );
    expect(backend.foods.items, hasLength(2), reason: 'yogurt was copied');
    expect(find.textContaining('added'), findsWidgets);

    // Opening it again offers the copy instead of adding another.
    await tester.tap(find.text('Overnight oats').last);
    await tester.pumpAndSettle();
    expect(find.text('In your recipes: open it'), findsOneWidget);
  });

  testWidgets('a basic food the database lacks stops the copy', (tester) async {
    final backend = _backend(withYogurt: false);
    await backend.pump(tester);
    await _openRecipes(tester);

    expect(
      find.text('324 kcal\nper portion'),
      findsNothing,
      reason: 'no total while a food is missing',
    );
    await tester.tap(find.text('Overnight oats'));
    await tester.pumpAndSettle();
    final add = find.widgetWithText(FilledButton, 'Add to my recipes');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    expect(backend.recipes.items, isEmpty);
  });
}
