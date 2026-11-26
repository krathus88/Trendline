import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/dish_templates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';
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
        // Meals: 200-1,000 kcal and 12 g protein a portion. Snacks (no-cook):
        // 100-450 kcal and some protein, so they hold off hunger.
        final (minKcal, maxKcal, minProtein) = t.noCook
            ? (100.0, 450.0, 4.0)
            : (200.0, 1000.0, 12.0);
        for (final f in t.flavourIds.isEmpty ? [null] : t.flavourIds) {
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
              inInclusiveRange(minKcal, maxKcal),
              reason: '${dish.name}: ${perPortion.round()} kcal',
            );
            expect(
              portion.protein / t.portions,
              greaterThanOrEqualTo(minProtein),
              reason: '${dish.name} protein',
            );
            expect(dish.expectedCookedWeightG(kcal), isNotNull);
            expect(dish.name, isNot(contains('{')), reason: dish.name);
            if (t.noCook) {
              expect(dish.madeWeightG, greaterThan(0), reason: dish.name);
            } else {
              expect(dish.madeWeightG, isNull, reason: 'cooked: weigh it');
            }
          }
        }
      }
    });

    test('there are snacks, and they are all no-cook', () {
      final snacks = [
        for (final t in shipped.templates)
          if (t.meals.contains(MealSlot.snack)) t,
      ];
      expect(snacks.length, greaterThanOrEqualTo(5));
      for (final t in snacks) {
        expect(t.noCook, isTrue, reason: t.id);
        expect(t.label, isNotNull, reason: '${t.id} needs a picker label');
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
          make(seed, prefs: prefs).flavour?.id,
          isNot(anyOf('indian', 'mexican')),
        );
      }
    });

    test('never-cuisines are never used', () {
      const prefs = FoodPreferences(
        cuisines: {Cuisine.indian: Preference.never},
      );
      for (var seed = 0; seed < 100; seed++) {
        expect(
          make(seed, prefs: prefs).flavour?.cuisine,
          isNot(Cuisine.indian),
        );
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
        expect(dish.flavour?.id, 'mexican');
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

    test('a no-cook snack has no flavour and is named from its picks', () {
      final bowl = shipped.templates.firstWhere((t) => t.id == 'yogurt-bowl');
      final dish = generateDish(
        bowl,
        shipped.flavours,
        FoodPreferences.none,
        Random(1),
        chosen: {
          0: bowl.slots[0].options.first,
          1: bowl.slots[1].options.first,
          2: null,
        },
      ) as GeneratedDish;
      expect(dish.flavour, isNull);
      expect(dish.name, 'Greek yogurt with blueberries');
      expect(dish.toRecipe().cuisine, isNull);
      expect(dish.madeWeightG, 150 + 80);
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

    test('only no-cook dishes go without a flavour, and they keep fresh', () {
      final source = File('assets/dish_templates.json').readAsStringSync();
      for (final (from, to) in [
        // A cooked dish without flavours.
        ('"flavours": ["british", "mediterranean"],\n', ''),
        // A no-cook dish that claims to keep.
        (
          '"no_cook": true,\n      "portions": 1,\n      "fridge_days": 0',
          '"no_cook": true,\n      "portions": 1,\n      "fridge_days": 2',
        ),
      ]) {
        expect(source.contains(from), isTrue, reason: from);
        expect(
          () => parseDishTemplates(source.replaceFirst(from, to)),
          throwsFormatException,
          reason: to,
        );
      }
    });
  });

  group('methods', () {
    /// Every dish a template can make with [flavourId]: each option in turn
    /// in every slot (the rest left to the seed), and each optional slot
    /// skipped too.
    Iterable<GeneratedDish> dishesOf(DishTemplate t, String? flavourId) sync* {
      for (final (i, slot) in t.slots.indexed) {
        for (final option in [...slot.options, if (slot.optional) null]) {
          final dish = generateDish(
            t,
            shipped.flavours,
            FoodPreferences.none,
            Random(i),
            flavourId: flavourId,
            chosen: {i: option},
          );
          if (dish is GeneratedDish) yield dish;
        }
      }
    }

    test('every shipped dish has complete, numbered steps', () {
      for (final t in shipped.templates) {
        expect(t.method, isNotEmpty, reason: t.id);
        for (final f in t.flavourIds.isEmpty ? [null] : t.flavourIds) {
          for (final dish in dishesOf(t, f)) {
            final method = dish.method!;
            final steps = method.split('\n');
            expect(
              steps.length,
              greaterThanOrEqualTo(t.noCook ? 1 : 3),
              reason: dish.name,
            );
            for (final (n, step) in steps.indexed) {
              expect(step, startsWith('${n + 1}. '), reason: dish.name);
              expect(step, isNot(contains('{')), reason: dish.name);
              expect(step, isNot(contains('}')), reason: dish.name);
              expect(step, matches(RegExp(r'[.!]$')), reason: step);
            }
            expect(steps.toSet(), hasLength(steps.length), reason: dish.name);
            // The copy saved to the user's recipes carries it.
            expect(dish.toRecipe().method, method);
          }
        }
      }
    });

    test('cooked dishes say when they are cooked, and how to keep them', () {
      for (final t in shipped.templates.where((t) => !t.noCook)) {
        for (final f in t.flavourIds) {
          for (final dish in dishesOf(t, f)) {
            final method = dish.method!;
            final protein =
                dish.picks[t.slots.indexWhere(
                  (s) => s.role == IngredientRole.protein,
                )]!;
            // Raw meat, fish and eggs always get a doneness check.
            if (protein.done case final done?) {
              expect(method, contains(done), reason: dish.name);
            }
            if (t.fridgeDays > 0) {
              expect(
                method,
                contains('fridge for up to ${t.fridgeDays} days'),
                reason: dish.name,
              );
              expect(method, contains('piping hot'), reason: dish.name);
            }
            if (method.contains('rice')) {
              expect(method, contains('within an hour'), reason: dish.name);
            }
          }
        }
      }
    });

    test('every raw meat, fish and egg option says how to tell it is '
        'cooked', () {
      for (final t in shipped.templates.where((t) => !t.noCook)) {
        for (final slot in t.slots.where(
          (s) => s.role == IngredientRole.protein,
        )) {
          for (final o in slot.options) {
            if (RegExp('Chicken|Turkey|Beef|Salmon|Cod|Eggs')
                .hasMatch(o.raw.name)) {
              expect(o.done, isNotNull, reason: '${t.id} ${o.label}');
            }
          }
        }
      }
    });

    test('a step can depend on what was picked', () {
      final omelette = shipped.templates.firstWhere((t) => t.id == 'omelette');
      final dairy = omelette.slots.indexWhere(
        (s) => s.role == IngredientRole.dairy,
      );
      String methodWith(TemplateOption? cheese) {
        final dish = generateDish(
          omelette,
          shipped.flavours,
          FoodPreferences.none,
          Random(1),
          chosen: {dairy: cheese},
        );
        return (dish as GeneratedDish).method!;
      }

      expect(methodWith(null), isNot(contains('Scatter over')));
      final feta = omelette.slots[dairy].options.firstWhere(
        (o) => o.label == 'feta',
      );
      expect(methodWith(feta), contains('Scatter over the feta.'));
    });

    test('several picks of one role are listed together', () {
      final bowl = shipped.templates.firstWhere((t) => t.id == 'rice-bowl');
      TemplateOption option(int slot, String label) =>
          bowl.slots[slot].options.firstWhere((o) => o.label == label);
      final dish = generateDish(
        bowl,
        shipped.flavours,
        FoodPreferences.none,
        Random(1),
        flavourId: 'chinese',
        chosen: {
          0: option(0, 'chickpea'),
          2: option(2, 'broccoli'),
          3: option(3, 'mushroom'),
        },
      );
      final method = (dish as GeneratedDish).method!;
      expect(method, contains('Add the broccoli and mushrooms'));
      expect(method, contains('Drain and rinse the chickpeas.'));
      expect(method, contains('until the chickpeas are hot through'));
      expect(method, contains('scatter over the sliced spring onions'));
    });

    test('a template with no method gives none', () {
      final source = File('assets/dish_templates.json').readAsStringSync();
      final start = source.indexOf('"method": [');
      final end = source.indexOf('],', start) + 2;
      final without = parseDishTemplates(source.replaceRange(start, end, ''));
      final dish = generateDish(
        without.templates.first,
        without.flavours,
        FoodPreferences.none,
        Random(1),
      );
      expect((dish as GeneratedDish).method, isNull);
    });

    test('refuses unknown placeholders and conditions', () {
      final source = File('assets/dish_templates.json').readAsStringSync();
      for (final (from, to) in [
        ('"Cook the {carb} as', '"Cook the {sprinkles} as'),
        ('{"if": "dairy",', '{"if": "custard",'),
        ('{"unless": "tuna",', '{"unless": "unicorn",'),
      ]) {
        expect(source.contains(from), isTrue, reason: from);
        expect(
          () => parseDishTemplates(source.replaceFirst(from, to)),
          throwsFormatException,
          reason: to,
        );
      }
    });
  });

  group('templateCopyMethod', () {
    /// [dish] saved as a recipe before templates had methods: its foods
    /// keep only their CoFID codes.
    (Recipe, Map<String, Food>) copyOf(GeneratedDish dish) {
      final foods = <String, Food>{};
      final ingredients = <RecipeIngredient>[];
      for (final (i, ing) in dish.ingredients.indexed) {
        foods['f$i'] = Food(
          id: 'f$i',
          name: ing.cofidName,
          per100g: const Nutrition(kcal: 100, proteinG: 1, carbsG: 1, fatG: 1),
          source: FoodSource.cofid,
          referenceCode: ing.cofidCode,
        );
        ingredients.add(
          RecipeIngredient(foodId: 'f$i', rawGrams: ing.rawGrams),
        );
      }
      final recipe = Recipe(
        id: 'r',
        name: dish.name,
        portions: dish.template.portions,
        ingredients: ingredients,
        origin: RecipeOrigin.template,
        sourceId: dish.template.id,
      );
      return (recipe, foods);
    }

    test('gives an old copy the steps it would get today', () {
      var checked = 0;
      final wrong = <String>[];
      for (final t in shipped.templates) {
        for (final flavourId in [
          ...t.flavourIds,
          if (t.flavourIds.isEmpty) null,
        ]) {
          for (var seed = 0; seed < 6; seed++) {
            final dish = generateDish(
              t,
              shipped.flavours,
              FoodPreferences.none,
              Random(seed),
              flavourId: flavourId,
            );
            if (dish is! GeneratedDish) continue;
            final (recipe, foods) = copyOf(dish);
            checked++;
            if (templateCopyMethod(recipe, foods, shipped) != dish.method) {
              wrong.add('${t.id} / $flavourId / ${dish.name}');
            }
          }
        }
      }
      expect(checked, greaterThan(50));
      expect(wrong, isEmpty);
    });

    test('nothing for other recipes or a template that is gone', () {
      final dish = generateDish(
        shipped.templates.first,
        shipped.flavours,
        FoodPreferences.none,
        Random(1),
      ) as GeneratedDish;
      final (recipe, foods) = copyOf(dish);
      expect(
        templateCopyMethod(
          Recipe(
            id: 'r',
            name: recipe.name,
            portions: recipe.portions,
            ingredients: recipe.ingredients,
          ),
          foods,
          shipped,
        ),
        isNull,
      );
      expect(
        templateCopyMethod(
          Recipe(
            id: 'r',
            name: recipe.name,
            portions: recipe.portions,
            ingredients: recipe.ingredients,
            origin: RecipeOrigin.template,
            sourceId: 'no-such-template',
          ),
          foods,
          shipped,
        ),
        isNull,
      );
    });
  });
}
