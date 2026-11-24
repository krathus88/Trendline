import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/replan.dart';

/// 500 kcal a portion, 0.5–1.75 portions.
PlannedItem _dish(
  String key,
  MealSlot slot, {
  double amount = 1,
  bool locked = false,
}) => PlannedItem(
  day: 0,
  slot: slot,
  key: key,
  name: key,
  amount: amount,
  isDish: true,
  perUnit: const Nutrition(kcal: 500, proteinG: 30, carbsG: 50, fatG: 15),
  minAmount: 0.5,
  maxAmount: 1.75,
  locked: locked,
);

/// A fixed 100 kcal snack (250 g).
const _coffee = PlannedItem(
  day: 0,
  slot: MealSlot.snack,
  key: 'food:coffee',
  name: 'Cappuccino',
  amount: 250,
  isDish: false,
  perUnit: Nutrition(kcal: 0.4, proteinG: 0.02, carbsG: 0.04, fatG: 0.015),
);

FoodLogEntry _log(MealSlot slot, double kcal, {String? foodId, String? r}) =>
    FoodLogEntry(
      id: 'l',
      eatenOn: DateTime(2026, 12, 7),
      eatenAt: DateTime(2026, 12, 7, 12),
      slot: slot,
      foodId: foodId,
      recipeId: r,
      foodName: 'x',
      grams: 100,
      nutrition: Nutrition(kcal: kcal, proteinG: 0, carbsG: 0, fatG: 0),
    );

void main() {
  test('each logged entry uses up one planned item in its meal', () {
    final planned = [
      _dish('recipe:oats', MealSlot.breakfast),
      _dish('recipe:stew', MealSlot.lunch),
      _dish('recipe:stew', MealSlot.dinner),
      _coffee,
    ];
    final remaining = remainingItems(planned, [
      _log(MealSlot.breakfast, 500, r: 'oats'),
      _log(MealSlot.dinner, 500, r: 'stew'),
      // Off-plan, matches nothing.
      _log(MealSlot.snack, 300, foodId: 'crisps'),
    ]);
    expect(remaining.map((i) => (i.key, i.slot)), [
      ('recipe:stew', MealSlot.lunch),
      ('food:coffee', MealSlot.snack),
    ]);
  });

  test('an off-plan snack shrinks the rest of the day', () {
    final remaining = [
      _dish('recipe:stew', MealSlot.lunch),
      _dish('recipe:curry', MealSlot.dinner),
      _coffee,
    ];
    // Target 1,600: breakfast (500) + 400 kcal of cake eaten, so 700 left
    // for 1,100 kcal of plan. The coffee is fixed, so 600 for the dishes.
    final r = replanRestOfDay(
      remaining: remaining,
      eaten: const Nutrition(kcal: 900, proteinG: 30, carbsG: 0, fatG: 0),
      targetKcal: 1600,
    );
    expect(r.items.map((i) => i.amount), [0.6, 0.6, 250]);
    expect(r.dayKcal, closeTo(1600, 1));
    expect(r.note, isNull);
    expect(r.changedFrom(remaining), hasLength(2));
  });

  test('a light day so far grows the rest, up to each range', () {
    final r = replanRestOfDay(
      remaining: [_dish('recipe:stew', MealSlot.dinner)],
      eaten: const Nutrition(kcal: 300, proteinG: 0, carbsG: 0, fatG: 0),
      targetKcal: 2000,
    );
    expect(r.items.single.amount, 1.75);
    expect(r.dayKcal, 1175);
    expect(r.note, contains('about 825 kcal short'));
  });

  test('a big lunch: the smallest portions and a note, not a hidden miss', () {
    final r = replanRestOfDay(
      remaining: [_dish('recipe:curry', MealSlot.dinner)],
      eaten: const Nutrition(kcal: 2100, proteinG: 0, carbsG: 0, fatG: 0),
      targetKcal: 2000,
    );
    expect(r.items.single.amount, 0.5);
    expect(r.note, contains('about 350 kcal over'));
  });

  test('locked and fixed items keep their amounts', () {
    final remaining = [
      _dish('recipe:stew', MealSlot.lunch, locked: true),
      _dish('recipe:curry', MealSlot.dinner),
      _dish('recipe:boxed', MealSlot.snack),
    ];
    final r = replanRestOfDay(
      remaining: remaining,
      eaten: Nutrition.zero,
      targetKcal: 1250,
      fixed: (i) => i.key == 'recipe:boxed',
    );
    expect(r.items.map((i) => i.amount), [1, 0.5, 1]);
    expect(r.changedFrom(remaining).single.key, 'recipe:curry');
  });

  test('nothing left to eat: says how the day ends up', () {
    final over = replanRestOfDay(
      remaining: const [],
      eaten: const Nutrition(kcal: 2500, proteinG: 0, carbsG: 0, fatG: 0),
      targetKcal: 2000,
    );
    expect(over.items, isEmpty);
    expect(over.note, contains('500 kcal over'));
    final close = replanRestOfDay(
      remaining: const [],
      eaten: const Nutrition(kcal: 1950, proteinG: 0, carbsG: 0, fatG: 0),
      targetKcal: 2000,
    );
    expect(close.note, isNull, reason: 'within 100 kcal');
  });
}
