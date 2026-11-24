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
  });

  static const double minHeightCm = 100;
  static const double maxHeightCm = 250;

  final Sex sex;
  final int birthYear;
  final double heightCm;
  final ActivityLevel activityLevel;
  final WeightUnit weightUnit;
  final bool useLeanMass;
  final DateTime disclaimerAcceptedAt;

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
  }) => Profile(
    sex: sex ?? this.sex,
    birthYear: birthYear ?? this.birthYear,
    heightCm: heightCm ?? this.heightCm,
    activityLevel: activityLevel ?? this.activityLevel,
    weightUnit: weightUnit ?? this.weightUnit,
    useLeanMass: useLeanMass ?? this.useLeanMass,
    disclaimerAcceptedAt: disclaimerAcceptedAt,
  );
}
