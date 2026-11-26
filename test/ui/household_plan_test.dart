import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/data/plans/planner_catalogue.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

/// Alex (the user) and Bea share a household with one shared recipe.
Future<TestBackend> _household() async {
  final backend = TestBackend(profile: testProfile)
    // Only the household's recipe: no library or template dishes.
    ..library = '{"format": 1, "recipes": []}'
    ..templates = '{}';
  backend.goals.goal = Goal.maintenance;
  await backend.weighIns.add(
    measuredAt: DateTime.now().subtract(const Duration(hours: 1)),
    weightKg: 90,
  );
  await backend.households.create(name: 'Flat 2', displayName: 'Alex');
  final h = backend.households.household!;
  backend.households.household = Household(
    id: h.id,
    name: h.name,
    members: [
      ...h.members,
      HouseholdMember(
        userId: 'bea',
        displayName: 'Bea',
        isOwner: false,
        joinedAt: DateTime(2026, 2),
      ),
    ],
  );
  backend.foods.shared.add(
    const Food(
      id: 'hf-lentils',
      name: 'Lentils',
      per100g: Nutrition(kcal: 350, proteinG: 24, carbsG: 50, fatG: 1.5),
      source: FoodSource.manual,
    ),
  );
  backend.recipes.items.add(
    Recipe(
      id: 'hr-dal',
      name: 'Dal',
      householdId: h.id,
      portions: 8,
      ingredients: const [
        RecipeIngredient(foodId: 'hf-lentils', rawGrams: 800),
      ],
    ),
  );
  return backend;
}

