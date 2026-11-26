import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/prep.dart';
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

  testWidgets('plans a snack a day, never prepped, unless switched off', (
    tester,
  ) async {
    final backend = await _ready(tester)
      ..templates = '''
{"format": 1,
 "flavours": [{"id": "plain", "name": "Plain", "cuisine": "british",
   "ingredients": [{"cofid": "12-555", "name": "Yogurt, Greek style, plain",
     "grams": 1, "role": "dairy"}]}],
 "options": {},
 "templates": [{"id": "yogurt-pot", "version": 1, "label": "Yogurt pot",
   "name": "{protein} pot", "meals": ["snack"], "no_cook": true,
   "portions": 1, "fridge_days": 0, "freezable": false,
   "slots": [{"role": "protein", "grams": 150, "min": 100, "max": 250,
     "options": [{"label": "Greek yogurt", "cofid": "12-555",
       "name": "Yogurt, Greek style, plain"}]}]}]}''';
    await backend.pump(tester);
    await _openPlan(tester);
    await tester.tap(find.text('Plan this week'));
    await tester.pumpAndSettle();
    expect(find.text('Greek yogurt pot'), findsNWidgets(7));

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final copy = backend.recipes.items.singleWhere(
      (r) => r.sourceId == 'yogurt-pot',
    );
    expect(copy.cookedWeightG, 150, reason: 'no-cook: weighs what goes in');
    expect(
      backend.prep.sessions.expand((s) => s.portions),
      hasLength(21),
      reason: 'snacks aren’t prepped; the 21 meals are',
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan a snack each day'));
    await tester.pumpAndSettle();
    expect(backend.profiles.profile?.planSnacks, isFalse);

    await _openPlan(tester);
    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(find.text('Greek yogurt pot'), findsNothing);
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

  testWidgets('without a weigh-in, shows the setup checklist, then plans', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile)..templates = '{}';
    backend.goals.goal = Goal.maintenance;
    await backend.pump(tester);
    await _openPlan(tester);
    await tester.tap(find.text('Plan this week'));
    await tester.pumpAndSettle();

    expect(find.text('Set up planning'), findsOneWidget);
    expect(find.text('Needed'), findsOneWidget, reason: 'only the weigh-in');
    final plan = find.widgetWithText(FilledButton, 'Plan this week').last;
    expect(tester.widget<FilledButton>(plan).onPressed, isNull);

    // Doing the step from the checklist updates it in place.
    await tester.tap(find.text('First weigh-in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'kg'), '90');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(backend.weighIns.items, hasLength(1));
    expect(find.text('Needed'), findsNothing);
    expect(tester.widget<FilledButton>(plan).onPressed, isNotNull);

    await tester.tap(plan);
    await tester.pumpAndSettle();
    expect(find.text('Set up planning'), findsNothing);
    expect(find.text('No plan for this week'), findsNothing);
  });

  testWidgets('cooked food stays in its meal; taken out, it becomes a '
      'leftover', (tester) async {
    final backend = await _ready(tester);
    final lentils = await backend.foods.save(
      const FoodDraft(
        name: 'Lentils',
        per100g: Nutrition(kcal: 350, proteinG: 24, carbsG: 50, fatG: 1.5),
        source: FoodSource.manual,
      ),
    );
    backend.recipes.items.add(
      Recipe(
        id: 'r-stew',
        name: 'Lentil stew',
        ingredients: [RecipeIngredient(foodId: lentils.id, rawGrams: 400)],
        // Out of the planner's choices, so only the cooked portion puts it
        // in the plan.
        listed: false,
      ),
    );
    final today = dayOf(DateTime.now());
    final week = weekStartOf(today);
    const targets = PlanTargets(
      kcal: 2400,
      proteinG: 140,
      carbsG: 250,
      fatG: 80,
      fibreG: 30,
    );
    backend.plans.weeks[week] = SavedPlan(
      weekStart: week,
      targets: List.filled(7, targets),
      notes: const [],
      items: [
        SavedPlanItem(
          id: 'i-stew',
          day: today,
          slot: MealSlot.dinner,
          recipeId: 'r-stew',
          amount: 1,
          amountMin: 0.5,
          amountMax: 1.75,
        ),
      ],
    );
    backend.prep.sessions.add(
      PrepSession(
        id: 's-stew',
        planId: 'plan',
        recipeId: 'r-stew',
        cookOn: today,
        portionCount: 1,
        cookedAt: today,
        cookedWeightG: 300,
        portions: [
          PrepPortion(
            id: 'p-stew',
            sessionId: 's-stew',
            day: today,
            slot: MealSlot.dinner,
            amount: 1,
            useBy: addDays(today, 3),
          ),
        ],
      ),
    );
    await backend.pump(tester);
    await _openPlan(tester);
    expect(find.text('Lentil stew'), findsOneWidget);

    // Regenerating keeps it where it was cooked for.
    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(find.text('Lentil stew'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);

    // Taken out and saved: the portion waits in Prep as a leftover.
    // (Later in the week, today's dinner is further down the list.)
    await tester.ensureVisible(find.text('Lentil stew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lentil stew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from the plan'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final portion = backend.prep.sessions
        .firstWhere((s) => s.id == 's-stew')
        .portions
        .single;
    expect(portion.status, PortionStatus.leftover);
    expect(portion.day, isNull);
    expect(portion.slot, isNull);
  });

  testWidgets('a leftover in the freezer goes in the next free meal', (
    tester,
  ) async {
    final backend = await _ready(tester);
    final lentils = await backend.foods.save(
      const FoodDraft(
        name: 'Lentils',
        per100g: Nutrition(kcal: 350, proteinG: 24, carbsG: 50, fatG: 1.5),
        source: FoodSource.manual,
      ),
    );
    backend.recipes.items.add(
      Recipe(
        id: 'r-stew',
        name: 'Lentil stew',
        ingredients: [RecipeIngredient(foodId: lentils.id, rawGrams: 400)],
      ),
    );
    final today = dayOf(DateTime.now());
    backend.prep.sessions.add(
      PrepSession(
        id: 's-old',
        recipeId: 'r-stew',
        cookOn: addDays(today, -5),
        portionCount: 1,
        cookedAt: addDays(today, -5),
        cookedWeightG: 300,
        portions: [
          PrepPortion(
            id: 'p-frozen',
            sessionId: 's-old',
            amount: 1,
            useBy: addDays(today, 60),
            storage: PrepStorage.freezer,
            status: PortionStatus.leftover,
          ),
        ],
      ),
    );
    await backend.pump(tester);
    await _openPlan(tester);
    await tester.tap(find.text('Plan this week'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Leftover · 1 portion'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final portion = backend.prep.sessions
        .firstWhere((s) => s.id == 's-old')
        .portions
        .single;
    expect(portion.status, PortionStatus.planned);
    expect(portion.day, today);
    expect(portion.slot, MealSlot.lunch);
  });
}
