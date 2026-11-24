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
    this.externalId,
  });

  /// Valid ranges, matching the database constraints.
  static const double minWeightKg = 25;
  static const double maxWeightKg = 400;
  static const double minBodyFatPct = 2;
  static const double maxBodyFatPct = 75;
  static const double minLeanMassKg = 10;
  static const double maxLeanMassKg = 200;

  final String id;
  final DateTime measuredAt;
  final double weightKg;
  final double? bodyFatPct;
  final double? leanMassKg;
  final WeighInSource source;

  /// The source system's record ID; null for manual weigh-ins.
  final String? externalId;

  static bool isValidWeight(double kg) =>
      kg >= minWeightKg && kg <= maxWeightKg;

  static bool isValidBodyFat(double pct) =>
      pct >= minBodyFatPct && pct <= maxBodyFatPct;

  static bool isValidLeanMass(double kg, {required double weightKg}) =>
      kg >= minLeanMassKg && kg <= maxLeanMassKg && kg < weightKg;
}
