import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/plans/household_plan_notifier.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/prep.dart';

const _n = Nutrition(kcal: 500, proteinG: 40, carbsG: 50, fatG: 15, fibreG: 6);

DishCandidate _dish(String key, Set<MealSlot> meals, {int servings = 4}) =>
    DishCandidate(
      key: key,
      name: key,
      kind: CandidateKind.recipe,
      meals: meals,
      perPortion: _n,
      maxServingsPerBatch: servings,
      keepsDays: 3,
    );

void main() {
  group('sizing shared meals', () {
    const day = PlanTargets(
      kcal: 2000,
      proteinG: 150,
      carbsG: 200,
      fatG: 70,
      fibreG: 30,
    );

    test('a shared dinner is sized to dinner’s share of the day', () {
      final t = targetsForMeals(day, {MealSlot.dinner});
      expect(t.kcal, closeTo(700, 1e-9));
      expect(t.proteinG, closeTo(52.5, 1e-9));
    });

    test('lunch and dinner together take their combined share', () {
      expect(
        targetsForMeals(day, {MealSlot.lunch, MealSlot.dinner}).kcal,
        closeTo(1300, 1e-9),
      );
      expect(targetsForMeals(day, const {}).kcal, 0);
    });

    test('a recipe’s portions last fewer days when everyone eats it', () {
      final d = _dish('stew', {MealSlot.dinner}, servings: 6);
      expect(forEaters(d, 2).maxServingsPerBatch, 3);
      expect(forEaters(d, 4).maxServingsPerBatch, 1);
      expect(forEaters(d, 9).maxServingsPerBatch, 1, reason: 'at least one');
      expect(forEaters(d, 1).maxServingsPerBatch, 6);
    });

    test('the planner gets its amount; everyone else one portion', () {
      const item = PlannedItem(
        day: 2,
        slot: MealSlot.dinner,
        key: 'recipe:stew',
        name: 'Stew',
        amount: 1.35,
        isDish: true,
        perUnit: _n,
        minAmount: 0.5,
        maxAmount: 1.75,
        batch: 0,
      );
      final dishes = servingsFor([item], 'me', ['me', 'bea', 'cat']);
      expect(dishes.single.amounts, {'me': 1.35, 'bea': 1.0, 'cat': 1.0});
      expect(dishes.single.totalPortions, closeTo(3.35, 1e-9));
      expect(dishes.single.batch, 0);
      expect(dishes.single.estimated, {'me', 'bea', 'cat'});
    });
  });

  group('planning the household week again', () {
    const stew = Nutrition(kcal: 500, proteinG: 30, carbsG: 50, fatG: 15);
    const curry = Nutrition(kcal: 400, proteinG: 25, carbsG: 45, fatG: 12);
    SharedDish dish(
      int day,
      String key,
      Nutrition n,
      Map<String, double> amounts, {
      Set<String> estimated = const {},
      MealSlot slot = MealSlot.dinner,
    }) => SharedDish(
      day: day,
      slot: slot,
      key: key,
      name: key,
      perPortion: n,
      amounts: amounts,
      estimated: estimated,
    );

    test('a dish that stays keeps everyone’s amounts and whether they’re '
        'fitted', () {
      final out = carryOver(
        [
          dish(0, 'recipe:stew', stew, {'me': 1.2, 'bea': 1}),
        ],
        [
          dish(
            0,
            'recipe:stew',
            stew,
            {'me': 1.4, 'bea': 0.8},
            estimated: {'me'},
          ),
        ],
      );
      expect(out.single.amounts, {'me': 1.4, 'bea': 0.8});
      expect(out.single.estimated, {'me'});
    });

    test('a new dish starts at the calories the eater had in that meal, '
        'as an estimate', () {
      final out = carryOver(
        [
          dish(0, 'library:curry', curry, {'me': 1.2, 'bea': 1}),
        ],
        [
          dish(0, 'recipe:stew', stew, {'me': 1, 'bea': 0.8}),
        ],
      );
      // Bea had 400 kcal of stew: a portion of curry. Me: 500 → 1.25.
      expect(out.single.amounts, {'me': 1.25, 'bea': 1.0});
      expect(out.single.estimated, {'me', 'bea'});
    });

    test('without that meal before, their average for that kind of meal '
        'that week', () {
      final out = carryOver(
        [
          dish(3, 'library:curry', curry, {'me': 1, 'bea': 1}),
        ],
        [
          dish(0, 'recipe:stew', stew, {'bea': 0.6}),
          dish(1, 'recipe:stew', stew, {'bea': 1}),
        ],
      );
      // (300 + 500) / 2 = 400 kcal: one portion of curry.
      expect(out.single.amounts['bea'], 1);
      expect(out.single.amounts['me'], 1, reason: 'nothing to go on');
    });

    test('estimates stay within the dish’s range', () {
      final out = carryOver(
        [
          dish(0, 'library:curry', curry, {'bea': 1}),
        ],
        [
          dish(0, 'recipe:stew', stew, {'bea': 1.75}),
          dish(0, 'recipe:pie', stew, {'bea': 1.75}),
        ],
      );
      expect(out.single.amounts['bea'], 1.75);
    });

    test('someone who joined since gets the planned amount', () {
      final out = carryOver(
        [
          dish(0, 'recipe:stew', stew, {'me': 1, 'new': 1}),
        ],
        [
          dish(0, 'recipe:stew', stew, {'me': 1.3}),
        ],
      );
      expect(out.single.amounts, {'me': 1.3, 'new': 1});
      expect(out.single.estimated, {'new'});
    });
  });

  test('the planner fills only the meals it is given', () {
    final plan = planWeek(
      PlannerInput(
        targets: const [
          PlanTargets(
            kcal: 700,
            proteinG: 50,
            carbsG: 70,
            fatG: 25,
            fibreG: 10,
          ),
        ],
        dishes: [
          _dish('stew', {MealSlot.lunch, MealSlot.dinner}),
          _dish('curry', {MealSlot.lunch, MealSlot.dinner}),
          _dish('oats', {MealSlot.breakfast}),
        ],
        meals: const [MealSlot.dinner],
        iterations: 300,
      ),
      Random(1),
    );
    expect(plan.items.map((i) => i.slot).toSet(), {MealSlot.dinner});
    expect(plan.items, hasLength(7));
    expect(
      plan.notes.where((n) => n.contains('No dishes suit')),
      isEmpty,
      reason: 'breakfast and lunch weren’t asked for',
    );
  });

  group('household week rows', () {
    test('items read back with their eaters, by day and meal', () {
      final week = householdWeekFromRow({
        'week_start': '2026-12-07',
        'notes': ['a note'],
        'plan_items': [
          {
            'id': 'i2',
            'eater_id': 'b',
            'day': '2026-12-08',
            'slot': 'dinner',
            'recipe_id': 'r1',
            'amount': '1.25',
            'amount_min': 0.5,
            'amount_max': 1.75,
            'batch': 0,
            'estimated': true,
          },
          {
            'id': 'i1',
            'eater_id': 'a',
            'day': '2026-12-07',
            'slot': 'dinner',
            'recipe_id': 'r1',
            'amount': 1,
            'amount_min': 0.5,
            'amount_max': 1.75,
            'batch': 0,
          },
        ],
      });
      expect(week.items.map((i) => i.id), ['i1', 'i2']);
      expect(week.itemsFor('b').single.amount, 1.25);
      expect(week.itemsFor('b').single.estimated, isTrue);
      expect(week.itemsFor('a').single.estimated, isFalse);
      expect(week.notes, ['a note']);
    });

    test('saving sends each serving with its eater, rounded', () {
      final params = saveHouseholdWeekParams(
        HouseholdWeek(
          weekStart: DateTime(2026, 12, 7),
          items: [
            SavedPlanItem(
              day: DateTime(2026, 12, 7),
              slot: MealSlot.dinner,
              recipeId: 'r1',
              eaterId: 'b',
              amount: 1.333,
              amountMin: 0.5,
              amountMax: 1.75,
              batch: 0,
            ),
          ],
        ),
      );
      expect(params['week_start'], '2026-12-07');
      expect(params['items'], [
        {
          'day': '2026-12-07',
          'slot': 'dinner',
          'recipe_id': 'r1',
          'eater_id': 'b',
          'amount': 1.33,
          'amount_min': 0.5,
          'amount_max': 1.75,
          'batch': 0,
        },
      ]);
    });
  });

  test('a household batch’s open portions are each eater’s own', () {
    PrepPortion portion(String id, String? eater) => PrepPortion(
      id: id,
      sessionId: 's',
      amount: 1,
      useBy: DateTime(2026, 12, 10),
      day: DateTime(2026, 12, 7),
      slot: MealSlot.dinner,
      eaterId: eater,
    );
    final session = PrepSession(
      id: 's',
      recipeId: 'r',
      cookOn: DateTime(2026, 12, 7),
      portionCount: 3,
      householdId: 'h',
      portions: [portion('p1', 'a'), portion('p2', 'b'), portion('p3', null)],
    );
    expect(session.isShared, isTrue);
    expect(session.openPortionsFor('a').map((p) => p.id), ['p1', 'p3']);
    expect(session.openPortionsFor('b').map((p) => p.id), ['p2', 'p3']);
    expect(session.openPortions, hasLength(3));
  });
}
