import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/prep.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

/// A stew (4 portions from 800 g chicken) with one batch of 2 portions:
/// dinner on [firstDay] and the day after.
Future<TestBackend> _ready({
  required DateTime firstDay,
  bool cooked = false,
}) async {
  final backend = TestBackend(profile: testProfile);
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
      ingredients: [RecipeIngredient(foodId: chicken.id, rawGrams: 800)],
      estimatedCookedWeightG: 1200,
    ),
  );
  backend.prep.sessions.add(
    PrepSession(
      id: 's-1',
      recipeId: 'r-stew',
      cookOn: firstDay,
      portionCount: 2,
      cookedAt: cooked ? DateTime.now() : null,
      cookedWeightG: cooked ? 800 : null,
      portions: [
        for (var d = 0; d < 2; d++)
          PrepPortion(
            id: 'p-$d',
            sessionId: 's-1',
            day: addDays(firstDay, d),
            slot: MealSlot.dinner,
            amount: 1,
            useBy: addDays(firstDay, 3),
          ),
      ],
    ),
  );
  return backend;
}

Future<void> _openPrep(WidgetTester tester, TestBackend backend) async {
  await backend.pump(tester);
  await tester.tap(find.text('Plan'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Prep'));
  await tester.pumpAndSettle();
}

void main() {
  final today = dayOf(DateTime.now());

  testWidgets('with nothing planned, says where prep comes from', (
    tester,
  ) async {
    await _openPrep(tester, TestBackend(profile: testProfile));
    expect(find.text('Nothing to prep'), findsOneWidget);
  });

  testWidgets('shows what to cook, then marks it cooked by weight', (
    tester,
  ) async {
    final backend = await _ready(firstDay: today);
    await _openPrep(tester, backend);
    expect(find.text('To cook'), findsOneWidget);
    expect(find.textContaining('2 portions for 2 meals'), findsOneWidget);

    await tester.tap(find.text('Stew'));
    await tester.pumpAndSettle();
    // Half the recipe: 400 g of chicken, expected to cook to about 600 g.
    expect(find.text('400 g'), findsOneWidget);
    expect(find.textContaining('Expect about 600 g'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    expect(find.textContaining('under a third'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '640');
    await tester.pump();
    await tester.tap(find.text('Mark cooked'));
    await tester.pumpAndSettle();

    expect(backend.prep.sessions.single.cookedWeightG, 640);
    // The recipe learns the weight, scaled to its own 4-portion batch.
    expect(backend.recipes.items.single.cookedWeightG, 1280);
    // Each of the two portions is half the batch.
    expect(find.text('320 g'), findsNWidgets(2));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('To cook'), findsNothing);
    expect(find.text('Cooked portions'), findsOneWidget);
  });

  testWidgets('eating a portion logs its share of the batch', (tester) async {
    final backend = await _ready(firstDay: today, cooked: true);
    await _openPrep(tester, backend);
    expect(find.textContaining('400 g'), findsNWidgets(2));

    await tester.tap(find.text('Stew').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eaten today'));
    await tester.pumpAndSettle();

    final log = backend.foodLogs.items.single;
    expect(log.recipeId, 'r-stew');
    expect(log.slot, MealSlot.dinner);
    expect(log.grams, 400);
    // 400 g of 800 g cooked from 400 g raw chicken: 200 g of chicken.
    expect(log.nutrition.kcal, closeTo(200, 0.01));
    final eaten = backend.prep.sessions.single.portions.first;
    expect(eaten.status, PortionStatus.eaten);
    expect(eaten.foodLogId, log.id);
    expect(find.text('Stew'), findsOneWidget, reason: 'one portion left');
  });

  testWidgets('a failed update takes the logged meal back out', (tester) async {
    final backend = await _ready(firstDay: today, cooked: true);
    backend.prep.failPortionUpdates = true;
    await _openPrep(tester, backend);
    await tester.tap(find.text('Stew').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eaten today'));
    await tester.pumpAndSettle();
    expect(backend.foodLogs.items, isEmpty);
    expect(find.text('Stew'), findsNWidgets(2));
  });

  testWidgets('a missed portion can go in the freezer', (tester) async {
    final backend = await _ready(firstDay: addDays(today, -1), cooked: true);
    await _openPrep(tester, backend);
    expect(find.textContaining('Missed'), findsOneWidget);

    await tester.tap(find.text('Stew').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to the freezer'));
    await tester.pumpAndSettle();

    final frozen = backend.prep.sessions.single.portions.first;
    expect(frozen.storage, PrepStorage.freezer);
    expect(frozen.status, PortionStatus.leftover);
    expect(frozen.day, isNull);
    expect(frozen.useBy, freezerUseBy(today));
    expect(find.textContaining('In the freezer'), findsOneWidget);
    expect(find.textContaining('Missed'), findsNothing);
  });

  testWidgets('a portion past its use-by date can only be thrown away', (
    tester,
  ) async {
    final backend = await _ready(firstDay: addDays(today, -5), cooked: true);
    await _openPrep(tester, backend);
    expect(find.text('Past its use-by date'), findsNWidgets(2));

    await tester.tap(find.text('Stew').first);
    await tester.pumpAndSettle();
    expect(find.text('Eaten today'), findsNothing);
    expect(find.text('Move to the freezer'), findsNothing);
    await tester.tap(find.text('Thrown away'));
    await tester.pumpAndSettle();
    expect(
      backend.prep.sessions.single.portions.first.status,
      PortionStatus.discarded,
    );
    expect(find.text('Stew'), findsOneWidget);
  });

  testWidgets('a library copy saved without a method shows the library’s', (
    tester,
  ) async {
    final backend = await _ready(firstDay: today)
      ..library = File('assets/recipe_library.json').readAsStringSync();
    final stew = backend.recipes.items.single;
    backend.recipes.items
      ..clear()
      ..add(
        Recipe(
          id: stew.id,
          name: stew.name,
          ingredients: stew.ingredients,
          estimatedCookedWeightG: stew.estimatedCookedWeightG,
          origin: RecipeOrigin.library,
          sourceId: 'red-lentil-soup',
          sourceVersion: 1,
        ),
      );
    await _openPrep(tester, backend);
    await tester.tap(find.text('Stew'));
    await tester.pumpAndSettle();
    expect(find.text('Method'), findsOneWidget);
    expect(find.textContaining('rinse the lentils'), findsOneWidget);
  });

  testWidgets('a recipe without a method shows no Method heading', (
    tester,
  ) async {
    final backend = await _ready(firstDay: today);
    await _openPrep(tester, backend);
    await tester.tap(find.text('Stew'));
    await tester.pumpAndSettle();
    expect(find.text('Method'), findsNothing);
  });
}
