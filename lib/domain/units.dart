/// How weights are shown. Storage is always kilograms.
enum WeightUnit { kg, lb, stLb }

const double kgPerLb = 0.45359237;
const int lbPerStone = 14;

double kgToLb(double kg) => kg / kgPerLb;

double lbToKg(double lb) => lb * kgPerLb;

double stLbToKg(int stones, double pounds) =>
    lbToKg(stones * lbPerStone + pounds);

/// Splits [kg] into stones and pounds, with pounds rounded to one decimal.
/// Rounding happens before the split, so 13.96 lb becomes the next stone
/// rather than "13 st 14.0 lb".
({int stones, double pounds}) kgToStLb(double kg) {
  final totalLb = (kgToLb(kg) * 10).round() / 10;
  final stones = totalLb ~/ lbPerStone;
  final pounds = ((totalLb - stones * lbPerStone) * 10).round() / 10;
  return (stones: stones, pounds: pounds);
}

/// A weight for display, e.g. "82.4 kg", "181.7 lb" or "12 st 13.7 lb".
String formatWeight(double kg, WeightUnit unit) {
  switch (unit) {
    case WeightUnit.kg:
      return '${kg.toStringAsFixed(1)} kg';
    case WeightUnit.lb:
      return '${kgToLb(kg).toStringAsFixed(1)} lb';
    case WeightUnit.stLb:
      final (:stones, :pounds) = kgToStLb(kg);
      return '$stones st ${pounds.toStringAsFixed(1)} lb';
  }
}

/// A signed weight change for display, e.g. "−0.6 kg" or "+1.2 lb". Stones
/// users see pounds: a weekly change is rarely more than a few pounds.
String formatWeightChange(double kg, WeightUnit unit) {
  final value = unit == WeightUnit.kg ? kg : kgToLb(kg);
  final suffix = unit == WeightUnit.kg ? 'kg' : 'lb';
  final rounded = (value * 10).round() / 10;
  if (rounded == 0) return '0.0 $suffix';
  // A true minus sign reads better than a hyphen next to numbers.
  final sign = rounded < 0 ? '−' : '+';
  return '$sign${rounded.abs().toStringAsFixed(1)} $suffix';
}
