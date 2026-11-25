import 'package:trendline/domain/units.dart';

enum Sex { male, female }

enum ActivityLevel { sedentary, light, moderate, very }

class Profile {
  const new({
    required this.sex,
    required this.birthYear,
    required this.heightCm,
    required this.activityLevel,
    required this.weightUnit,
    required this.disclaimerAcceptedAt,
    this.useLeanMass = false,
    this.strengthTraining = false,
    this.planSnacks = true,
    this.healthScreenedAt,
  });

  static const double minHeightCm = 100;
  static const double maxHeightCm = 250;

  final Sex sex;
  final int birthYear;
  final double heightCm;
  final ActivityLevel activityLevel;
  final WeightUnit weightUnit;
  final bool useLeanMass;

  /// Does regular strength (weights or resistance) training. Raises the
  /// protein target, since training is what builds and keeps muscle.
  final bool strengthTraining;

  /// Whether week plans include a snack each day.
  final bool planSnacks;
  final DateTime disclaimerAcceptedAt;

  /// When the user confirmed that none of the conditions needing medical
  /// supervision apply to them. Null until then. Which condition applied
  /// (if any did) is never stored.
  final DateTime? healthScreenedAt;

  static bool isValidHeight(double cm) =>
      cm >= minHeightCm && cm <= maxHeightCm;

  /// Adults only: the energy formulas used later aren't meant for children.
  static bool isValidBirthYear(int year, {required int currentYear}) =>
      year >= 1900 && year <= currentYear - 18;

  Profile copyWith({
    Sex? sex,
    int? birthYear,
    double? heightCm,
    ActivityLevel? activityLevel,
    WeightUnit? weightUnit,
    bool? useLeanMass,
    bool? strengthTraining,
    bool? planSnacks,
    DateTime? healthScreenedAt,
  }) => Profile(
    sex: sex ?? this.sex,
    birthYear: birthYear ?? this.birthYear,
    heightCm: heightCm ?? this.heightCm,
    activityLevel: activityLevel ?? this.activityLevel,
    weightUnit: weightUnit ?? this.weightUnit,
    useLeanMass: useLeanMass ?? this.useLeanMass,
    strengthTraining: strengthTraining ?? this.strengthTraining,
    planSnacks: planSnacks ?? this.planSnacks,
    disclaimerAcceptedAt: disclaimerAcceptedAt,
    healthScreenedAt: healthScreenedAt ?? this.healthScreenedAt,
  );
}
