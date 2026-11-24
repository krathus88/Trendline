import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/recipe_library.dart';

/// Basic foods as the data migration loads them: (code, name) -> kcal.
Map<({String code, String name}), double> _referenceFoods() {
  final sql = File(
    'supabase/migrations/20261129000100_reference_foods_data.sql',
  ).readAsStringSync();
  final row = RegExp(
    r"^  \('([0-9-]+)', '((?:[^']|'')*)', '(?:[^']|'')*', '[A-Z]+', ([0-9.]+),",
    multiLine: true,
  );
  return {
    for (final m in row.allMatches(sql))
      (code: m[1]!, name: m[2]!.replaceAll("''", "'")): double.parse(m[3]!),
  };
}

void main() {
  group('the shipped library', () {
    final library = parseRecipeLibrary(
      File('assets/recipe_library.json').readAsStringSync(),
    );
    final foods = _referenceFoods();

    test('parses, and has recipes', () {
      expect(foods, hasLength(greaterThan(2000)));
      expect(library, isNotEmpty);
    });

    test('every ingredient is a basic food the database has', () {
      final missing = [
        for (final r in library)
          for (final i in r.ingredients)
            if (!foods.containsKey(i.key))
              '${r.id}: ${i.cofidCode} ${i.cofidName}',
      ];
      expect(missing, isEmpty);
    });

    test('every recipe has a protein and a plausible portion size', () {
      for (final r in library) {
        expect(
          r.ingredients.any((i) => i.role == IngredientRole.protein),
          isTrue,
          reason: '${r.id} has no protein',
        );
        final kcal = r.ingredients.fold<double>(
          0,
          (sum, i) => sum + foods[i.key]! * i.rawGrams / 100,
        );
        expect(
          kcal / r.portions,
          inInclusiveRange(150, 1200),
          reason: '${r.id}: ${(kcal / r.portions).round()} kcal a portion',
        );
      }
    });
  });

  group('parseRecipeLibrary', () {
    String library(String recipe) => '{"format": 1, "recipes": [$recipe]}';
    const good =
        '{"id": "oats", "version": 1, "name": "Oats", "meals": ["breakfast"], '
        '"cuisine": "british", "portions": 2, "fridge_days": 3, '
        '"freezable": false, "ingredients": [{"cofid": "11-788", '
        '"name": "Porridge oats, unfortified", "grams": 80, "role": "carb"}]}';

    test('reads a recipe', () {
      final r = parseRecipeLibrary(library(good)).single;
      expect(r.id, 'oats');
      expect(r.meals, {MealSlot.breakfast});
      expect(r.cuisine, Cuisine.british);
      expect(r.ingredients.single.rawGrams, 80);
      expect(r.ingredients.single.role, IngredientRole.carb);
      expect(r.method, isNull);
    });

    test('refuses an unknown format', () {
      expect(
        () => parseRecipeLibrary('{"format": 2, "recipes": []}'),
        throwsFormatException,
      );
    });

    test('refuses duplicate ids', () {
      expect(
        () => parseRecipeLibrary('{"format": 1, "recipes": [$good, $good]}'),
        throwsFormatException,
      );
    });

    test('refuses bad values', () {
      for (final (from, to) in [
        ('"oats"', '"Oats!"'),
        ('"portions": 2', '"portions": 0'),
        ('"fridge_days": 3', '"fridge_days": 9'),
        ('["breakfast"]', '["brunch"]'),
        ('"british"', '"martian"'),
        ('"grams": 80', '"grams": 0'),
        ('"grams": 80', '"grams": "80"'),
        ('"11-788"', '"11788"'),
        ('"role": "carb"', '"role": "garnish"'),
        ('"freezable": false', '"freezable": "no"'),
      ]) {
        expect(
          () => parseRecipeLibrary(library(good.replaceFirst(from, to))),
          throwsFormatException,
          reason: to,
        );
      }
    });
  });
}
