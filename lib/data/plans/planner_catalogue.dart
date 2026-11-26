import 'dart:math';

import 'package:meta/meta.dart';
import 'package:trendline/domain/dish_templates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';

/// Everything the planner draws on, already loaded.
@immutable
class PlannerSources {
  const new({
    required this.recipes,
    required this.foods,
    required this.library,
    required this.libraryFoods,
    required this.templates,
    required this.templateFoods,
    required this.preferences,
    required this.rules,
    this.favourites = const {},
  });

  final List<Recipe> recipes;
  final Map<String, Food> foods;
  final List<LibraryRecipe> library;
  final Map<FoodKey, FoodDraft> libraryFoods;
  final DishTemplates? templates;
  final Map<FoodKey, FoodDraft> templateFoods;
  final FoodPreferences preferences;
  final List<MealRule> rules;

  /// The IDs of the recipes the user has starred.
  final Set<String> favourites;
}

/// How much more often the planner offers a favourite recipe: as much as a
/// liked food or cuisine.
const double favouriteWeight = 3;

/// A template dish the planner may use, with its expected cooked weight.
typedef GeneratedOption = ({GeneratedDish dish, double? expectedCookedG});

/// The planner's candidates and rules, plus what's needed to save the
/// library and template dishes it picks.
@immutable
class PlannerCatalogue {
  const new({
    required this.dishes,
    required this.rules,
    required this.library,
    required this.generated,
  });

  final List<DishCandidate> dishes;
  final List<PlannerRule> rules;

  /// Library recipes by candidate key.
  final Map<String, LibraryRecipe> library;

  /// Template dishes by candidate key.
  final Map<String, GeneratedOption> generated;
}

