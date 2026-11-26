import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/prep.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

final DateTime _today = dayOf(DateTime.now());
final DateTime _week = weekStartOf(_today);

/// Today's saved plan: 80 g oats at breakfast (40–120 g), a fixed 150 g
/// yogurt snack, and a portion of stew at dinner (0.5–1.75 portions).
Future<TestBackend> _ready({bool stewCooked = false}) async {
  final backend = TestBackend(profile: testProfile);
  backend.goals.goal = Goal.maintenance;
  await backend.weighIns.add(
    measuredAt: DateTime.now().subtract(const Duration(hours: 1)),
    weightKg: 90,
  );
  final oats = await backend.foods.save(
    const FoodDraft(
      name: 'Oats',
      per100g: Nutrition(kcal: 380, proteinG: 11, carbsG: 60, fatG: 8),
      source: FoodSource.manual,
    ),
  );
  final yogurt = await backend.foods.save(
    const FoodDraft(
      name: 'Yogurt',
      per100g: Nutrition(kcal: 60, proteinG: 10, carbsG: 4, fatG: 0),
      source: FoodSource.manual,
    ),
  );
  final chicken = await backend.foods.save(
    const FoodDraft(
      name: 'Chicken',
      per100g: Nutrition(kcal: 100, proteinG: 24, carbsG: 0, fatG: 1),
      source: FoodSource.manual,
    ),
  );
  backend.recipes.items.add(
    Recipe(
      id: 'r-stew',
      name: 'Stew',
      ingredients: [RecipeIngredient(foodId: chicken.id, rawGrams: 2000)],
      cookedWeightG: 1600,
    ),
  );
  backend.plans.weeks[_week] = SavedPlan(
    weekStart: _week,
    targets: List.filled(
      7,
      const PlanTargets(
        kcal: 2000,
        proteinG: 140,
        carbsG: 200,
        fatG: 65,
        fibreG: 30,
      ),
    ),
    notes: const [],
    items: [
      SavedPlanItem(
        id: 'i-oats',
        day: _today,
        slot: MealSlot.breakfast,
        foodId: oats.id,
        amount: 80,
        amountMin: 40,
        amountMax: 120,
      ),
      SavedPlanItem(
        id: 'i-yog',
        day: _today,
        slot: MealSlot.snack,
        foodId: yogurt.id,
        amount: 150,
      ),
      SavedPlanItem(
        id: 'i-stew',
        day: _today,
        slot: MealSlot.dinner,
        recipeId: 'r-stew',
        amount: 1,
        amountMin: 0.5,
        amountMax: 1.75,
        batch: 0,
      ),
    ],
  );
  if (stewCooked) {
    backend.prep.sessions.add(
      PrepSession(
        id: 's-1',
        recipeId: 'r-stew',
        cookOn: _today,
        portionCount: 2,
        cookedAt: DateTime.now(),
        cookedWeightG: 1000,
        portions: [
          for (var d = 0; d < 2; d++)
            PrepPortion(
              id: 'p-$d',
              sessionId: 's-1',
              day: addDays(_today, d),
              slot: MealSlot.dinner,
              amount: 1,
              useBy: addDays(_today, 3),
            ),
        ],
      ),
    );
  }
  return backend;
}

/// The "eaten as planned" button on [name]'s planned row.
Finder _eat(String name) => find.descendant(
  of: find.widgetWithText(ListTile, name),
  matching: find.byTooltip('Eaten as planned'),
);

double _amount(TestBackend backend, String id) =>
    backend.plans.weeks[_week]!.items.firstWhere((i) => i.id == id).amount;

Future<void> _bigLunch(TestBackend backend, double kcal) async {
  await backend.foodLogs.add(
    day: _today,
    slot: MealSlot.lunch,
    food: Food(
      id: 'f-feast',
      name: 'Feast',
      per100g: Nutrition(kcal: kcal / 10, proteinG: 0, carbsG: 0, fatG: 0),
      source: FoodSource.manual,
    ),
    grams: 1000,
  );
}

