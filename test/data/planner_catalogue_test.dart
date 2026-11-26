import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/data/plans/planner_catalogue.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';

const FoodKey _oatsKey = (code: '11-788', name: 'Porridge oats, unfortified');
const FoodKey _yogKey = (code: '12-555', name: 'Yogurt, Greek style, plain');

const _oatsDraft = FoodDraft(
  name: 'Porridge oats, unfortified',
  per100g: Nutrition(kcal: 381, proteinG: 10.9, carbsG: 64, fatG: 8),
  source: FoodSource.cofid,
  referenceCode: '11-788',
);
const _yogDraft = FoodDraft(
  name: 'Greek style yogurt, plain',
  per100g: Nutrition(kcal: 133, proteinG: 5.7, carbsG: 4.6, fatG: 10.2),
  source: FoodSource.cofid,
  referenceCode: '12-555',
);

const _oatsRecipe = LibraryRecipe(
  id: 'oats',
  version: 1,
  name: 'Overnight oats',
  meals: {MealSlot.breakfast},
  cuisine: Cuisine.british,
  portions: 2,
  fridgeDays: 3,
  freezable: false,
  ingredients: [
    LibraryIngredient(
      cofidCode: '11-788',
      cofidName: 'Porridge oats, unfortified',
      rawGrams: 100,
      role: IngredientRole.carb,
    ),
    LibraryIngredient(
      cofidCode: '12-555',
      cofidName: 'Yogurt, Greek style, plain',
      rawGrams: 200,
      role: IngredientRole.protein,
    ),
  ],
);

const _chicken = Food(
  id: 'f-chicken',
  name: 'Chicken',
  per100g: Nutrition(kcal: 106, proteinG: 24, carbsG: 0, fatG: 1.5),
  source: FoodSource.manual,
);
const _myYogurt = Food(
  id: 'f-yog',
  name: 'Greek style yogurt, plain',
  per100g: Nutrition(kcal: 133, proteinG: 5.7, carbsG: 4.6, fatG: 10.2),
  source: FoodSource.cofid,
  referenceCode: '12-555',
);

PlannerSources _sources({
  List<Recipe> recipes = const [],
  FoodPreferences preferences = FoodPreferences.none,
  List<MealRule> rules = const [],
  Set<String> favourites = const {},
}) => PlannerSources(
  recipes: recipes,
  foods: {
    for (final f in [_chicken, _myYogurt]) f.id: f,
  },
  library: const [_oatsRecipe],
  libraryFoods: const {_oatsKey: _oatsDraft, _yogKey: _yogDraft},
  templates: null,
  templateFoods: const {},
  preferences: preferences,
  rules: rules,
  favourites: favourites,
);

const _myStew = Recipe(
  id: 'r-stew',
  name: 'My stew',
  portions: 3,
  fridgeDays: 2,
  ingredients: [RecipeIngredient(foodId: 'f-chicken', rawGrams: 600)],
);

