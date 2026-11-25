import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/schedule.dart';

void main() {
  group('mealTimes', () {
    String at(DaySchedule s, MealSlot slot) => formatClock(mealTimes(s)[slot]!);

    test('a standard day', () {
      const day = DaySchedule.standard(1);
      expect(at(day, MealSlot.breakfast), '07:30');
      expect(at(day, MealSlot.lunch), '13:45');
      expect(at(day, MealSlot.snack), '17:00');
      expect(at(day, MealSlot.dinner), '20:00');
    });

    test('a night shift crosses midnight', () {
      const day = DaySchedule(
        weekday: 6,
        wakeMinute: 15 * 60,
        sleepMinute: 7 * 60,
      );
      expect(day.awakeMinutes, 16 * 60);
      expect(at(day, MealSlot.breakfast), '15:30');
      expect(at(day, MealSlot.lunch), '21:45');
      expect(at(day, MealSlot.snack), '01:00');
      expect(at(day, MealSlot.dinner), '04:00');
    });

    test('meals stay in order on the shortest and longest days', () {
      for (final awake in [8 * 60, 20 * 60]) {
        final day = DaySchedule(
          weekday: 1,
          wakeMinute: 6 * 60,
          sleepMinute: (6 * 60 + awake) % (24 * 60),
        );
        final t = mealTimes(day);
        int since(MealSlot s) => (t[s]! - day.wakeMinute + 1440) % 1440;
        expect(since(MealSlot.breakfast), lessThan(since(MealSlot.lunch)));
        expect(since(MealSlot.lunch), lessThan(since(MealSlot.snack)));
        expect(since(MealSlot.snack), lessThan(since(MealSlot.dinner)));
        expect(since(MealSlot.dinner), lessThanOrEqualTo(awake - 180));
      }
    });
  });

  group('validateSchedule', () {
    test('accepts normal days and night shifts', () {
      expect(validateSchedule(const DaySchedule.standard(3)), isNull);
      expect(
        validateSchedule(
          const DaySchedule(weekday: 6, wakeMinute: 900, sleepMinute: 420),
        ),
        isNull,
      );
    });

    test('refuses too short, too long and impossible days', () {
      for (final s in const [
        DaySchedule(weekday: 1, wakeMinute: 420, sleepMinute: 720),
        DaySchedule(weekday: 1, wakeMinute: 300, sleepMinute: 180),
        DaySchedule(weekday: 1, wakeMinute: 420, sleepMinute: 420),
        DaySchedule(weekday: 0, wakeMinute: 420, sleepMinute: 1380),
        DaySchedule(weekday: 1, wakeMinute: 420, sleepMinute: 1440),
      ]) {
        expect(validateSchedule(s), isNotNull);
      }
    });
  });

  test('fullWeek fills unset days with the standard day', () {
    const saturday = DaySchedule(
      weekday: 6,
      wakeMinute: 9 * 60,
      sleepMinute: 60,
    );
    final week = fullWeek([saturday]);
    expect(week.map((d) => d.weekday), [1, 2, 3, 4, 5, 6, 7]);
    expect(week[5], saturday);
    expect(week[0], const DaySchedule.standard(1));
    expect(
      [for (final d in week) d.isSet],
      [false, false, false, false, false, true, false],
      reason: 'only the saved day counts as set',
    );
    // A saved day with the standard times is still set, and equal to it.
    const savedStandard = DaySchedule(
      weekday: 1,
      wakeMinute: 7 * 60,
      sleepMinute: 23 * 60,
    );
    expect(savedStandard.isSet, isTrue);
    expect(savedStandard, const DaySchedule.standard(1));
  });

  group('meal rules', () {
    const cappuccino = MealRule(
      id: 'r1',
      foodId: 'coffee',
      slot: MealSlot.breakfast,
      frequency: RuleFrequency.daily,
      amountMin: 250,
      amountMax: 250,
    );

    MealRule weekly(
      RuleFrequency f,
      int times, {
      String food = 'salmon',
      MealSlot? slot,
    }) => MealRule(
      id: '',
      foodId: food,
      slot: slot,
      frequency: f,
      timesPerWeek: times,
      amountMin: 120,
      amountMax: 180,
    );

    test('accepts normal rules', () {
      expect(validateRule(cappuccino), isNull);
      expect(validateRule(weekly(RuleFrequency.minPerWeek, 2)), isNull);
      expect(validateRule(weekly(RuleFrequency.maxPerWeek, 28)), isNull);
    });

    test('refuses impossible rules', () {
      expect(validateRule(weekly(RuleFrequency.minPerWeek, 0)), isNotNull);
      expect(
        validateRule(weekly(RuleFrequency.minPerWeek, 8, slot: MealSlot.lunch)),
        isNotNull,
        reason: 'lunch only happens 7 times a week',
      );
      expect(validateRule(weekly(RuleFrequency.maxPerWeek, 29)), isNotNull);
      expect(
        validateRule(
          const MealRule(
            id: '',
            foodId: 'coffee',
            frequency: RuleFrequency.daily,
            amountMin: 300,
            amountMax: 200,
          ),
        ),
        isNotNull,
      );
      expect(
        validateRule(
          const MealRule(
            id: '',
            frequency: RuleFrequency.daily,
            amountMin: 1,
            amountMax: 1,
          ),
        ),
        isNotNull,
        reason: 'needs a food or recipe',
      );
      expect(
        validateRule(
          const MealRule(
            id: '',
            recipeId: 'stew',
            frequency: RuleFrequency.daily,
            amountMin: 1,
            amountMax: 12,
          ),
        ),
        isNotNull,
        reason: 'at most 10 portions',
      );
    });

    test('finds rules that cannot all be met', () {
      String name(MealRule r) => r.target;
      expect(
        ruleConflicts([
          weekly(RuleFrequency.minPerWeek, 3),
          weekly(RuleFrequency.maxPerWeek, 2),
        ], name),
        ['salmon: at least 3 but at most 2 times a week.'],
      );
      expect(
        ruleConflicts([
          cappuccino,
          weekly(RuleFrequency.maxPerWeek, 5, food: 'coffee'),
        ], name),
        hasLength(1),
        reason: 'daily is 7 times a week',
      );
      expect(
        ruleConflicts([
          cappuccino,
          const MealRule(
            id: 'r2',
            foodId: 'coffee',
            slot: MealSlot.breakfast,
            frequency: RuleFrequency.daily,
            amountMin: 100,
            amountMax: 150,
          ),
        ], name),
        ['coffee: two daily amounts that don’t overlap.'],
      );
    });

    test('rules that fit together are fine', () {
      expect(
        ruleConflicts([
          cappuccino,
          weekly(RuleFrequency.minPerWeek, 2),
          weekly(RuleFrequency.maxPerWeek, 4),
          weekly(RuleFrequency.maxPerWeek, 3, food: 'chocolate'),
        ], (r) => r.target),
        isEmpty,
      );
      expect(ruleConflicts(const [], (r) => r.target), isEmpty);
    });
  });
}
