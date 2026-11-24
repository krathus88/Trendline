import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/schedule.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

Future<void> _open(WidgetTester tester, String setting) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(setting));
  await tester.pumpAndSettle();
}

void main() {
  group('Day schedule', () {
    testWidgets('shows each day with its meal times', (tester) async {
      final backend = TestBackend(profile: testProfile);
      backend.schedules.saved[6] = const DaySchedule(
        weekday: 6,
        wakeMinute: 15 * 60,
        sleepMinute: 7 * 60,
      );
      await backend.pump(tester);
      await _open(tester, 'Day schedule');

      expect(find.textContaining('07:00–23:00'), findsNWidgets(6));
      expect(
        find.text(
          'Breakfast 07:30 · Lunch 13:45 · Snacks 17:00 · Dinner 20:00',
        ),
        findsNWidgets(6),
      );
      expect(find.textContaining('Saturday   15:00–07:00'), findsOneWidget);
    });

    testWidgets('changes the weekend wake-up time', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.pump(tester);
      await _open(tester, 'Day schedule');

      await tester.tap(find.textContaining('Saturday'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wake up'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '9');
      await tester.enterText(find.byType(TextField).at(1), '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekend'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(backend.schedules.saved.keys, unorderedEquals([6, 7]));
      expect(backend.schedules.saved[7]!.wakeMinute, 9 * 60 + 30);
      expect(backend.schedules.saved[7]!.sleepMinute, 23 * 60);
      expect(find.textContaining('09:30–23:00'), findsNWidgets(2));
    });
  });

  group('Meal rules', () {
    testWidgets('adds a daily cappuccino at breakfast', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.foods.save(
        const FoodDraft(
          name: 'Cappuccino',
          per100g: Nutrition(kcal: 40, proteinG: 2, carbsG: 4, fatG: 1.5),
          source: FoodSource.manual,
        ),
      );
      await backend.pump(tester);
      await _open(tester, 'Meal rules');
      expect(find.text('No rules yet'), findsOneWidget);

      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cappuccino'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Breakfast'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '250');
      await tester.tap(find.widgetWithText(FilledButton, 'Save rule'));
      await tester.pumpAndSettle();

      final rule = backend.rules.items.single;
      expect(rule.frequency, RuleFrequency.daily);
      expect(rule.slot, MealSlot.breakfast);
      expect(rule.amountMin, 250);
      expect(rule.amountMax, 250);
      expect(rule.foodId, backend.foods.items.single.id);
      expect(find.text('Every day · breakfast · 250 g'), findsOneWidget);
    });

    testWidgets('refuses an impossible count', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.foods.save(
        const FoodDraft(
          name: 'Salmon',
          per100g: Nutrition(kcal: 217, proteinG: 20, carbsG: 0, fatG: 15),
          source: FoodSource.manual,
        ),
      );
      await backend.pump(tester);
      await _open(tester, 'Meal rules');
      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salmon'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'At least'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Times'), '8');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dinner'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save rule'));
      await tester.pumpAndSettle();

      expect(
        find.text('Times a week must be between 1 and 7.'),
        findsOneWidget,
      );
      expect(backend.rules.items, isEmpty);
    });

    testWidgets('says when rules cannot all be kept', (tester) async {
      final backend = TestBackend(profile: testProfile);
      final salmon = await backend.foods.save(
        const FoodDraft(
          name: 'Salmon',
          per100g: Nutrition(kcal: 217, proteinG: 20, carbsG: 0, fatG: 15),
          source: FoodSource.manual,
        ),
      );
      for (final (f, n) in [
        (RuleFrequency.minPerWeek, 3),
        (RuleFrequency.maxPerWeek, 2),
      ]) {
        await backend.rules.save(
          MealRule(
            id: '',
            foodId: salmon.id,
            frequency: f,
            timesPerWeek: n,
            amountMin: 120,
            amountMax: 180,
          ),
        );
      }
      await backend.pump(tester);
      await _open(tester, 'Meal rules');

      expect(
        find.text(
          'Can’t all be kept: Salmon: at least 3 but at most 2 times a week.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('At least 3 a week · any meal · 120–180 g'),
        findsOneWidget,
      );
    });
  });
}
