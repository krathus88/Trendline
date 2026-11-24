import 'package:trendline/domain/nutrition.dart';

enum FoodSource { openFoodFacts, manual }

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
  });

  final String name;
  final String? brand;
  final String? barcode;
  final Nutrition per100g;
  final double? sugarG;
  final double? saltG;
  final double? servingG;
  final FoodSource source;
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
  });

  static const double maxGrams = 4999;

  final String id;

  /// The local calendar day it counts towards.
  final DateTime eatenOn;
  final DateTime eatenAt;
  final MealSlot slot;
  final String? foodId;
  final String foodName;
  final String? foodBrand;
  final double grams;
  final Nutrition nutrition;
}
