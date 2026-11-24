import 'package:trendline/domain/nutrition.dart';

enum FoodSource {
  openFoodFacts,
  manual,

  /// A basic food from CoFID, the UK government's food composition data.
  cofid,
}

/// A saved product. Nutrition is per 100 g.
class Food {
  const new({
    required this.id,
    required this.name,
    required this.per100g,
    required this.source,
    this.brand,
    this.barcode,
    this.sugarG,
    this.saltG,
    this.servingG,
    this.referenceCode,
  });

  final String id;
  final String name;
  final String? brand;
  final String? barcode;
  final Nutrition per100g;
  final double? sugarG;
  final double? saltG;

  /// One serving, if the label gives one (e.g. a sachet or a pot).
  final double? servingG;
  final FoodSource source;

  /// The CoFID code of a basic food this was copied from.
  final String? referenceCode;

  String get displayName => brand == null ? name : '$name · $brand';
}

/// Unsaved food details, e.g. from a search result or the manual entry form.
class FoodDraft {
  const new({
    required this.name,
    required this.per100g,
    required this.source,
    this.brand,
    this.barcode,
    this.sugarG,
    this.saltG,
    this.servingG,
    this.referenceCode,
    this.referenceName,
  });

  final String name;
  final String? brand;
  final String? barcode;
  final Nutrition per100g;
  final double? sugarG;
  final double? saltG;
  final double? servingG;
  final FoodSource source;

  /// The CoFID code, for a basic food. Set exactly when [source] is
  /// [FoodSource.cofid].
  final String? referenceCode;

  /// CoFID's own name for a basic food ([name] is the friendlier one).
  /// With [referenceCode], it identifies the food (codes aren't unique).
  final String? referenceName;
}

enum MealSlot { breakfast, lunch, dinner, snack }

/// One logged portion. Name and nutrition are a snapshot taken when it was
/// logged, so later edits to the food don't change history.
class FoodLogEntry {
  const new({
    required this.id,
    required this.eatenOn,
    required this.eatenAt,
    required this.slot,
    required this.foodName,
    required this.grams,
    required this.nutrition,
    this.foodId,
    this.foodBrand,
    this.recipeId,
  });

  static const double maxGrams = 4999;

  final String id;

  /// The local calendar day it counts towards.
  final DateTime eatenOn;
  final DateTime eatenAt;
  final MealSlot slot;
  final String? foodId;

  /// The recipe it's a portion of, if it is one (then [foodId] is null).
  final String? recipeId;
  final String foodName;
  final String? foodBrand;
  final double grams;
  final Nutrition nutrition;
}