/// Turns [s] into planner candidates:
///
/// * the user's listed recipes (in the meals of the library recipe or
///   template they came from; lunch and dinner for their own), except
///   mixes, which only meal rules place;
/// * library recipes they haven't copied yet;
/// * [variants] dishes per template and flavour, made under their
///   preferences.
///
/// Anything with a "never" food or cuisine is left out; likes and dislikes
/// set each dish's preference weight, and a starred recipe gets
/// [favouriteWeight].
PlannerCatalogue buildCatalogue(PlannerSources s, {int variants = 2}) {
  final prefs = s.preferences;
  final dishes = <DishCandidate>[];
  final library = <String, LibraryRecipe>{};
  final generated = <String, GeneratedOption>{};

  // The user's foods copied from basic foods, so rules about them can count
  // library and template dishes that use the same basic food.
  final userFoodByBasic = <(String, String), String>{
    for (final f in s.foods.values)
      if (f.referenceCode != null) (f.referenceCode!, f.name): f.id,
  };
  Set<String> containsBasic(
    Iterable<LibraryIngredient> ingredients,
    Map<FoodKey, FoodDraft> drafts,
  ) => {
    for (final i in ingredients)
      if (drafts[i.key] case final d?)
        if (userFoodByBasic[(d.referenceCode ?? '', d.name)] case final id?)
          'food:$id',
  };

  double weightOf(Iterable<LibraryIngredient> ingredients, Cuisine? cuisine) {
    var w = cuisine == null ? 1.0 : prefs.cuisineWeight(cuisine);
    for (final i in ingredients) {
      w *= prefs.ingredientWeight(i.key);
    }
    return w;
  }

  // What gives a dish most of its protein, as one id across sources: a
  // basic food (the user's copy included) by its CoFID code, any other
  // food by its id.
  String? proteinOfLibrary(
    Iterable<LibraryIngredient> ingredients,
    Map<FoodKey, FoodDraft> drafts,
  ) {
    String? best;
    var most = 0.0;
    for (final i in ingredients) {
      final grams = i.rawGrams * (drafts[i.key]?.per100g.proteinG ?? 0) / 100;
      if (grams > most) {
        most = grams;
        best = 'cofid:${i.cofidCode}';
      }
    }
    return best;
  }

  String? proteinOfRecipe(Recipe r) {
    String? best;
    var most = 0.0;
    for (final i in r.ingredients) {
      final food = s.foods[i.foodId];
      if (food == null) continue;
      final grams = i.rawGrams * food.per100g.proteinG / 100;
      if (grams > most) {
        most = grams;
        best = food.referenceCode != null
            ? 'cofid:${food.referenceCode}'
            : 'food:${food.id}';
      }
    }
    return best;
  }

  Nutrition? perPortionOf(LibraryRecipe r, Map<FoodKey, FoodDraft> drafts) =>
      libraryRecipeNutrition(r, {
        for (final e in drafts.entries) e.key: e.value.per100g,
      })?.perPortion;

  final libraryById = {for (final r in s.library) r.id: r};
  final templatesById = {
    for (final t in s.templates?.templates ?? const <DishTemplate>[]) t.id: t,
  };

  // The user's recipes. Mixes (a sachet with milk) aren't dishes: only meal
  // rules place them.
  for (final r in s.recipes) {
    if (!r.listed || r.origin == RecipeOrigin.mix) continue;
    final n = recipeNutrition(r, s.foods);
    if (!n.complete || r.ingredients.isEmpty) continue;
    final meals = switch (r.origin) {
      RecipeOrigin.library => libraryById[r.sourceId]?.meals,
      RecipeOrigin.template => templatesById[r.sourceId]?.meals,
      RecipeOrigin.user || RecipeOrigin.mix => null,
    };
    dishes.add(
      DishCandidate(
        key: 'recipe:${r.id}',
        name: r.name,
        kind: CandidateKind.recipe,
        meals: meals ?? const {MealSlot.lunch, MealSlot.dinner},
        perPortion: n.perPortion,
        maxServingsPerBatch: r.portions,
        keepsDays: r.fridgeDays,
        preference: s.favourites.contains(r.id) ? favouriteWeight : 1,
        favourite: s.favourites.contains(r.id),
        mainProtein: proteinOfRecipe(r),
        contains: {
          'recipe:${r.id}',
          for (final i in r.ingredients) 'food:${i.foodId}',
        },
      ),
    );
  }

  // Library recipes not already in the user's recipes.
  final copied = {
    for (final r in s.recipes)
      if (r.origin == RecipeOrigin.library) r.sourceId,
  };
  for (final r in s.library) {
    if (copied.contains(r.id)) continue;
    final weight = weightOf(r.ingredients, r.cuisine);
    final perPortion = perPortionOf(r, s.libraryFoods);
    if (weight <= 0 || perPortion == null) continue;
    final key = 'library:${r.id}';
    library[key] = r;
    dishes.add(
      DishCandidate(
        key: key,
        name: r.name,
        kind: CandidateKind.library,
        meals: r.meals,
        perPortion: perPortion,
        // Library dishes are scaled to the servings they're cooked for.
        maxServingsPerBatch: 6,
        keepsDays: r.fridgeDays,
        cuisine: r.cuisine,
        preference: weight,
        mainProtein: proteinOfLibrary(r.ingredients, s.libraryFoods),
        contains: containsBasic(r.ingredients, s.libraryFoods),
      ),
    );
  }

  // Dishes made from templates.
  final templates = s.templates;
  if (templates != null) {
    final kcal = {
      for (final e in s.templateFoods.entries) e.key: e.value.per100g.kcal,
    };
    for (final t in templates.templates) {
      // No-cook snacks have no flavours; they get more variants instead, as
      // they're eaten one serving at a time and repeat sooner.
      for (final flavour in t.flavourIds.isEmpty ? [null] : t.flavourIds) {
        final names = <String>{};
        final count = t.noCook ? variants * 3 : variants;
        for (var v = 0; v < count; v++) {
          final result = generateDish(
            t,
            templates.flavours,
            prefs,
            Random(Object.hash(t.id, flavour, v)),
            flavourId: flavour,
          );
          if (result is! GeneratedDish || !names.add(result.name)) continue;
          final recipe = result.toRecipe();
          final perPortion = perPortionOf(recipe, s.templateFoods);
          final weight = weightOf(recipe.ingredients, recipe.cuisine);
          if (perPortion == null || weight <= 0) continue;
          final key = 'template:${t.id}:${flavour ?? 'plain'}:$v';
          generated[key] = (
            dish: result,
            expectedCookedG: result.expectedCookedWeightG(kcal),
          );
          dishes.add(
            DishCandidate(
              key: key,
              name: result.name,
              kind: CandidateKind.template,
              meals: t.meals,
              perPortion: perPortion,
              // Made fresh each time: never batched, never prepped.
              maxServingsPerBatch: t.noCook ? 1 : 6,
              keepsDays: t.fridgeDays,
              cuisine: recipe.cuisine,
              preference: weight,
              mainProtein: proteinOfLibrary(
                recipe.ingredients,
                s.templateFoods,
              ),
              contains: containsBasic(recipe.ingredients, s.templateFoods),
              maxServing: t.noCook ? 1.5 : 1.75,
            ),
          );
        }
      }
    }
  }

  // Rules, with what they add per gram or portion.
  final recipesById = {for (final r in s.recipes) r.id: r};
  final rules = <PlannerRule>[];
  for (final rule in s.rules) {
    if (rule.isRecipe) {
      final r = recipesById[rule.recipeId];
      if (r == null) continue;
      final n = recipeNutrition(r, s.foods);
      if (!n.complete) continue;
      rules.add(
        PlannerRule(
          rule: rule,
          name: r.name,
          perUnit: n.perPortion,
          // A mix (coffee with milk) goes alongside the meal's dish.
          isMeal: r.origin != RecipeOrigin.mix,
        ),
      );
    } else {
      final f = s.foods[rule.foodId];
      if (f == null) continue;
      rules.add(
        PlannerRule(rule: rule, name: f.name, perUnit: perGram(f.per100g)),
      );
    }
  }

  return PlannerCatalogue(
    dishes: dishes,
    rules: rules,
    library: library,
    generated: generated,
  );
}

/// Per-100 g values as per gram, unrounded ([Nutrition.forGrams] rounds to
/// 0.1, which would lose most of a gram's protein).
Nutrition perGram(Nutrition per100g) => Nutrition(
  kcal: per100g.kcal / 100,
  proteinG: per100g.proteinG / 100,
  carbsG: per100g.carbsG / 100,
  fatG: per100g.fatG / 100,
  fibreG: per100g.fibreG / 100,
  fibreUnknown: per100g.fibreUnknown,
);
