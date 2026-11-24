import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/meal_rules/meal_rule_repository.dart';
import 'package:trendline/data/schedule/schedule_repository.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/schedule.dart';

void main() {
  group('schedule rows', () {
    test('Postgres times become minutes after midnight', () {
      expect(readClock('07:30:00'), 450);
      expect(readClock('23:59'), 1439);
      expect(readClock('24:00:00'), isNull);
      expect(readClock('7am'), isNull);
      expect(readClock(null), isNull);
    });

    test('round-trip', () {
      const s = DaySchedule(weekday: 6, wakeMinute: 900, sleepMinute: 420);
      final row = scheduleToRow(s);
      expect(row, {'weekday': 6, 'wake_time': '15:00', 'sleep_time': '07:00'});
      expect(scheduleFromRow(row), s);
      expect(scheduleFromRow({'weekday': 1, 'wake_time': 'x'}), isNull);
    });
  });

  group('meal rule rows', () {
    test('round-trip a weekly rule', () {
      const rule = MealRule(
        id: 'm1',
        foodId: 'salmon',
        frequency: RuleFrequency.minPerWeek,
        timesPerWeek: 2,
        amountMin: 120.04,
        amountMax: 180,
      );
      final row = mealRuleToRow(rule);
      expect(row['frequency'], 'min_per_week');
      expect(row['slot'], isNull);
      expect(row['amount_min'], 120.0);
      final back = mealRuleFromRow({...row, 'id': 'm1'})!;
      expect(back.frequency, RuleFrequency.minPerWeek);
      expect(back.timesPerWeek, 2);
      expect(back.slot, isNull);
    });

    test('a daily rule sends no count', () {
      final row = mealRuleToRow(
        const MealRule(
          id: '',
          recipeId: 'stew',
          slot: MealSlot.dinner,
          frequency: RuleFrequency.daily,
          timesPerWeek: 3,
          amountMin: 1,
          amountMax: 1,
        ),
      );
      expect(row['times_per_week'], isNull);
      expect(row['slot'], 'dinner');
      expect(row['recipe_id'], 'stew');
    });

    test('unreadable rows are skipped', () {
      expect(
        mealRuleFromRow({
          'id': 'm1',
          'frequency': 'fortnightly',
          'amount_min': 1,
          'amount_max': 1,
        }),
        isNull,
      );
    });
  });
}
