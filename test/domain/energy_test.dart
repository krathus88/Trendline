import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/energy.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';

final profile = Profile(
  sex: Sex.male,
  birthYear: 1990,
  heightCm: 180,
  activityLevel: ActivityLevel.light,
  weightUnit: WeightUnit.kg,
  disclaimerAcceptedAt: DateTime(2026),
);

void main() {
  final on = DateTime(2026, 11, 25);

  test('Mifflin-St Jeor matches the published formula', () {
    // 10*90 + 6.25*180 - 5*36 + 5 = 1850
    expect(
      mifflinStJeorBmr(sex: Sex.male, weightKg: 90, heightCm: 180, age: 36),
      1850,
    );
    // Same body, female: -161 instead of +5.
    expect(
      mifflinStJeorBmr(sex: Sex.female, weightKg: 90, heightCm: 180, age: 36),
      1684,
    );
  });

  test('Katch-McArdle uses lean mass only', () {
    expect(katchMcArdleBmr(70), closeTo(1882, 1e-9));
  });

  test('age is counted from the birth year', () {
    expect(ageOn(1990, on), 36);
  });

  test('uses Katch-McArdle only when opted in and lean mass is known', () {
    expect(estimateBmr(profile, weightKg: 90, on: on, leanMassKg: 70), 1850);
    final optedIn = profile.copyWith(useLeanMass: true);
    expect(
      estimateBmr(optedIn, weightKg: 90, on: on, leanMassKg: 70),
      closeTo(1882, 1e-9),
    );
    expect(estimateBmr(optedIn, weightKg: 90, on: on), 1850);
  });

  test('formula TDEE is BMR times the activity factor', () {
    expect(formulaTdee(profile, weightKg: 90, on: on), closeTo(2543.75, 1e-9));
  });

  test('activity factors rise with activity', () {
    final factors = ActivityLevel.values.map(activityFactor).toList();
    expect(factors, [1.2, 1.375, 1.55, 1.725]);
  });
}