void main() {
  test('offers listed recipes and library recipes not yet copied', () {
    final c = buildCatalogue(
      _sources(
        recipes: [
          _myStew,
          const Recipe(
            id: 'r-hidden',
            name: 'Planner copy',
            listed: false,
            ingredients: [RecipeIngredient(foodId: 'f-chicken', rawGrams: 1)],
          ),
        ],
      ),
    );
    final keys = c.dishes.map((d) => d.key);
    expect(keys, containsAll(['recipe:r-stew', 'library:oats']));
    expect(keys, isNot(contains('recipe:r-hidden')));

    final stew = c.dishes.firstWhere((d) => d.key == 'recipe:r-stew');
    expect(stew.meals, {MealSlot.lunch, MealSlot.dinner});
    expect(stew.maxServingsPerBatch, 3);
    expect(stew.keepsDays, 2);
    expect(stew.perPortion.kcal, closeTo(636 / 3, 0.01));
    expect(stew.contains, {'recipe:r-stew', 'food:f-chicken'});

    final oats = c.dishes.firstWhere((d) => d.key == 'library:oats');
    expect(oats.meals, {MealSlot.breakfast});
    expect(oats.contains, {
      'food:f-yog',
    }, reason: 'the user’s copy of the yogurt counts for rules about it');
  });

  test('a favourite recipe is offered as often as a liked dish', () {
    const other = Recipe(
      id: 'r-other',
      name: 'Other stew',
      ingredients: [RecipeIngredient(foodId: 'f-chicken', rawGrams: 600)],
    );
    final c = buildCatalogue(
      _sources(recipes: [_myStew, other], favourites: {'r-stew'}),
    );
    final stew = c.dishes.firstWhere((d) => d.key == 'recipe:r-stew');
    final plain = c.dishes.firstWhere((d) => d.key == 'recipe:r-other');
    expect(stew.favourite, isTrue);
    expect(stew.preference, favouriteWeight);
    expect(stew.preference, preferenceWeight(Preference.like));
    expect(plain.favourite, isFalse);
    expect(plain.preference, 1);
  });

  test('a mix is never a dish, but a meal rule can still place it', () {
    const latte = Recipe(
      id: 'r-latte',
      name: 'Coffee with yogurt',
      portions: 1,
      cookedWeightG: 215,
      fridgeDays: 0,
      freezable: false,
      origin: RecipeOrigin.mix,
      ingredients: [RecipeIngredient(foodId: 'f-yog', rawGrams: 200)],
    );
    final c = buildCatalogue(
      _sources(
        recipes: [latte],
        rules: const [
          MealRule(
            id: 'm1',
            recipeId: 'r-latte',
            slot: MealSlot.breakfast,
            frequency: RuleFrequency.daily,
            amountMin: 1,
            amountMax: 1,
          ),
        ],
      ),
    );
    expect(c.dishes.map((d) => d.key), isNot(contains('recipe:r-latte')));
    final rule = c.rules.single;
    expect(rule.name, 'Coffee with yogurt');
    expect(rule.perUnit.kcal, closeTo(266, 0.01));
    expect(rule.isMeal, isFalse, reason: 'it goes beside breakfast');
  });

  test('a library recipe already copied is offered as the copy', () {
    final c = buildCatalogue(
      _sources(
        recipes: [
          const Recipe(
            id: 'r-oats',
            name: 'Overnight oats',
            origin: RecipeOrigin.library,
            sourceId: 'oats',
            sourceVersion: 1,
            ingredients: [RecipeIngredient(foodId: 'f-yog', rawGrams: 200)],
          ),
        ],
      ),
    );
    final keys = c.dishes.map((d) => d.key);
    expect(keys, isNot(contains('library:oats')));
    final copy = c.dishes.firstWhere((d) => d.key == 'recipe:r-oats');
    expect(copy.meals, {MealSlot.breakfast}, reason: 'the library’s meals');
  });

  test('never-foods and never-cuisines leave dishes out', () {
    for (final prefs in const [
      FoodPreferences(ingredients: {_yogKey: Preference.never}),
      FoodPreferences(cuisines: {Cuisine.british: Preference.never}),
    ]) {
      final c = buildCatalogue(_sources(preferences: prefs));
      expect(c.dishes.map((d) => d.key), isNot(contains('library:oats')));
    }
    final liked = buildCatalogue(
      _sources(
        preferences: const FoodPreferences(
          ingredients: {_oatsKey: Preference.like},
        ),
      ),
    );
    expect(liked.dishes.single.preference, 3);
  });

  test('rules get exact per-gram and per-portion values', () {
    final c = buildCatalogue(
      _sources(
        recipes: [_myStew],
        rules: const [
          MealRule(
            id: 'm1',
            foodId: 'f-yog',
            frequency: RuleFrequency.daily,
            amountMin: 150,
            amountMax: 150,
          ),
          MealRule(
            id: 'm2',
            recipeId: 'r-stew',
            frequency: RuleFrequency.maxPerWeek,
            timesPerWeek: 2,
            amountMin: 1,
            amountMax: 1,
          ),
          MealRule(
            id: 'm3',
            foodId: 'gone',
            frequency: RuleFrequency.daily,
            amountMin: 1,
            amountMax: 1,
          ),
        ],
      ),
    );
    expect(
      c.rules,
      hasLength(2),
      reason: 'a rule about a missing food is skipped',
    );
    final yogurt = c.rules.first;
    expect(yogurt.name, 'Greek style yogurt, plain');
    expect(yogurt.perUnit.proteinG, closeTo(0.057, 1e-9));
    expect(c.rules.last.perUnit.kcal, closeTo(212, 0.01));
    expect(yogurt.isMeal, isFalse, reason: 'a food goes beside a dish');
    expect(c.rules.last.isMeal, isTrue, reason: 'the stew is a meal');
  });

  test('plan rows round-trip', () {
    final plan = SavedPlan(
      weekStart: DateTime(2026, 12, 7),
      targets: [
        for (var d = 0; d < 7; d++)
          PlanTargets(
            // Sunday is a maintenance day (the goal date fell on Saturday).
            kcal: d == 6 ? 2600 : 2000.04,
            proteinG: 140,
            carbsG: 200,
            fatG: 65,
            fibreG: 30,
          ),
      ],
      notes: const ['A note'],
      items: [
        SavedPlanItem(
          day: DateTime(2026, 12, 8),
          slot: MealSlot.dinner,
          recipeId: 'r1',
          amount: 1.254,
          amountMin: 0.5,
          amountMax: 1.75,
          locked: true,
          batch: 2,
        ),
      ],
    );
    final params = savePlanParams(plan);
    expect(params['week_start'], '2026-12-07');
    final items = params['items'] as List;
    expect((items.single as Map)['amount'], 1.25);
    expect((items.single as Map)['day'], '2026-12-08');
    // The plan's own columns hold Monday's; every day goes in day_targets.
    expect(params['kcal_target'], 2000);
    final days = params['day_targets'] as List;
    expect(days, hasLength(7));
    expect((days.last as Map)['kcal'], 2600);

    final back = savedPlanFromRow({
      'week_start': '2026-12-07',
      'kcal_target': '2000.0',
      'protein_target_g': 140,
      'carbs_target_g': 200,
      'fat_target_g': 65,
      'fibre_target_g': 30,
      'day_targets': days,
      'notes': ['A note'],
      'plan_items': [
        {...(items.single as Map<String, dynamic>)},
      ],
    });
    expect(back.notes, ['A note']);
    expect(back.items.single.locked, isTrue);
    expect(back.items.single.batch, 2);
    expect(back.items.single.day, DateTime(2026, 12, 8));
    expect(
      [for (final t in back.targets) t.kcal],
      [...List.filled(6, 2000), 2600],
    );

    // Plans saved before day targets were kept use their own every day.
    final older = savedPlanFromRow({
      'week_start': '2026-12-07',
      'kcal_target': 1900,
      'protein_target_g': 140,
      'carbs_target_g': 200,
      'fat_target_g': 65,
      'fibre_target_g': 30,
      'day_targets': null,
    });
    expect([for (final t in older.targets) t.kcal], List.filled(7, 1900));
  });
}
