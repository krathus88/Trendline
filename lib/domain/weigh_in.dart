enum WeighInSource { manual, healthConnect }

/// One scale reading.
class WeighIn {
  const new({
    required this.id,
    required this.measuredAt,
    required this.weightKg,
    this.bodyFatPct,
    this.leanMassKg,
    this.source = WeighInSource.manual,
  });

  /// Valid ranges, matching the database constraints.
  static const double minWeightKg = 25;
  static const double maxWeightKg = 400;
  static const double minBodyFatPct = 2;
  static const double maxBodyFatPct = 75;

  final String id;
  final DateTime measuredAt;
  final double weightKg;
  final double? bodyFatPct;
  final double? leanMassKg;
  final WeighInSource source;

  static bool isValidWeight(double kg) =>
      kg >= minWeightKg && kg <= maxWeightKg;

  static bool isValidBodyFat(double pct) =>
      pct >= minBodyFatPct && pct <= maxBodyFatPct;
}
