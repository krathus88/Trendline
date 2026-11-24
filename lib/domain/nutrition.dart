import 'package:meta/meta.dart';

/// Energy and macronutrients. Used both per 100 g (a food) and as an amount
/// (a logged portion or a day's total).
@immutable
class Nutrition {
  const new({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fibreG = 0,
    this.fibreUnknown = false,
  });

  static const Nutrition zero = Nutrition(
    kcal: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
  );

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// The known fibre. With [fibreUnknown], the real amount may be higher.
  final double fibreG;

  /// Whether some or all of the fibre isn't known: a food with no fibre
  /// figure, or a total that includes one. Fibre is optional on UK labels.
  final bool fibreUnknown;

  /// The nutrition in [grams] of a food whose per-100 g values are `this`,
  /// rounded to one decimal (what's stored in the food log).
  Nutrition forGrams(double grams) {
    final f = grams / 100;
    return Nutrition(
      kcal: _round1(kcal * f),
      proteinG: _round1(proteinG * f),
      carbsG: _round1(carbsG * f),
      fatG: _round1(fatG * f),
      fibreG: _round1(fibreG * f),
      fibreUnknown: fibreUnknown,
    );
  }

  Nutrition operator +(Nutrition other) => Nutrition(
    kcal: kcal + other.kcal,
    proteinG: proteinG + other.proteinG,
    carbsG: carbsG + other.carbsG,
    fatG: fatG + other.fatG,
    fibreG: fibreG + other.fibreG,
    fibreUnknown: fibreUnknown || other.fibreUnknown,
  );

  static Nutrition sum(Iterable<Nutrition> items) =>
      items.fold(zero, (total, n) => total + n);

  @override
  bool operator ==(Object other) =>
      other is Nutrition &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbsG == carbsG &&
      other.fatG == fatG &&
      other.fibreG == fibreG &&
      other.fibreUnknown == fibreUnknown;

  @override
  int get hashCode =>
      Object.hash(kcal, proteinG, carbsG, fatG, fibreG, fibreUnknown);

  @override
  String toString() =>
      'Nutrition(${kcal}kcal, P$proteinG C$carbsG F$fatG '
      'Fi$fibreG${fibreUnknown ? '+?' : ''})';
}

double _round1(double v) => (v * 10).round() / 10;

/// Checks per-100 g values against physical limits, matching the database
/// constraints. Returns a problem description, or null if they're plausible.
String? validatePer100g(Nutrition n) {
  final values = [n.kcal, n.proteinG, n.carbsG, n.fatG, n.fibreG];
  if (values.any((v) => v.isNaN || v.isInfinite || v < 0)) {
    return 'Values must be zero or more.';
  }
  if (n.kcal > 900) return 'Energy can’t be more than 900 kcal per 100 g.';
  if ([n.proteinG, n.carbsG, n.fatG, n.fibreG].any((v) => v > 100)) {
    return 'No nutrient can be more than 100 g per 100 g.';
  }
  if (n.proteinG + n.carbsG + n.fatG + n.fibreG > 105) {
    return 'Protein, carbs, fat and fibre add up to more than 100 g.';
  }
  return null;
}
