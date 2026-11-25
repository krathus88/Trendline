import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

Future<void> _openHousehold(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Household'));
  await tester.pumpAndSettle();
}

Future<void> _fillNames(WidgetTester tester, String first, String me) async {
  await tester.enterText(find.byType(TextField).first, first);
  await tester.enterText(find.widgetWithText(TextField, 'Your name'), me);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creates a household, makes an invite code and leaves', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    await backend.pump(tester);
    await _openHousehold(tester);

    expect(find.text('You’re not in a household'), findsOneWidget);
    expect(find.textContaining('never shared'), findsOneWidget);

    await tester.tap(find.text('Create a household'));
    await tester.pumpAndSettle();
    await _fillNames(tester, 'Flat 2', 'Alex');
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Flat 2'), findsOneWidget);
    expect(find.text('Alex (you)'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);

    await tester.tap(find.text('New invite code'));
    await tester.pumpAndSettle();
    final code = backend.households.household!.invites.single.code;
    expect(
      find.text('${code.substring(0, 5)}-${code.substring(5)}'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Withdraw code'));
    await tester.pumpAndSettle();
    expect(backend.households.household!.invites, isEmpty);

    await tester.tap(find.text('Leave household'));
    await tester.pumpAndSettle();
    expect(find.textContaining('last member'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(backend.households.household, isNull);
    expect(find.text('You’re not in a household'), findsOneWidget);
  });

  testWidgets('joining: a bad code says so, a good one joins', (tester) async {
    final backend = TestBackend(profile: testProfile);
    backend.households.validCodes.add('ABCDE23456');
    await backend.pump(tester);
    await _openHousehold(tester);

    await tester.tap(find.text('Join with a code'));
    await tester.pumpAndSettle();
    await _fillNames(tester, 'ZZZZZ-ZZZZZ', 'Bea');
    await tester.tap(find.widgetWithText(TextButton, 'Join'));
    await tester.pumpAndSettle();
    expect(find.textContaining('That code doesn’t work'), findsOneWidget);

    await tester.tap(find.text('Join with a code'));
    await tester.pumpAndSettle();
    await _fillNames(tester, 'abcde 23456', 'Bea');
    await tester.tap(find.widgetWithText(TextButton, 'Join'));
    await tester.pumpAndSettle();

    expect(find.text('Joined home'), findsOneWidget);
    expect(find.text('Bea (you)'), findsOneWidget);
    expect(find.text('New invite code'), findsNothing, reason: 'not the owner');
  });

  testWidgets('shares a recipe and lists it under the household', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    final rice = await backend.foods.save(
      const FoodDraft(
        name: 'Basmati rice',
        per100g: Nutrition(kcal: 350, proteinG: 8, carbsG: 76, fatG: 0.5),
        source: FoodSource.manual,
      ),
    );
    await backend.recipes.save(
      Recipe(
        id: '',
        name: 'Rice pot',
        ingredients: [RecipeIngredient(foodId: rice.id, rawGrams: 400)],
      ),
    );
    await backend.households.create(name: 'Flat 2', displayName: 'Alex');
    await backend.pump(tester);

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recipes'));
    await tester.pumpAndSettle();
    expect(find.text('Shared with Flat 2'), findsOneWidget);
    expect(find.text('Nothing shared yet'), findsOneWidget);

    await tester.tap(find.text('Rice pot'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Share with household'));
    await tester.pumpAndSettle();
    expect(find.text('Shared with your household'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Rice pot'), findsNWidgets(2), reason: 'own and shared');
    expect(find.text('Nothing shared yet'), findsNothing);
    final shared = backend.recipes.items.where((r) => r.isShared).single;
    expect(shared.householdId, backend.households.household!.id);

    // Opening the shared one offers a copy back instead of sharing.
    await tester.tap(find.text('Rice pot').last);
    await tester.pumpAndSettle();
    expect(find.text('Shared recipe'), findsOneWidget);
    expect(find.byTooltip('Share with household'), findsNothing);
    expect(find.byTooltip('Copy to my recipes'), findsOneWidget);
  });

  testWidgets('the owner renames the household; each changes their own name', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    await backend.households.create(name: 'Flat 2', displayName: 'Alex');
    await backend.pump(tester);
    await _openHousehold(tester);

    await tester.tap(find.byTooltip('Rename household'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Household name'),
      '',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a household name.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Household name'),
      ' The Flat ',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(backend.households.household!.name, 'The Flat');
    expect(find.text('The Flat'), findsOneWidget);

    await tester.tap(find.byTooltip('Change your name'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'The name the others see'),
      'Al',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Al (you)'), findsOneWidget);
    expect(backend.households.household!.members.single.displayName, 'Al');
  });

  testWidgets('Today’s picker logs a portion of a shared recipe', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    await backend.households.create(name: 'Flat 2', displayName: 'Alex');
    final h = backend.households.household!;
    backend.foods.shared.add(
      const Food(
        id: 'hf-lentils',
        name: 'Lentils',
        per100g: Nutrition(kcal: 350, proteinG: 24, carbsG: 50, fatG: 1.5),
        source: FoodSource.manual,
      ),
    );
    backend.recipes.items.addAll([
      Recipe(
        id: 'hr-dal',
        name: 'Dal',
        householdId: h.id,
        cookedWeightG: 1600,
        ingredients: const [
          RecipeIngredient(foodId: 'hf-lentils', rawGrams: 400),
        ],
      ),
      Recipe(
        id: 'hr-hidden',
        name: 'Hidden stew',
        householdId: h.id,
        listed: false,
        ingredients: const [
          RecipeIngredient(foodId: 'hf-lentils', rawGrams: 400),
        ],
      ),
    ]);
    await backend.pump(tester);

    await tester.tap(find.text('Add food').first);
    await tester.pumpAndSettle();
    expect(find.text('Shared with Flat 2'), findsOneWidget);
    expect(find.text('Hidden stew'), findsNothing);
    await tester.tap(find.text('Dal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 portion (400 g)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add to breakfast'));
    await tester.pumpAndSettle();

    final entry = backend.foodLogs.items.single;
    expect(entry.recipeId, 'hr-dal');
    expect(entry.grams, 400, reason: 'one portion of the cooked batch');
  });
}