/// One library dish, Indian, that could go in a shared dinner.
const _indianLibrary = '''
{"format": 1, "recipes": [
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

void _addLibraryFoods(TestBackend backend) {
  for (final (code, name, n) in [
    (
      '18-290',
      'Chicken, light meat, raw',
      const Nutrition(kcal: 106, proteinG: 24, carbsG: 0, fatG: 1.5),
    ),
    (
      '11-857',
      'Rice, white, basmati, raw',
      const Nutrition(kcal: 351, proteinG: 8, carbsG: 76, fatG: 0.5),
    ),
  ]) {
    backend.referenceFoods.byKey[(code: code, name: name)] = FoodDraft(
      name: name,
      per100g: n,
      source: FoodSource.cofid,
      referenceCode: code,
      referenceName: name,
    );
  }
}

Future<void> _planAndSaveHousehold(WidgetTester tester) async {
  await tester.tap(find.text('Plan'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Household meals'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Plan shared meals'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('plans shared dinners for everyone, then fits the user’s '
      'own servings', (tester) async {
    final backend = await _household();
    await backend.pump(tester);
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Household meals'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nobody’s targets are shared'), findsOneWidget);

    await tester.tap(find.text('Plan shared meals'));
    await tester.pumpAndSettle();
    expect(find.text('Dal'), findsNWidgets(7));
    expect(find.textContaining('Bea ~1'), findsNWidgets(7));

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    final weekStart = weekStartOf(DateTime.now());
    final week = backend.plans.householdWeeks[weekStart]!;
    expect(week.items, hasLength(14), reason: 'a serving each, 7 dinners');
    expect(week.itemsFor('bea').every((i) => i.amount == 1), isTrue);
    expect(week.items.map((i) => i.slot).toSet(), {MealSlot.dinner});

    // Joint prep: batches for both, each with a portion per serving.
    final sessions = backend.prep.sessions;
    expect(sessions, isNotEmpty);
    expect(sessions.every((s) => s.isShared), isTrue);
    expect(sessions.expand((s) => s.portions), hasLength(14));
    expect(sessions.expand((s) => s.portions).map((p) => p.eaterId).toSet(), {
      'user-1',
      'bea',
    });

    // The user's own week shows their servings, marked as shared.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Dal'), findsNWidgets(7));
    expect(find.byTooltip('Shared with your household'), findsNWidgets(7));

    // Planning their own week fits their servings to their day; Bea's
    // stay as they are.
    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final after = backend.plans.householdWeeks[weekStart]!;
    expect(
      after.itemsFor('user-1').every((i) => i.amount > 1),
      isTrue,
      reason: 'a whole day to fill with nothing else planned',
    );
    expect(after.itemsFor('bea').every((i) => i.amount == 1), isTrue);
    expect(
      after.itemsFor('user-1').any((i) => i.estimated),
      isFalse,
      reason: 'saving the user’s week fits their servings',
    );
    expect(after.itemsFor('bea').every((i) => i.estimated), isTrue);
    expect(
      backend.plans.weeks[weekStart]!.items.where((i) => i.recipeId != null),
      isEmpty,
      reason: 'the shared dinners aren’t copied into the user’s own plan',
    );

    // A shared dish can't be swapped from the user's own week.
    await tester.tap(find.text('Dal').first);
    await tester.pumpAndSettle();
    expect(find.text('Swap for another dish'), findsNothing);
    expect(find.textContaining('Change the dish in Household'), findsOneWidget);
  });

  testWidgets('Prep shows the household batch with whose portions are whose', (
    tester,
  ) async {
    final backend = await _household();
    await backend.pump(tester);
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Household meals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan shared meals'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Prep'));
    await tester.pumpAndSettle();
    expect(find.textContaining('· household'), findsWidgets);

    await tester.tap(find.text('Dal').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('You · Dinner'), findsWidgets);
    expect(find.textContaining('Bea · Dinner'), findsWidgets);
  });

  testWidgets('planning the household week again keeps what Bea fitted', (
    tester,
  ) async {
    final backend = await _household();
    await backend.pump(tester);
    await _planAndSaveHousehold(tester);
    final weekStart = weekStartOf(DateTime.now());

    // Bea fits her servings on her phone.
    await backend.plans.updateAmounts({
      for (final i in backend.plans.householdWeeks[weekStart]!.itemsFor('bea'))
        i.id!: 1.4,
    });

    await tester.tap(find.text('Plan again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bea 1.4'), findsNWidgets(7));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final bea = backend.plans.householdWeeks[weekStart]!.itemsFor('bea');
    expect(bea, hasLength(7));
    expect(bea.every((i) => i.amount == 1.4 && !i.estimated), isTrue);
  });

  testWidgets('the user fits their estimated servings without re-planning '
      'their week', (tester) async {
    final backend = await _household();
    await backend.pump(tester);
    await _planAndSaveHousehold(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.textContaining('estimates until'), findsOneWidget);
    await tester.tap(find.text('Fit my portions'));
    await tester.pumpAndSettle();

    expect(find.textContaining('estimates until'), findsNothing);
    final week = backend.plans.householdWeeks[weekStartOf(DateTime.now())]!;
    final mine = week.itemsFor('user-1');
    expect(mine.every((i) => !i.estimated), isTrue);
    expect(
      mine.every((i) => i.amount > 0.5 && i.amount <= 1.75),
      isTrue,
      reason: 'sized to dinner’s share of the day, within range',
    );
    expect(week.itemsFor('bea').every((i) => i.estimated), isTrue);
    expect(backend.plans.weeks, isEmpty, reason: 'no plan of their own');
  });

  testWidgets('a dish someone in the household never wants isn’t planned', (
    tester,
  ) async {
    final backend = await _household();
    backend.library = _indianLibrary;
    _addLibraryFoods(backend);
    await backend.pump(tester);
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Household meals'));
    await tester.pumpAndSettle();

    // Without anyone minding, the library dish is a candidate.
    final seen = <String>{};
    for (var i = 0; i < 4; i++) {
      await tester.tap(
        find.textContaining(RegExp('Plan (shared meals|again)')),
      );
      await tester.pumpAndSettle();
      if (find.text('Chicken and rice').evaluate().isNotEmpty) {
        seen.add('chicken');
      }
    }
    expect(seen, {'chicken'});

    // Bea never wants Indian food: the household's combined preferences.
    backend.households.foodPreferences = FoodPreferences.combined(const [
      HouseholdPreference(target: Cuisine.indian, nevers: 1, members: 2),
    ]);
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .invalidate(householdFoodPreferencesProvider);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Plan again'));
      await tester.pumpAndSettle();
      expect(find.text('Chicken and rice'), findsNothing);
    }
  });

  testWidgets('last week’s dishes and the household’s stars count for its '
      'plan', (tester) async {
    final backend = await _household();
    final weekStart = weekStartOf(DateTime.now());
    final lastWeek = addDays(weekStart, -7);
    backend.plans.householdWeeks[lastWeek] = HouseholdWeek(
      weekStart: lastWeek,
      items: [
        SavedPlanItem(
          day: lastWeek,
          slot: MealSlot.dinner,
          recipeId: 'hr-dal',
          eaterId: 'user-1',
          amount: 1,
        ),
      ],
    );
    // Bea starred it; Alex didn't.
    backend.households.recipeFavourites = {'hr-dal': 0.5};
    await backend.pump(tester);
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Household meals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan shared meals'));
    await tester.pumpAndSettle();

    final input = backend.lastPlannerInput!;
    expect(input.recent, containsAll(['recipe:hr-dal', 'Dal']));
    final dal = input.dishes.singleWhere((d) => d.key == 'recipe:hr-dal');
    expect(dal.favourite, isTrue);
    expect(dal.preference, closeTo(1 + (favouriteWeight - 1) / 2, 1e-9));
  });
}
