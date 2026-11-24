import 'package:meta/meta.dart';
import 'package:trendline/domain/recipe_library.dart';

/// How the user feels about an ingredient or cuisine. No preference is
/// neutral. The app never asks why (an allergy would be health data).
enum Preference { like, dislike, never }

/// A basic food by CoFID code and name (codes alone aren't unique).
typedef FoodKey = ({String code, String name});

/// The user's likes, dislikes and nevers.
@immutable
class FoodPreferences {
  const new({this.ingredients = const {}, this.cuisines = const {}});

  static const FoodPreferences none = FoodPreferences();

  final Map<FoodKey, Preference> ingredients;
  final Map<Cuisine, Preference> cuisines;
}

/// How much more (or less) likely a choice is: liked 3x, disliked a quarter
/// as likely, never 0 (excluded).
double preferenceWeight(Preference? p) => switch (p) {
  Preference.like => 3,
  Preference.dislike => 0.25,
  Preference.never => 0,
  null => 1,
};
