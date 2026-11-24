import 'package:trendline/domain/profile.dart';

/// Energy in one kilogram of body weight change, in kcal. The usual
/// approximation for mixed fat and lean tissue lost on a diet.
const double kcalPerKg = 7700;

double activityFactor(ActivityLevel level) => switch (level) {
  ActivityLevel.sedentary => 1.2,
  ActivityLevel.light => 1.375,
  ActivityLevel.moderate => 1.55,
  ActivityLevel.very => 1.725,
};

/// Age in whole years on [day]. Only the birth year is stored, so this can be
/// a year high for part of the year; the formulas move about 5 kcal a year.
int ageOn(int birthYear, DateTime day) => day.year - birthYear;

/// Basal metabolic rate by Mifflin-St Jeor, in kcal per day.
double mifflinStJeorBmr({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required int age,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return switch (sex) {
    Sex.male => base + 5,
    Sex.female => base - 161,
  };
}

/// Basal metabolic rate by Katch-McArdle, from lean body mass.
double katchMcArdleBmr(double leanMassKg) => 370 + 21.6 * leanMassKg;

/// BMR for [profile] at [weightKg]. Katch-McArdle only if the user opted in
/// and a lean mass reading exists; otherwise Mifflin-St Jeor.
double estimateBmr(
  Profile profile, {
  required double weightKg,
  required DateTime on,
  double? leanMassKg,
}) {
  if (profile.useLeanMass && leanMassKg != null) {
    return katchMcArdleBmr(leanMassKg);
  }
  return mifflinStJeorBmr(
    sex: profile.sex,
    weightKg: weightKg,
    heightCm: profile.heightCm,
    age: ageOn(profile.birthYear, on),
  );
}

/// Total daily energy expenditure from the formula: BMR times the activity
/// factor. The starting point until logging data takes over.
double formulaTdee(
  Profile profile, {
  required double weightKg,
  required DateTime on,
  double? leanMassKg,
}) =>
    estimateBmr(profile, weightKg: weightKg, on: on, leanMassKg: leanMassKg) *
    activityFactor(profile.activityLevel);
