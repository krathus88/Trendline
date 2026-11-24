import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/dish_templates.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe_library.dart';

/// Basic foods as the data migration loads them: key -> (kcal, protein).
Map<FoodKey, ({double kcal, double protein})> _referenceFoods() {
  final sql = File(
    'supabase/migrations/20261129000100_reference_foods_data.sql',
  ).readAsStringSync();
  final row = RegExp(
    r"^  \('([0-9-]+)', '((?:[^']|'')*)', '(?:[^']|'')*', '[A-Z]+', "
    '([0-9.]+), ([0-9.]+),',
    multiLine: true,
  );
  return {
    for (final m in row.allMatches(sql))
      (code: m[1]!, name: m[2]!.replaceAll("''", "'")): (
        kcal: double.parse(m[3]!),
        protein: double.parse(m[4]!),
      ),
  };
}

const FoodKey _chicken = (code: '18-290', name: 'Chicken, light meat, raw');
const FoodKey _rice = (code: '11-857', name: 'Rice, white, basmati, raw');
const FoodKey _onion = (code: '13-499', name: 'Onions, raw');

void main() {
  final shipped = parseDishTemplates(
    File('assets/dish_templates.json').readAsStringSync(),
  );
  final foods = _referenceFoods();
  final kcal = {for (final e in foods.entries) e.key: e.value.kcal};

  group('the shipped templates', () {
    test('every food is a basic food the database has', () {
      final missing = [
        for (final k in shipped.foodKeys)
          if (!foods.containsKey(k)) '${k.code} ${k.name}',
      ];
      expect(missing, isEmpty);
    });

    test('every template makes sensible dishes with every flavour', () {
      for (final t in shipped.templates) {
        for (final f in t.flavourIds) {
          for (var seed = 0; seed < 20; seed++) {
            final dish = generateDish(
              t,
              shipped.flavours,
              FoodPreferences.none,
              Random(seed),
              flavourId: f,
            );
            expect(dish, isA<GeneratedDish>(), reason: '${t.id} $f');
            dish as GeneratedDish;
            final portion = dish.ingredients.fold(
              (kcal: 0.0, protein: 0.0),
              (sum, i) => (
                kcal: sum.kcal + foods[i.key]!.kcal * i.rawGrams / 100,
                protein: sum.protein + foods[i.key]!.protein * i.rawGrams / 100,
              ),
            );
            final perPortion = portion.kcal / t.portions;
            expect(
              perPortion,
              inInclusiveRange(200, 1000),
              reason: '${dish.name}: ${perPortion.round()} kcal',
            );
            expect(
              portion.protein / t.portions,
              greaterThanOrEqualTo(12),
              reason: '${dish.name} protein',
            );
            expect(dish.expectedCookedWeightG(kcal), isNotNull);
          }
        }
      }
    });
  });

  group('generateDish', () {
    final bowl = shipped.templates.firstWhere((t) => t.id == 'rice-bowl');

    GeneratedDish make(
      int seed, {
      FoodPreferences prefs = FoodPreferences.none,
      String? flavourId,
      Map<int, TemplateOption?> chosen = const {},
    }) => generateDish(
      bowl,
      shipped.flavours,
      prefs,
      Random(seed),
      flavourId: flavourId,
      chosen: chosen,
    ) as GeneratedDish;

    test('the same seed makes the same dish', () {
      expect(make(7).name, make(7).name);
      expect(make(7).picks, make(7).picks);
    });

    test('never-foods are never used', () {
      const prefs = FoodPreferences(ingredients: {_chicken: Preference.never});
      for (var seed = 0; seed < 300; seed++) {
        expect(
          make(seed, prefs: prefs).ingredients.map((i) => i.key),
          isNot(contains(_chicken)),
        );
      }
    });

    test('a never-ingredient in a flavour rules that flavour out', () {
      // Onion is in the Indian and Mexican profiles.
      const prefs = FoodPreferences(ingredients: {_onion: Preference.never});
      for (var seed = 0; seed < 100; seed++) {
        expect(
          make(seed, prefs: prefs).flavour.id,
          isNot(anyOf('indian', 'mexican')),
        );
      }
    });

    test('never-cuisines are never used', () {
      const prefs = FoodPreferences(
        cuisines: {Cuisine.indian: Preference.never},
      );
      for (var seed = 0; seed < 100; seed++) {
        expect(make(seed, prefs: prefs).flavour.cuisine, isNot(Cuisine.indian));
      }
    });

    test('liked foods come up more often, disliked less', () {
      int chickenCount(FoodPreferences prefs) => [
        for (var seed = 0; seed < 3000; seed++)
          if (make(seed, prefs: prefs).picks.first!.raw == _chicken) 1,
      ].length;
      final neutral = chickenCount(FoodPreferences.none);
      final liked = chickenCount(
        const FoodPreferences(ingredients: {_chicken: Preference.like}),
      );
      final disliked = chickenCount(
        const FoodPreferences(ingredients: {_chicken: Preference.dislike}),
      );
      // Six proteins: about 1/6 neutral, 3/8 liked, 1/21 disliked.
      expect(neutral, inInclusiveRange(380, 620));
      expect(liked, greaterThan(neutral * 1.8));
      expect(disliked, lessThan(neutral * 0.5));
    });

    test('two vegetable slots never pick the same food', () {
      for (var seed = 0; seed < 200; seed++) {
        final veg = [
          for (final (i, s) in bowl.slots.indexed)
            if (s.role == IngredientRole.veg) make(seed).picks[i]!.raw,
        ];
        expect(veg.toSet(), hasLength(veg.length));
      }
    });

    test('choices the user made are kept', () {
      final rice = bowl.slots[1].options.firstWhere((o) => o.raw == _rice);
      for (var seed = 0; seed < 50; seed++) {
        final dish = make(seed, flavourId: 'mexican', chosen: {1: rice});
        expect(dish.flavour.id, 'mexican');
        expect(dish.picks[1], rice);
        expect(dish.name, startsWith('Mexican '));
      }
    });

    test('says why when preferences leave nothing', () {
      final prefs = FoodPreferences(
        ingredients: {
          for (final o in bowl.slots.first.options) o.raw: Preference.never,
        },
      );
      final result = generateDish(bowl, shipped.flavours, prefs, Random(1));
      expect(result, isA<NoDish>());
      expect((result as NoDish).reason, contains('protein'));
    });

    test('the batch merges the same food from two places', () {
      // Onion comes from the Indian flavour (40 g a portion); listed once.
      final dish = make(3, flavourId: 'indian');
      final onions = dish.ingredients.where((i) => i.key == _onion);
      expect(onions, hasLength(1));
      expect(onions.single.rawGrams, 40 * bowl.portions);
    });

    test('names fill in the flavour and the protein', () {
      final dish = make(
        1,
        flavourId: 'indian',
        chosen: {0: bowl.slots.first.options.first},
      );
      expect(dish.name, 'Indian chicken rice bowl');
    });
  });

  group('expectedCookedWeightG', () {
    test('rice triples, chicken shrinks, the rest stays', () {
      final bowl = shipped.templates.firstWhere((t) => t.id == 'rice-bowl');
      final dish = generateDish(
        bowl,
        shipped.flavours,
        FoodPreferences.none,
        Random(1),
        flavourId: 'mediterranean',
        chosen: {
          0: bowl.slots[0].options.firstWhere((o) => o.raw == _chicken),
          1: bowl.slots[1].options.firstWhere((o) => o.raw == _rice),
        },
      ) as GeneratedDish;
      // 4 portions: chicken 520 g x 106/148, rice 240 g x 351/117, veg 640 g,
      // oil 16 g, flavour 7.8 g x 4.
      const expected = 520 * 106 / 148 + 240 * 351 / 117 + 640 + 16 + 31.2;
      expect(dish.expectedCookedWeightG(kcal), (expected / 10).round() * 10);
    });

    test('is unknown when a value is missing', () {
      final bowl = shipped.templates.firstWhere((t) => t.id == 'rice-bowl');
      final dish = generateDish(
        bowl,
        shipped.flavours,
        FoodPreferences.none,
        Random(1),
        chosen: {1: bowl.slots[1].options.firstWhere((o) => o.raw == _rice)},
      ) as GeneratedDish;
      expect(dish.expectedCookedWeightG(const {}), isNull);
    });
  });

  group('parseDishTemplates', () {
    test('refuses an unknown format and bad references', () {
      expect(() => parseDishTemplates('{"format": 2}'), throwsFormatException);
      final source = File('assets/dish_templates.json').readAsStringSync();
      for (final (from, to) in [
        ('"options": "lean-protein"', '"options": "no-such-set"'),
        ('"flavours": ["chinese"]', '"flavours": ["martian"]'),
        ('"grams": 130, "min": 90', '"grams": 30, "min": 90'),
        ('"18-290"', '"18290"'),
      ]) {
        expect(
          () => parseDishTemplates(source.replaceFirst(from, to)),
          throwsFormatException,
          reason: to,
        );
      }
    });
  });
}
