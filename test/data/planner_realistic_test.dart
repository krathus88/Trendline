import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/plans/planner_catalogue.dart';
import 'package:trendline/domain/dish_templates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/recipe_library.dart';

/// Basic foods as the data migration loads them.
Map<FoodKey, FoodDraft> _basicFoods() {
  final sql = File(
    'supabase/migrations/20261129000100_reference_foods_data.sql',
  ).readAsStringSync();
  const text = "'((?:[^']|'')*)'";
  const number = '(null|[0-9.]+)';
  final row = RegExp(
    "^  \\('([0-9-]+)', $text, $text, '[A-Z]+', "
    '$number, $number, $number, $number, $number,',
    multiLine: true,
  );
  double? n(String? v) => v == null || v == 'null' ? null : double.parse(v);
  return {
    for (final m in row.allMatches(sql))
      (code: m[1]!, name: m[2]!.replaceAll("''", "'")): FoodDraft(
        name: m[3]!.replaceAll("''", "'"),
        per100g: Nutrition(
          kcal: n(m[4])!,
          proteinG: n(m[5])!,
          carbsG: n(m[6])!,
          fatG: n(m[7])!,
          fibreG: n(m[8]) ?? 0,
          fibreUnknown: n(m[8]) == null,
        ),
        source: FoodSource.cofid,
        referenceCode: m[1],
        referenceName: m[2]!.replaceAll("''", "'"),
      ),
  };
}

void main() {
  test('the shipped library and templates plan a sound week', () {
    final foods = _basicFoods();
    final catalogue = buildCatalogue(
      PlannerSources(
        recipes: const [],
        foods: const {},
        library: parseRecipeLibrary(
          File('assets/recipe_library.json').readAsStringSync(),
        ),
        libraryFoods: foods,
        templates: parseDishTemplates(
          File('assets/dish_templates.json').readAsStringSync(),
        ),
        templateFoods: foods,
        preferences: FoodPreferences.none,
        rules: const [],
      ),
    );
    expect(catalogue.dishes.length, greaterThan(30));

    for (final targets in const [
      // A typical loss target, a larger one, and a smaller one near the
      // 1,500 floor.
      PlanTargets(kcal: 2100, proteinG: 150, carbsG: 220, fatG: 70, fibreG: 30),
      PlanTargets(kcal: 2360, proteinG: 157, carbsG: 250, fatG: 79, fibreG: 30),
      PlanTargets(kcal: 1550, proteinG: 120, carbsG: 150, fatG: 52, fibreG: 30),
    ]) {
      final plan = planWeek(
        PlannerInput(targets: [targets], dishes: catalogue.dishes),
        Random(1),
      );
      final dishes = plan.items.map((i) => i.key).toSet();
      final batches = {for (final i in plan.items) ?i.batch};
      final snacks = [
        for (final i in plan.items)
          if (i.slot == MealSlot.snack) i,
      ];
      // Printed so a run shows what the planner made; tests have no logger.
      // ignore: avoid_print
      print(
        '${targets.kcal.round()} kcal: ${dishes.length} dishes, '
        '${batches.length} cook sessions, snacks '
        '${snacks.map((s) => '${s.name} ${s.amount}').toSet()}. '
        'Notes: ${plan.notes}',
      );
      expect(snacks, hasLength(7), reason: 'a snack every day');
      expect(
        snacks.every((s) => s.batch == null),
        isTrue,
        reason: 'snacks are made fresh, never batch-cooked',
      );
      expect(
        snacks.map((s) => s.key).toSet().length,
        greaterThanOrEqualTo(3),
        reason: 'snacks vary',
      );
      for (final s in snacks) {
        expect(s.amount, inInclusiveRange(0.5, 1.5), reason: s.name);
      }
      for (var d = 0; d < 7; d++) {
        final n = plan.totalOn(d);
        expect(
          n.kcal,
          closeTo(targets.kcal, targets.kcal * 0.1),
          reason: 'day $d',
        );
        expect(
          n.proteinG,
          greaterThan(targets.proteinG * 0.8),
          reason: 'day $d protein ${n.proteinG.round()}',
        );
      }
      expect(dishes.length, greaterThanOrEqualTo(4), reason: 'some variety');
      expect(batches.length, lessThan(21), reason: 'some batch cooking');
    }
  });
}
