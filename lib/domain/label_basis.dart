import 'package:trendline/domain/nutrition.dart';

/// What the numbers on a nutrition label are given per. Foods are always
/// stored per 100 g of the food itself, so labels on another basis are
/// converted with [labelFactor].
enum LabelBasis {
  /// Per 100 g, or per 100 ml for a drink (1 ml is taken as 1 g).
  per100g,

  /// Per serving (one sachet, one bar), with the serving's weight.
  perServing,

  /// Per 100 ml of the food made up with water (a sachet drink, stock,
  /// squash), with the dry serving's weight and how much one serving makes.
  /// Water adds nothing, so one serving's nutrition is the label value for
  /// the volume it makes.
  per100mlMadeUp,
}

/// What to multiply the label's values by to get per 100 g of the food, or
/// null while a needed amount is missing or impossible.
///
/// * per serving: 100 / [servingG];
/// * per 100 ml made up: one serving is [makesMl] / 100 of the label values,
///   so per 100 g of the dry food it's [makesMl] / [servingG].
double? labelFactor(LabelBasis basis, {double? servingG, double? makesMl}) {
  bool ok(double? v) => v != null && v.isFinite && v > 0;
  return switch (basis) {
    LabelBasis.per100g => 1,
    LabelBasis.perServing => ok(servingG) ? 100 / servingG! : null,
    LabelBasis.per100mlMadeUp =>
      ok(servingG) && ok(makesMl) ? makesMl! / servingG! : null,
  };
}

/// [label] values (as printed) converted to per 100 g with [factor].
Nutrition labelToPer100g(Nutrition label, double factor) => Nutrition(
  kcal: label.kcal * factor,
  proteinG: label.proteinG * factor,
  carbsG: label.carbsG * factor,
  fatG: label.fatG * factor,
  fibreG: label.fibreG * factor,
  fibreUnknown: label.fibreUnknown,
);
