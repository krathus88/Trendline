import 'dart:math';

import 'package:meta/meta.dart';
import 'package:trendline/domain/recipe_library.dart';

/// How the user feels about an ingredient or cuisine. No preference is
/// neutral. The app never asks why (an allergy would be health data).
enum Preference { like, dislike, never }

/// A basic food by CoFID code and name (codes alone aren't unique).
typedef FoodKey = ({String code, String name});

/// The user's likes, dislikes and nevers, or a household's combined.
@immutable
class FoodPreferences {
  const new({
    this.ingredients = const {},
    this.cuisines = const {},
    this.ingredientWeights = const {},
    this.cuisineWeights = const {},
  });

  /// A household's preferences, from how many of its members like,
  /// dislike or never want each food and cuisine ([counts]). Anything
  /// someone never wants is left out for everyone; otherwise each member's
  /// weight counts equally (a geometric mean over all members, those
  /// without a preference counting as neutral), so one member's like and
  /// another's dislike roughly cancel out.
  factory combined(Iterable<HouseholdPreference> counts) {
    final ingredients = <FoodKey, Preference>{};
    final cuisines = <Cuisine, Preference>{};
    final ingredientWeights = <FoodKey, double>{};
    final cuisineWeights = <Cuisine, double>{};
    for (final c in counts) {
      final never = c.nevers > 0;
      final weight = never ? 0.0 : c.weight;
      switch (c.target) {
        case final Cuisine cuisine:
          if (never) cuisines[cuisine] = Preference.never;
          cuisineWeights[cuisine] = weight;
        case final FoodKey food:
          if (never) ingredients[food] = Preference.never;
          ingredientWeights[food] = weight;
      }
    }
    return FoodPreferences(
      ingredients: ingredients,
      cuisines: cuisines,
      ingredientWeights: ingredientWeights,
      cuisineWeights: cuisineWeights,
    );
  }

  static const FoodPreferences none = FoodPreferences();

  final Map<FoodKey, Preference> ingredients;
  final Map<Cuisine, Preference> cuisines;

  /// Weights that replace [preferenceWeight] for these foods and cuisines
  /// (a household's combined preferences).
  final Map<FoodKey, double> ingredientWeights;
  final Map<Cuisine, double> cuisineWeights;

  /// How much more (or less) likely [food] is to be chosen; 0 excludes it.
  double ingredientWeight(FoodKey food) =>
      ingredientWeights[food] ?? preferenceWeight(ingredients[food]);

  /// How much more (or less) likely [cuisine] is to be chosen; 0 excludes
  /// it.
  double cuisineWeight(Cuisine cuisine) =>
      cuisineWeights[cuisine] ?? preferenceWeight(cuisines[cuisine]);

  bool isNever(FoodKey food) => ingredients[food] == Preference.never;
}

/// How many of a household's [members] like, dislike or never want one
/// food or cuisine ([target]: a [FoodKey] or a [Cuisine]). Says nothing
/// about who.
@immutable
class HouseholdPreference {
  const new({
    required this.target,
    required this.members,
    this.likes = 0,
    this.dislikes = 0,
    this.nevers = 0,
  });

  final Object target;
  final int likes;
  final int dislikes;
  final int nevers;
  final int members;

  /// The geometric mean of the members' weights (see [preferenceWeight]).
  double get weight {
    final n = max(members, likes + dislikes + nevers);
    if (n == 0) return 1;
    return exp(
      (likes * log(preferenceWeight(Preference.like)) +
              dislikes * log(preferenceWeight(Preference.dislike))) /
          n,
    );
  }
}

/// How much more (or less) likely a choice is: liked 3x, disliked a quarter
/// as likely, never 0 (excluded).
double preferenceWeight(Preference? p) => switch (p) {
  Preference.like => 3,
  Preference.dislike => 0.25,
  Preference.never => 0,
  null => 1,
};
