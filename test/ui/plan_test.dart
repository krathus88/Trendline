import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

/// Two library dishes: one for breakfast, one for lunch and dinner.
const _library = '''
{"format": 1, "recipes": [
  {"id": "oats", "version": 1, "name": "Overnight oats",
   "meals": ["breakfast"], "cuisine": "british", "portions": 2,
   "fridge_days": 2, "freezable": false,
   "ingredients": [
     {"cofid": "11-788", "name": "Porridge oats, unfortified", "grams": 160,
      "role": "carb"},
     {"cofid": "12-555", "name": "Yogurt, Greek style, plain", "grams": 300,
      "role": "protein"}]},
  {"id": "chicken-rice", "version": 1, "name": "Chicken and rice",
   "meals": ["lunch", "dinner"], "cuisine": "indian", "portions": 4,
   "fridge_days": 3, "freezable": true,
   "ingredients": [
     {"cofid": "18-290", "name": "Chicken, light meat, raw", "grams": 600,
      "role": "protein"},
     {"cofid": "11-857", "name": "Rice, white, basmati, raw", "grams": 300,
      "role": "carb"}]}
]}
''';

FoodDraft _draft(String code, String name, Nutrition n) => FoodDraft(
  name: name,
  per100g: n,
  source: FoodSource.cofid,
  referenceCode: code,
  referenceName: name,
);

Future<TestBackend> _ready(WidgetTester tester) async {
  final backend = TestBackend(profile: testProfile)
    ..library = _library
    // The planner copes without templates.
    ..templates = '{}';
  backend.goals.goal = Goal.maintenance;
  await backend.weighIns.add(
    measuredAt: DateTime.now().subtract(const Duration(hours: 1)),
    weightKg: 90,
  );
  for (final d in [
    _draft(
      '11-788',
      'Porridge oats, unfortified',
      const Nutrition(kcal: 381, proteinG: 10.9, carbsG: 64, fatG: 8),
    ),
    _draft(
      '12-555',
      'Yogurt, Greek style, plain',
      const Nutrition(kcal: 133, proteinG: 5.7, carbsG: 4.6, fatG: 10.2),
    ),
    _draft(
      '18-290',
      'Chicken, light meat, raw',
      const Nutrition(kcal: 106, proteinG: 24, carbsG: 0, fatG: 1.5),
    ),
    _draft(
      '11-857',
      'Rice, white, basmati, raw',
      const Nutrition(kcal: 351, proteinG: 8, carbsG: 76, fatG: 0.5),
    ),
  ]) {
    backend.referenceFoods.byKey[(
          code: d.referenceCode!,
          name: d.referenceName!,
        )] =
        d;
  }
  return backend;
}

Future<void> _openPlan(WidgetTester tester) async {
  await tester.tap(find.text('Plan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('makes a week, then saves it with the dishes copied in', (
    tester,
  ) async {
    final backend = await _ready(tester);
    await backend.pump(tester);
    await _openPlan(tester);
    expect(find.text('No plan for this week'), findsOneWidget);

    await tester.tap(find.text('Plan this week'));
    await tester.pumpAndSettle();

    expect(find.text('Overnight oats'), findsNWidgets(7));
    expect(find.text('Chicken and rice'), findsNWidgets(14));
    expect(find.textContaining('Not saved yet'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final week = weekStartOf(DateTime.now());
    final saved = backend.plans.weeks[week]!;
    expect(saved.items.where((i) => i.recipeId != null), hasLength(21));
    // Each library dish was copied once, into the user's recipes.
    expect(backend.recipes.items.map((r) => r.sourceId).toSet(), {
      'oats',
      'chicken-rice',
    });
    expect(
      backend.recipes.items.every((r) => r.origin == RecipeOrigin.library),
      isTrue,
    );
    expect(find.text('Saved'), findsOneWidget);

    // Saving lays out the batches to cook.
    expect(backend.prep.sessions, isNotEmpty);
    expect(
      backend.prep.sessions.expand((s) => s.portions),
      hasLength(21),
      reason: 'one portion per planned dish',
    );
    await tester.tap(find.byTooltip('Prep'));
    await tester.pumpAndSettle();
    expect(find.text('To cook'), findsOneWidget);
  });

  testWidgets('a locked item stays when regenerating', (tester) async {
    final backend = await _ready(tester);
    await backend.pump(tester);
    await _openPlan(tester);
    await tester.tap(find.text('Plan this week'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overnight oats').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock (keep when regenerating)'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsOneWidget);

    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('meal rules go in every day', (tester) async {
    final backend = await _ready(tester);
    final coffee = await backend.foods.save(
      const FoodDraft(
        name: 'Cappuccino',
        per100g: Nutrition(kcal: 40, proteinG: 2, carbsG: 4, fatG: 1.5),
        source: FoodSource.manual,
      ),
    );
    await backend.rules.save(
      MealRule(
        id: '',
        foodId: coffee.id,
        slot: MealSlot.breakfast,
        frequency: RuleFrequency.daily,
        amountMin: 250,
        amountMax: 250,
      ),
    );
    await backend.pump(tester);
    await _openPlan(tester);
    await tester.tap(find.text('Plan this week'));
    await tester.pumpAndSettle();

    expect(find.text('Cappuccino'), findsNWidgets(7));
    expect(find.text('250 g · 100 kcal'), findsNWidgets(7));
  });

  testWidgets('without targets, says what to set up first', (tester) async {
    final backend = TestBackend(profile: testProfile)..templates = '{}';
    await backend.pump(tester);
    await _openPlan(tester);
    await tester.tap(find.text('Plan this week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('the plan is sized'), findsOneWidget);
  });
}
