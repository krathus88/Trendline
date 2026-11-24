import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

/// One dish shape with one choice per slot, so the dish is predictable.
const _templates = '''
{"format": 1,
 "flavours": [{"id": "plain", "name": "Peppery", "cuisine": "british",
   "ingredients": [{"cofid": "13-880", "name": "Pepper, black", "grams": 1,
                    "role": "flavour"}]}],
 "options": {},
 "templates": [{"id": "bowl", "version": 3, "name": "{flavour} {protein} bowl",
   "meals": ["lunch"], "portions": 2, "fridge_days": 3, "freezable": false,
   "flavours": ["plain"],
   "slots": [
     {"role": "protein", "grams": 100, "min": 50, "max": 200, "options": [
       {"label": "chicken", "cofid": "18-290", "name": "Chicken, light meat, raw",
        "cooked": {"cofid": "18-323",
                   "name": "Chicken, breast, grilled without skin, meat only"}}]},
     {"role": "carb", "grams": 50, "min": 20, "max": 100, "options": [
       {"label": "rice", "cofid": "11-857", "name": "Rice, white, basmati, raw",
        "cooked": {"cofid": "11-858",
                   "name": "Rice, white, basmati, boiled in unsalted water"}}]}
   ]}]}
''';

const FoodKey _chicken = (code: '18-290', name: 'Chicken, light meat, raw');

FoodDraft _draft(String code, String name, double kcal, double protein) =>
    FoodDraft(
      name: name,
      per100g: Nutrition(kcal: kcal, proteinG: protein, carbsG: 0, fatG: 0),
      source: FoodSource.cofid,
      referenceCode: code,
      referenceName: name,
    );

TestBackend _backend() {
  final backend = TestBackend(profile: testProfile)..templates = _templates;
  for (final d in [
    _draft('18-290', 'Chicken, light meat, raw', 106, 24),
    _draft(
      '18-323',
      'Chicken, breast, grilled without skin, meat only',
      148,
      32,
    ),
    _draft('11-857', 'Rice, white, basmati, raw', 351, 8),
    _draft('11-858', 'Rice, white, basmati, boiled in unsalted water', 117, 3),
    _draft('13-880', 'Pepper, black', 251, 10),
  ]) {
    backend.referenceFoods.byKey[(
          code: d.referenceCode!,
          name: d.referenceName!,
        )] =
        d;
  }
  return backend;
}

Future<void> _openMakeDish(WidgetTester tester) async {
  await tester.tap(find.text('Food'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Recipes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Make a dish'));
  await tester.pumpAndSettle();
}

void main() {
  group('Make a dish', () {
    testWidgets('makes a dish with totals and an expected cooked weight', (
      tester,
    ) async {
      final backend = _backend();
      await backend.pump(tester);
      await _openMakeDish(tester);

      expect(find.text('Peppery chicken bowl'), findsOneWidget);
      // (100 x 1.06 + 50 x 3.51 + 1 x 2.51) a portion.
      expect(find.text('284 kcal per portion · 2 portions'), findsOneWidget);
      // 2 x (100 x 106/148 + 50 x 351/117 + 1) = 445 g, to the nearest 10.
      expect(find.textContaining('Expect about 450 g cooked'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Add to my recipes'));
      await tester.pumpAndSettle();

      final copy = backend.recipes.items.single;
      expect(copy.name, 'Peppery chicken bowl');
      expect(copy.origin, RecipeOrigin.template);
      expect(copy.sourceId, 'bowl');
      expect(copy.sourceVersion, 3);
      expect(copy.estimatedCookedWeightG, 450);
      expect(copy.cookedWeightG, isNull, reason: 'logging waits for weighing');
      expect(copy.ingredients.map((i) => i.rawGrams), [200, 100, 2]);
    });

    testWidgets('says why when preferences rule everything out', (
      tester,
    ) async {
      final backend = _backend();
      backend.preferences.ingredients[_chicken] = Preference.never;
      await backend.pump(tester);
      await _openMakeDish(tester);

      expect(find.textContaining('No protein is left'), findsOneWidget);
      expect(find.text('Add to my recipes'), findsNothing);
    });
  });

  group('Food preferences', () {
    Future<void> openPreferences(WidgetTester tester) async {
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food preferences'));
      await tester.pumpAndSettle();
    }

    testWidgets('sets a cuisine preference', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.pump(tester);
      await openPreferences(tester);

      await tester.tap(find.text('No preference').at(1)); // Indian
      await tester.pumpAndSettle();
      await tester.tap(find.text('Never').last);
      await tester.pumpAndSettle();

      expect(backend.preferences.cuisines, {Cuisine.indian: Preference.never});
    });

    testWidgets('adds a food the user never wants', (tester) async {
      final backend = TestBackend(profile: testProfile);
      backend.referenceFoods.items.add(
        _draft('13-888', 'Coriander leaves, fresh', 18, 2),
      );
      await backend.pump(tester);
      await openPreferences(tester);

      await tester.tap(find.text('Add a food'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'coriander');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coriander leaves, fresh'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Never'));
      await tester.pumpAndSettle();

      expect(backend.preferences.ingredients, {
        (code: '13-888', name: 'Coriander leaves, fresh'): Preference.never,
      });
      expect(find.text('Coriander leaves, fresh'), findsOneWidget);
    });
  });
}
