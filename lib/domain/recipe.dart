import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';

/// One ingredient: raw grams of one of the user's foods.
@immutable
class RecipeIngredient {
  const new({required this.foodId, required this.rawGrams});

  static const double maxGrams = 4999;

  final String foodId;
  final double rawGrams;

  @override
  bool operator ==(Object other) =>
      other is RecipeIngredient &&
      other.foodId == foodId &&
      other.rawGrams == rawGrams;

  @override
  int get hashCode => Object.hash(foodId, rawGrams);
}

/// Where a recipe came from.
enum RecipeOrigin { user, library, template }

/// A batch-cookable recipe. Portions are eaten in cooked grams, measured
/// against the batch's [cookedWeightG] once the user has weighed it.
@immutable
class Recipe {
  const new({
    required this.id,
    required this.name,
    required this.ingredients,
    this.portions = 4,
    this.cookedWeightG,
    this.fridgeDays = 3,
    this.freezable = true,
    this.method,
    this.origin = RecipeOrigin.user,
    this.sourceId,
    this.sourceVersion,
  });

  static const int maxPortions = 50;
  static const double maxCookedWeightG = 50000;
  static const int maxFridgeDays = 7;

  final String id;
  final String name;
  final List<RecipeIngredient> ingredients;
  final int portions;

  /// The whole batch after cooking. Null until it's been weighed.
  final double? cookedWeightG;
  final int fridgeDays;
  final bool freezable;

  /// Cooking steps, optional.
  final String? method;

  final RecipeOrigin origin;

  /// The library recipe or template it was copied from, and its version.
  final String? sourceId;
  final int? sourceVersion;

  double get rawWeightG => ingredients.fold(0, (sum, i) => sum + i.rawGrams);

  /// One portion's cooked weight, once the batch has been weighed.
  double? get portionG =>
      cookedWeightG == null ? null : cookedWeightG! / portions;
}

/// What a recipe adds up to, worked out from its ingredients' foods.
@immutable
class RecipeNutrition {
  const new({
    required this.batch,
    required this.perPortion,
    required this.missingFoods,
    this.per100gCooked,
  });

  /// The whole batch.
  final Nutrition batch;

  /// Batch / portions.
  final Nutrition perPortion;

  /// Per 100 g as eaten, once the cooked weight is known.
  final Nutrition? per100gCooked;

  /// Ingredients whose food can't be found (for example, not loaded yet).
  /// While any are missing, the totals are incomplete.
  final int missingFoods;

  bool get complete => missingFoods == 0;
}

/// Adds up [recipe] from [foods] (the user's foods by ID).
RecipeNutrition recipeNutrition(Recipe recipe, Map<String, Food> foods) {
  var batch = Nutrition.zero;
  var missing = 0;
  for (final ingredient in recipe.ingredients) {
    final food = foods[ingredient.foodId];
    if (food == null) {
      missing++;
      continue;
    }
    batch += food.per100g.forGrams(ingredient.rawGrams);
  }
  final cooked = recipe.cookedWeightG;
  return RecipeNutrition(
    batch: batch,
    perPortion: _scale(batch, 1 / recipe.portions),
    per100gCooked: cooked == null || cooked <= 0
        ? null
        : _scale(batch, 100 / cooked),
    missingFoods: missing,
  );
}

Nutrition _scale(Nutrition n, double f) => Nutrition(
  kcal: n.kcal * f,
  proteinG: n.proteinG * f,
  carbsG: n.carbsG * f,
  fatG: n.fatG * f,
  fibreG: n.fibreG * f,
  fibreUnknown: n.fibreUnknown,
);

/// Problems that stop a recipe being saved, or null if it's fine. Matches
/// the database checks.
String? validateRecipe(Recipe recipe) {
  if (recipe.name.trim().isEmpty) return 'Give the recipe a name.';
  if (recipe.name.trim().length > 200) return 'That name is too long.';
  if (recipe.ingredients.isEmpty) return 'Add at least one ingredient.';
  if (recipe.ingredients.length > 200) return 'That’s too many ingredients.';
  if (recipe.ingredients.any(
    (i) =>
        i.rawGrams.isNaN ||
        i.rawGrams <= 0 ||
        i.rawGrams > RecipeIngredient.maxGrams,
  )) {
    return 'Each ingredient needs an amount up to 4999 g.';
  }
  if (recipe.portions < 1 || recipe.portions > Recipe.maxPortions) {
    return 'Portions must be between 1 and ${Recipe.maxPortions}.';
  }
  final cooked = recipe.cookedWeightG;
  if (cooked != null &&
      (cooked.isNaN || cooked <= 0 || cooked > Recipe.maxCookedWeightG)) {
    return 'The cooked weight must be more than 0 g and at most 50 kg.';
  }
  if (recipe.fridgeDays < 0 || recipe.fridgeDays > Recipe.maxFridgeDays) {
    return 'Fridge days must be between 0 and ${Recipe.maxFridgeDays}.';
  }
  return null;
}

/// A gentle check on the cooked weight: cooking usually changes weight by
/// well under 4x (rice and pasta gain water, meat loses some). Returns a
/// warning to show, not a reason to refuse.
String? cookedWeightWarning(Recipe recipe) {
  final cooked = recipe.cookedWeightG;
  final raw = recipe.rawWeightG;
  if (cooked == null || raw <= 0) return null;
  final ratio = cooked / raw;
  if (ratio < 0.3) {
    return 'That’s under a third of the raw weight. Did you leave the '
        'pot’s weight out twice?';
  }
  if (ratio > 4) {
    return 'That’s over four times the raw weight. Did you include the '
        'pot?';
  }
  return null;
}