void main() {
  testWidgets('shows the meals still to eat, and logs one as planned', (
    tester,
  ) async {
    final backend = await _ready();
    await backend.pump(tester);
    expect(find.textContaining('Planned ·'), findsNWidgets(3));
    expect(find.text('Planned · 80 g · 304 kcal'), findsOneWidget);

    await tester.tap(_eat('Oats'));
    await tester.pumpAndSettle();

    final log = backend.foodLogs.items.single;
    expect(log.foodName, 'Oats');
    expect(log.grams, 80);
    expect(find.textContaining('Planned ·'), findsNWidgets(2));
  });

  testWidgets('a dish not prepped is logged from its weighed recipe', (
    tester,
  ) async {
    final backend = await _ready();
    await backend.pump(tester);
    await tester.tap(_eat('Stew'));
    await tester.pumpAndSettle();
    final log = backend.foodLogs.items.single;
    expect(log.recipeId, 'r-stew');
    // One portion of a 1,600 g batch of four.
    expect(log.grams, 400);
    expect(log.nutrition.kcal, closeTo(500, 0.5));
  });

  testWidgets('a cooked dish is logged from its batch', (tester) async {
    final backend = await _ready(stewCooked: true);
    await backend.pump(tester);
    await tester.tap(_eat('Stew'));
    await tester.pumpAndSettle();
    // Half of a 1,000 g batch of two portions.
    expect(backend.foodLogs.items.single.grams, 500);
    expect(
      backend.prep.sessions.single.portions.first.status,
      PortionStatus.eaten,
    );
  });

  testWidgets('re-planning after a huge lunch shrinks what’s left', (
    tester,
  ) async {
    final backend = await _ready();
    await _bigLunch(backend, 6000);
    await backend.pump(tester);

    await tester.tap(find.text('Re-plan the rest of the day'));
    await tester.pumpAndSettle();

    expect(_amount(backend, 'i-oats'), 40);
    expect(_amount(backend, 'i-stew'), 0.5);
    expect(_amount(backend, 'i-yog'), 150, reason: 'fixed');
    expect(find.text('Planned · 40 g · 152 kcal'), findsOneWidget);
    expect(find.textContaining('kcal over'), findsOneWidget);
  });

  testWidgets('a cooked, boxed portion stays as it is', (tester) async {
    final backend = await _ready(stewCooked: true);
    await _bigLunch(backend, 6000);
    await backend.pump(tester);
    await tester.tap(find.text('Re-plan the rest of the day'));
    await tester.pumpAndSettle();
    expect(_amount(backend, 'i-stew'), 1);
    expect(_amount(backend, 'i-oats'), 40);
  });

  testWidgets('a light day so far grows the rest', (tester) async {
    final backend = await _ready();
    await backend.pump(tester);
    await tester.tap(find.text('Re-plan the rest of the day'));
    await tester.pumpAndSettle();
    expect(_amount(backend, 'i-oats'), greaterThan(80));
    expect(_amount(backend, 'i-stew'), greaterThan(1));
  });

  testWidgets('a failed save leaves the plan as it was', (tester) async {
    final backend = await _ready();
    backend.plans.failUpdates = true;
    await _bigLunch(backend, 6000);
    await backend.pump(tester);
    await tester.tap(find.text('Re-plan the rest of the day'));
    await tester.pumpAndSettle();
    expect(_amount(backend, 'i-oats'), 80);
    expect(find.text('Planned · 80 g · 304 kcal'), findsOneWidget);
  });

  /// The skip button on [name]'s planned row.
  Finder skipButton(String name) => find.descendant(
    of: find.widgetWithText(ListTile, name),
    matching: find.byTooltip('Skip (not having it)'),
  );

  testWidgets('skipping a meal takes it out, then re-planning makes up for '
      'it', (tester) async {
    final backend = await _ready();
    await backend.pump(tester);
    await tester.tap(skipButton('Oats'));
    await tester.pumpAndSettle();

    expect(
      backend.plans.weeks[_week]!.items.map((i) => i.id),
      unorderedEquals(['i-yog', 'i-stew']),
    );
    expect(find.textContaining('Planned ·'), findsNWidgets(2));
    expect(find.textContaining('Skipped Oats'), findsOneWidget);

    await tester.tap(find.text('Re-plan the rest of the day'));
    await tester.pumpAndSettle();
    expect(_amount(backend, 'i-stew'), greaterThan(1));
  });

  testWidgets('a skipped cooked portion waits in Prep as a leftover', (
    tester,
  ) async {
    final backend = await _ready(stewCooked: true);
    await backend.pump(tester);
    await tester.tap(skipButton('Stew'));
    await tester.pumpAndSettle();
    final portion = backend.prep.sessions.single.portions.first;
    expect(portion.status, PortionStatus.leftover);
    expect(portion.day, isNull);
    expect(find.textContaining('Planned ·'), findsNWidgets(2));
  });

  testWidgets('a failed skip keeps the meal', (tester) async {
    final backend = await _ready();
    backend.plans.failUpdates = true;
    await backend.pump(tester);
    await tester.tap(skipButton('Oats'));
    await tester.pumpAndSettle();
    expect(backend.plans.weeks[_week]!.items, hasLength(3));
    expect(find.textContaining('Planned ·'), findsNWidgets(3));
  });
}
