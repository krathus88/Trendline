import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';

final today = DateTime(2026, 11, 25);

final male = Profile(
  sex: Sex.male,
  birthYear: 1990,
  heightCm: 180,
  activityLevel: ActivityLevel.light,
  weightUnit: WeightUnit.kg,
  disclaimerAcceptedAt: DateTime(2026),
);
final Profile female = male.copyWith(sex: Sex.female);

GoalPlan resolve(Goal goal, {double trendKg = 100}) =>
    resolveGoal(goal, trendKg: trendKg, today: today);

void main() {
  group('resolveGoal', () {
    test('maintenance plans no loss', () {
      final plan = resolve(Goal.maintenance);
      expect(plan.status, GoalStatus.maintaining);
      expect(plan.kgPerWeek, 0);
    });

    test('target and kg pace: projects the date', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceValue: 0.5,
        ),
      );
      expect(plan.status, GoalStatus.losing);
      expect(plan.kgPerWeek, 0.5);
      expect(plan.cappedByPace, isFalse);
      // 10 kg at 0.5 kg a week = 20 weeks.
      expect(plan.projectedDate, DateTime(2027, 4, 14));
    });

    test('a pace above 1% a week is capped, and the cap is reported', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceValue: 1.5,
        ),
      );
      expect(plan.requestedKgPerWeek, 1.5);
      expect(plan.kgPerWeek, closeTo(1, 1e-9));
      expect(plan.cappedByPace, isTrue);
    });

    test('percent pace converts at the current trend weight', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceMode: PaceMode.percentPerWeek,
          paceValue: 0.5,
        ),
        trendKg: 120,
      );
      expect(plan.kgPerWeek, closeTo(0.6, 1e-9));
    });

    test('percent pace above 1% is capped', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceMode: PaceMode.percentPerWeek,
          paceValue: 2,
        ),
      );
      expect(plan.kgPerWeek, closeTo(1, 1e-9));
      expect(plan.cappedByPace, isTrue);
    });

    test('percent pace takes longer than the same starting kg pace', () {
      const target = 90.0;
      final kg = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: target,
          paceValue: 1,
        ),
      );
      final pct = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: target,
          paceMode: PaceMode.percentPerWeek,
          paceValue: 1,
        ),
      );
      expect(pct.projectedDate!.isAfter(kg.projectedDate!), isTrue);
    });

    test('target and date: derives the pace', () {
      final plan = resolve(
        Goal(
          kind: GoalKind.targetAndDate,
          targetWeightKg: 95,
          goalDate: today.add(const Duration(days: 70)),
        ),
      );
      expect(plan.kgPerWeek, closeTo(0.5, 1e-9));
      expect(plan.projectedDate, DateTime(2027, 2, 3));
    });

    test('target and date too soon: capped, and the date moves later', () {
      final date = today.add(const Duration(days: 14));
      final plan = resolve(
        Goal(kind: GoalKind.targetAndDate, targetWeightKg: 90, goalDate: date),
      );
      expect(plan.requestedKgPerWeek, closeTo(5, 1e-9));
      expect(plan.kgPerWeek, closeTo(1, 1e-9));
      expect(plan.projectedDate!.isAfter(date), isTrue);
    });

    test('pace and date: derives the target', () {
      final plan = resolve(
        Goal(
          kind: GoalKind.paceAndDate,
          paceValue: 0.5,
          goalDate: today.add(const Duration(days: 70)),
        ),
      );
      expect(plan.targetWeightKg, closeTo(95, 1e-9));
    });

    test('a trend at or below the target counts as reached', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 100,
          paceValue: 0.5,
        ),
      );
      expect(plan.status, GoalStatus.reached);
      expect(plan.kgPerWeek, 0);
    });

    test('a target above the trend is reached, not a gain plan', () {
      final plan = resolve(
        Goal(
          kind: GoalKind.targetAndDate,
          targetWeightKg: 110,
          goalDate: today.add(const Duration(days: 70)),
        ),
      );
      expect(plan.status, GoalStatus.reached);
    });

    test('a goal date that has passed means maintenance until changed', () {
      final plan = resolve(
        Goal(
          kind: GoalKind.targetAndDate,
          targetWeightKg: 90,
          goalDate: today.subtract(const Duration(days: 1)),
        ),
      );
      expect(plan.status, GoalStatus.datePassed);
      expect(plan.kgPerWeek, 0);
    });

    test('a pace of zero is maintenance', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceValue: 0,
        ),
      );
      expect(plan.status, GoalStatus.maintaining);
    });
  });

  group('Goal.isComplete', () {
    test('needs the two values its kind fixes', () {
      expect(const Goal(kind: GoalKind.targetAndPace).isComplete, isFalse);
      expect(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceValue: 0.5,
        ).isComplete,
        isTrue,
      );
      expect(
        Goal(kind: GoalKind.paceAndDate, goalDate: today).isComplete,
        isFalse,
      );
      expect(Goal.maintenance.isComplete, isTrue);
    });
  });

  group('computeTargets', () {
    DailyTargets targets({
      Profile? profile,
      double tdee = 2500,
      double bmr = 1800,
      double trendKg = 100,
      double kgPerWeek = 0.5,
      double? leanMassKg,
    }) => computeTargets(
      profile: profile ?? male,
      tdeeKcal: tdee,
      bmrKcal: bmr,
      trendKg: trendKg,
      kgPerWeek: kgPerWeek,
      leanMassKg: leanMassKg,
    );

    test('deficit comes from the pace: 0.5 kg a week is 550 kcal a day', () {
      final t = targets();
      expect(t.kcal, 1950);
      expect(t.limitedByFloor, isFalse);
      expect(t.kgPerWeek, 0.5);
    });

    test('maintenance eats the estimate', () {
      expect(targets(kgPerWeek: 0).kcal, 2500);
    });

    test('never below BMR, and says so', () {
      final t = targets(tdee: 2300, bmr: 1900, kgPerWeek: 1);
      expect(t.kcal, 1900);
      expect(t.limitedByFloor, isTrue);
      expect(t.kgPerWeek, closeTo(400 * 7 / 7700, 1e-9));
    });

    test('never below 1,500 kcal for men', () {
      final t = targets(tdee: 2000, bmr: 1300, kgPerWeek: 1);
      expect(t.kcal, 1500);
      expect(t.limitedByFloor, isTrue);
    });

    test('never below 1,200 kcal for women', () {
      final t = targets(profile: female, tdee: 1700, bmr: 1100, kgPerWeek: 1);
      expect(t.kcal, 1200);
      expect(t.floorKcal, 1200);
    });

    test('an estimate below the floor still targets the floor', () {
      final t = targets(profile: female, tdee: 1100, bmr: 1000, kgPerWeek: 0);
      expect(t.kcal, 1200);
      expect(t.limitedByFloor, isTrue);
      expect(t.kgPerWeek, 0);
    });

    test('rounding never takes calories below the floor', () {
      final t = targets(tdee: 2000, bmr: 1503, kgPerWeek: 1);
      expect(t.kcal, greaterThanOrEqualTo(1503));
    });

    test('macros: protein by body weight, fat floor, carbs the rest', () {
      final t = targets();
      expect(t.proteinG, 150);
      // 25% of 1950 kcal is 54 g, under the 0.6 g/kg minimum of 60 g.
      expect(t.fatG, 60);
      expect(t.carbsG, ((1950 - 600 - 540) / 4).roundToDouble());
      expect(t.fibreG, 30);
    });

    test('protein from lean mass when opted in', () {
      final t = targets(
        profile: male.copyWith(useLeanMass: true),
        leanMassKg: 70,
      );
      expect(t.proteinG, 140);
    });

    test('carbs never go negative', () {
      final t = targets(profile: female, tdee: 1300, bmr: 1000, trendKg: 150);
      expect(t.carbsG, greaterThanOrEqualTo(0));
    });
  });
}
