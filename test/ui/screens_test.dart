import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/platform/health_source.dart';
import 'package:trendline/ui/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

void main() {
  group('Onboarding', () {
    testWidgets('needs the disclaimer and saves the profile', (tester) async {
      final backend = TestBackend();
      await backend.pump(tester);

      await tester.tap(find.text('Male'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Birth year'),
        '1990',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Height'),
        '180',
      );
      await tester.tap(find.text('st & lb'));
      await tester.pumpAndSettle();

      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      await tester.ensureVisible(continueButton);
      expect(
        tester.widget<FilledButton>(continueButton).onPressed,
        isNull,
        reason: 'disabled until the disclaimer is accepted',
      );

      await tester.tap(find.text('I do strength training'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(backend.profiles.saves, 1);
      expect(backend.profiles.profile!.weightUnit, WeightUnit.stLb);
      expect(backend.profiles.profile!.strengthTraining, isTrue);

      // Then the health check, before anything else.
      expect(find.text('Do any of these apply to you?'), findsOneWidget);
      await tester.tap(find.text('None of these apply'));
      await tester.pumpAndSettle();
      expect(backend.profiles.profile!.healthScreenedAt, isNotNull);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('stops if a screened condition applies, saving nothing', (
      tester,
    ) async {
      final backend = TestBackend(
        profile: Profile(
          sex: Sex.female,
          birthYear: 1990,
          heightCm: 165,
          activityLevel: ActivityLevel.light,
          weightUnit: WeightUnit.kg,
          disclaimerAcceptedAt: DateTime(2026),
        ),
      );
      await backend.pump(tester);
      expect(find.text('Kidney disease'), findsOneWidget);

      await tester.tap(find.text('One or more apply'));
      await tester.pumpAndSettle();
      expect(find.textContaining("isn't suitable"), findsOneWidget);
      expect(backend.profiles.saves, 0);
      expect(backend.profiles.profile!.healthScreenedAt, isNull);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('Your goal'), findsNothing);
    });

    testWidgets('rejects under-18s', (tester) async {
      await TestBackend().pump(tester);
      final year = DateTime.now().year - 10;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Birth year'),
        '$year',
      );
      await tester.tap(find.text('Male'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Height'),
        '150',
      );
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a year (18+ only)'), findsOneWidget);
    });
  });

  group('Today', () {
    testWidgets('logs a saved food and totals the day', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.foods.save(
        const FoodDraft(
          name: 'Oats',
          per100g: Nutrition(kcal: 379, proteinG: 13, carbsG: 60, fatG: 7),
          source: FoodSource.manual,
        ),
      );
      await backend.pump(tester);

      expect(find.text('Breakfast'), findsOneWidget);
      await tester.tap(find.text('Add food').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oats'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '50');
      await tester.pumpAndSettle();
      expect(find.text('190 kcal'), findsOneWidget, reason: 'live preview');
      await tester.tap(find.widgetWithText(FilledButton, 'Add to breakfast'));
      await tester.pumpAndSettle();

      expect(backend.foodLogs.items.single.grams, 50);
      expect(backend.foodLogs.items.single.eatenOn, dayOf(DateTime.now()));
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('190'), findsWidgets);
    });

    testWidgets('edits and removes a logged portion', (tester) async {
      final backend = TestBackend(profile: testProfile);
      final oats = await backend.foods.save(
        const FoodDraft(
          name: 'Oats',
          per100g: Nutrition(kcal: 379, proteinG: 13, carbsG: 60, fatG: 7),
          source: FoodSource.manual,
        ),
      );
      await backend.foodLogs.add(
        day: dayOf(DateTime.now()),
        slot: MealSlot.breakfast,
        food: oats,
        grams: 50,
      );
      await backend.pump(tester);

      await tester.tap(find.text('Oats'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '100');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(backend.foodLogs.items.single.nutrition.kcal, 379);

      await tester.tap(find.text('Oats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from log'));
      await tester.pumpAndSettle();
      expect(backend.foodLogs.items, isEmpty);
      expect(find.text('Oats'), findsNothing);
    });

    testWidgets('can go back a day but not into the future', (tester) async {
      await TestBackend(profile: testProfile).pump(tester);

      final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
      expect(tester.widget<IconButton>(next).onPressed, isNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsOneWidget);
      expect(tester.widget<IconButton>(next).onPressed, isNotNull);
    });
  });

  group('Food', () {
    testWidgets('searches Open Food Facts on submit and logs a result', (
      tester,
    ) async {
      final backend = TestBackend(profile: testProfile);
      var searches = 0;
      backend.off = (request) async {
        searches++;
        return http.Response(
          jsonEncode({
            'hits': [
              {
                'code': '01219494',
                'product_name': 'Semi skimmed milk',
                'brands': ["Sainsbury's"],
                'nutriments': {
                  'energy-kcal_100g': 50,
                  'proteins_100g': 3.6,
                  'carbohydrates_100g': 4.8,
                  'fat_100g': 1.8,
                },
              },
            ],
          }),
          200,
        );
      };
      await backend.pump(tester);

      await tester.tap(find.text('Add food').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'milk');
      await tester.pump();
      expect(searches, 0, reason: 'no search-as-you-type');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(searches, 1);

      await tester.tap(find.text('Semi skimmed milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to breakfast'));
      await tester.pumpAndSettle();

      expect(backend.foods.items.single.barcode, '01219494');
      expect(backend.foodLogs.items.single.foodName, 'Semi skimmed milk');
    });

    testWidgets('an unknown barcode opens manual entry with it filled in', (
      tester,
    ) async {
      final backend = TestBackend(profile: testProfile);
      backend.scanner.result = '5000000000000';
      await backend.pump(tester);

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan barcode'));
      await tester.pumpAndSettle();

      expect(find.textContaining('5000000000000'), findsOneWidget);
      expect(find.text('Save food'), findsOneWidget);
    });

    testWidgets('manual entry refuses impossible nutrition', (tester) async {
      await TestBackend(profile: testProfile).pump(tester);
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter from label'));
      await tester.pumpAndSettle();

      Future<void> fill(String label, String value) =>
          tester.enterText(find.widgetWithText(TextFormField, label), value);
      await fill('Name', 'Mystery bar');
      await fill('Energy', '400');
      await fill('Protein', '60');
      await fill('Carbs', '60');
      await fill('Fat', '10');
      final save = find.text('Save food');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.textContaining('add up to more than 100 g'), findsOneWidget);
    });
  });

  group('Progress', () {
    testWidgets('adds a weigh-in in stones and pounds', (tester) async {
      final backend = TestBackend(
        profile: testProfile.copyWith(weightUnit: WeightUnit.stLb),
      );
      await backend.pump(tester);
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      expect(find.text('No weigh-ins yet'), findsOneWidget);

      await tester.tap(find.text('Weigh-in'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'st').first,
        '12',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'lb'), '7');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        backend.weighIns.items.single.weightKg,
        closeTo(stLbToKg(12, 7), 1e-9),
      );
      expect(find.text('12 st 7.0 lb'), findsWidgets);
    });

    testWidgets('shows the trend chart after two days', (tester) async {
      final backend = TestBackend(profile: testProfile);
      final today = DateTime.now();
      for (var d = 0; d < 10; d++) {
        await backend.weighIns.add(
          measuredAt: addDays(today, -d),
          weightKg: 90 - d * 0.1,
        );
      }
      await backend.pump(tester);
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text('Not enough data yet'), findsNothing);
      expect(find.text('Trend weight'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  group('Settings', () {
    testWidgets('credits Open Food Facts', (tester) async {
      await TestBackend(profile: testProfile).pump(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Open Database License (ODbL)'),
        findsOneWidget,
      );
    });
  });
  group('Health Connect', () {
    testWidgets('connects from Settings and shows the imported reading', (
      tester,
    ) async {
      final backend = TestBackend(profile: testProfile);
      backend.health.readings = BodyReadings(
        weightKg: [
          HealthReading(
            id: 'hc-1',
            at: DateTime.now().subtract(const Duration(hours: 1)),
            value: 90,
          ),
        ],
      );
      await backend.pump(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Import weigh-ins from your scale'), findsOneWidget);
      await tester.tap(find.text('Health Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(backend.weighIns.items.single.externalId, 'hc-1');
      expect(find.text('Added 1 weigh-in from Health Connect'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sync now'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Health Connect'), findsWidgets);

      await tester.tap(find.byTooltip('Delete weigh-in'));
      await tester.pumpAndSettle();
      expect(backend.weighIns.dismissed, {'hc-1'});
      expect(find.textContaining("won't be imported"), findsOneWidget);
    });

    testWidgets('is hidden where Health Connect is unavailable', (
      tester,
    ) async {
      final backend = TestBackend(profile: testProfile);
      backend.health.status = HealthAvailability.unavailable;
      await backend.pump(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Health Connect'), findsNothing);
    });
  });
  group('Goals and targets', () {
    Future<TestBackend> withWeighIn(WidgetTester tester, {Goal? goal}) async {
      final backend = TestBackend(profile: testProfile);
      backend.goals.goal = goal;
      await backend.weighIns.add(
        measuredAt: DateTime.now().subtract(const Duration(hours: 1)),
        weightKg: 90,
      );
      await backend.pump(tester);
      return backend;
    }

    testWidgets('asks for a goal, and says when a pace is capped', (
      tester,
    ) async {
      final backend = await withWeighIn(tester);
      expect(find.text('Your goal'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Target weight'),
        '80',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Pace'), '2');
      await tester.pumpAndSettle();
      expect(find.textContaining('capped at'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(backend.goals.saves, 1);
      expect(backend.goals.goal!.targetWeightKg, 80);
      expect(find.byType(HomeShell), findsOneWidget);
    });

    testWidgets('gaining: needs a higher target, and caps at 0.5%', (
      tester,
    ) async {
      final backend = await withWeighIn(tester);
      await tester.tap(find.text('Gain'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Target weight'),
        '85',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Pace'), '1');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('aim above your trend weight'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Target weight'),
        '95',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('over 0.5% of your weight'), findsOneWidget);
      expect(find.textContaining('Gaining 0.45 kg/week'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(backend.goals.goal!.direction, GoalDirection.gain);
    });

    testWidgets('maintain needs no values', (tester) async {
      final backend = await withWeighIn(tester);
      await tester.tap(find.text('Maintain'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(backend.goals.goal!.kind, GoalKind.maintain);
    });

    testWidgets('a percent pace above 1% cannot be saved', (tester) async {
      await withWeighIn(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Target weight'),
        '80',
      );
      await tester.tap(find.text('% a week'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Pace'), '1.5');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull,
      );
      expect(find.text('Enter a pace up to 1% a week.'), findsOneWidget);
    });

    testWidgets('Today shows what is left and marks the day complete', (
      tester,
    ) async {
      final backend = await withWeighIn(tester, goal: Goal.maintenance);
      expect(find.text('Left today'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);

      await tester.tap(find.text('Everything eaten is logged'));
      await tester.pumpAndSettle();
      expect(backend.energy.completeDays, {dayOf(DateTime.now())});
    });

    testWidgets('Progress explains the estimate and the goal', (tester) async {
      await withWeighIn(
        tester,
        goal: const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 85,
          paceValue: 0.5,
        ),
      );
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      expect(find.text('Daily burn estimate'), findsOneWidget);
      expect(find.textContaining('From a formula for now.'), findsOneWidget);
      expect(find.textContaining('Losing 0.5 kg/week'), findsOneWidget);
    });
  });
}
