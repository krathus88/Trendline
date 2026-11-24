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

  group('resolveGoal: gaining', () {
    test('target and pace: gains towards the target', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          direction: GoalDirection.gain,
          targetWeightKg: 105,
          paceValue: 0.25,
        ),
      );
      expect(plan.status, GoalStatus.gaining);
      expect(plan.weeklyChangeKg, 0.25);
      // 5 kg at 0.25 kg a week = 20 weeks.
      expect(plan.projectedDate, DateTime(2027, 4, 14));
    });

    test('gaining is capped at 0.5% a week', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          direction: GoalDirection.gain,
          targetWeightKg: 110,
          paceValue: 1,
        ),
      );
      expect(plan.kgPerWeek, closeTo(0.5, 1e-9));
      expect(plan.cappedByPace, isTrue);
    });

    test('a percent gain pace grows with the weight', () {
      final kg = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          direction: GoalDirection.gain,
          targetWeightKg: 110,
          paceValue: 0.5,
        ),
      );
      final pct = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          direction: GoalDirection.gain,
          targetWeightKg: 110,
          paceMode: PaceMode.percentPerWeek,
          paceValue: 0.5,
        ),
      );
      expect(pct.kgPerWeek, closeTo(kg.kgPerWeek, 1e-9));
      expect(pct.projectedDate!.isBefore(kg.projectedDate!), isTrue);
    });

    test('target and date: derives the gain pace', () {
      final plan = resolve(
        Goal(
          kind: GoalKind.targetAndDate,
          direction: GoalDirection.gain,
          targetWeightKg: 102,
          goalDate: today.add(const Duration(days: 56)),
        ),
      );
      expect(plan.weeklyChangeKg, closeTo(0.25, 1e-9));
    });

    test('pace and date: derives a higher target', () {
      final plan = resolve(
        Goal(
          kind: GoalKind.paceAndDate,
          direction: GoalDirection.gain,
          paceValue: 0.25,
          goalDate: today.add(const Duration(days: 70)),
        ),
      );
      expect(plan.targetWeightKg, closeTo(102.5, 1e-9));
    });

    test('a trend at or above a gain target counts as reached', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          direction: GoalDirection.gain,
          targetWeightKg: 98,
          paceValue: 0.25,
        ),
      );
      expect(plan.status, GoalStatus.reached);
      expect(plan.weeklyChangeKg, 0);
    });

    test('overshooting a loss target is reached, not a gain plan', () {
      final plan = resolve(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 101,
          paceValue: 0.5,
        ),
      );
      expect(plan.status, GoalStatus.reached);
    });
  });

  group('proteinWeightKg', () {
    test('is the actual weight up to a BMI of 25', () {
      expect(proteinWeightKg(70, 180), 70);
      expect(proteinWeightKg(81, 180), closeTo(81, 1e-9));
    });

    test('above BMI 25, counts only a quarter of the excess', () {
      // 180 cm: BMI 25 is 81 kg. 150 kg -> 81 + 0.25 * 69 = 98.25 kg.
      expect(proteinWeightKg(150, 180), closeTo(98.25, 1e-9));
    });
  });

  group('protein per kg', () {
    test('losing protects muscle by default, more with training', () {
      expect(
        proteinPerKgBodyWeight(weeklyChangeKg: -0.5, strengthTraining: false),
        1.6,
      );
      expect(
        proteinPerKgBodyWeight(weeklyChangeKg: -0.5, strengthTraining: true),
        2.0,
      );
    });

    test('maintaining: 1.2, or 1.6 with training', () {
      expect(
        proteinPerKgBodyWeight(weeklyChangeKg: 0, strengthTraining: false),
        1.2,
      );
      expect(
        proteinPerKgBodyWeight(weeklyChangeKg: 0, strengthTraining: true),
        1.6,
      );
    });

    test('gaining aims for muscle either way', () {
      expect(
        proteinPerKgBodyWeight(weeklyChangeKg: 0.25, strengthTraining: false),
        1.6,
      );
    });

    test('per kg of lean mass is higher, as lean mass is less than weight', () {
      for (final change in [-0.5, 0.0, 0.25]) {
        for (final training in [false, true]) {
          expect(
            proteinPerKgLeanMass(
              weeklyChangeKg: change,
              strengthTraining: training,
            ),
            greaterThan(
              proteinPerKgBodyWeight(
                weeklyChangeKg: change,
                strengthTraining: training,
              ),
            ),
          );
        }
      }
    });
  });

  group('computeTargets', () {
    DailyTargets targets({
      Profile? profile,
      double tdee = 2500,
      double bmr = 1800,
      double trendKg = 75,
      double change = -0.5,
      double? leanMassKg,
    }) => computeTargets(
      profile: profile ?? male,
      tdeeKcal: tdee,
      bmrKcal: bmr,
      trendKg: trendKg,
      weeklyChangeKg: change,
      leanMassKg: leanMassKg,
    );

    test('deficit comes from the pace: 0.5 kg a week is 550 kcal a day', () {
      final t = targets();
      expect(t.kcal, 1950);
      expect(t.limitedByFloor, isFalse);
      expect(t.weeklyChangeKg, -0.5);
    });

    test('surplus for gaining: 0.25 kg a week is 275 kcal a day', () {
      final t = targets(change: 0.25);
      expect(t.kcal, 2780);
      expect(t.weeklyChangeKg, 0.25);
      expect(t.limitedByFloor, isFalse);
    });

    test('maintenance eats the estimate', () {
      expect(targets(change: 0).kcal, 2500);
    });

    test('never below BMR, and says so', () {
      final t = targets(tdee: 2300, bmr: 1900, change: -1);
      expect(t.kcal, 1900);
      expect(t.limitedByFloor, isTrue);
      expect(t.weeklyChangeKg, closeTo(-400 * 7 / 7700, 1e-9));
    });

    test('never below 1,500 kcal for men', () {
      final t = targets(tdee: 2000, bmr: 1300, change: -1);
      expect(t.kcal, 1500);
      expect(t.limitedByFloor, isTrue);
    });

    test('never below 1,200 kcal for women', () {
      final t = targets(profile: female, tdee: 1700, bmr: 1100, change: -1);
      expect(t.kcal, 1200);
      expect(t.floorKcal, 1200);
    });

    test('an estimate below the floor targets the floor, and says so', () {
      final t = targets(profile: female, tdee: 1100, bmr: 1000, change: 0);
      expect(t.kcal, 1200);
      expect(t.limitedByFloor, isTrue);
      expect(t.weeklyChangeKg, greaterThan(0));
    });

    test('rounding never takes calories below the floor', () {
      final t = targets(tdee: 2000, bmr: 1503, change: -1);
      expect(t.kcal, greaterThanOrEqualTo(1503));
    });

    test('losing at a healthy weight: 1.6 g/kg, fat 30%, carbs the rest', () {
      final t = targets();
      expect(t.proteinG, 120, reason: '1.6 g/kg of 75 kg');
      expect(t.proteinBasis, ProteinBasis.bodyWeight);
      expect(t.fatG, 65, reason: '30% of 1950 kcal');
      expect(t.carbsG, ((1950 - 480 - 585) / 4).roundToDouble());
      expect(t.fibreG, 30);
    });

    test('strength training raises protein when losing', () {
      final t = targets(profile: male.copyWith(strengthTraining: true));
      expect(t.proteinG, 150, reason: '2.0 g/kg of 75 kg');
    });

    test('a high weight uses the adjusted weight, not the full weight', () {
      final t = targets(trendKg: 150, tdee: 3200, bmr: 2300);
      // 1.6 * 98.25 kg = 157 g, not 1.6 * 150 = 240 g.
      expect(t.proteinG, 157);
    });

    test('lean mass from the scale is used when known', () {
      final t = targets(trendKg: 100, leanMassKg: 80);
      expect(t.proteinBasis, ProteinBasis.leanMass);
      expect(t.proteinG, 160, reason: '2.0 g/kg of 80 kg lean mass');
    });

    test('a muscular build is not penalised by BMI', () {
      // 100 kg at 180 cm is BMI 31, but with 85 kg of lean mass.
      final byWeight = targets(trendKg: 100);
      final byLean = targets(trendKg: 100, leanMassKg: 85);
      expect(byLean.proteinG, greaterThan(byWeight.proteinG));
    });

    test('never below 60 g of protein', () {
      final t = targets(profile: female, trendKg: 40, tdee: 1500, bmr: 1100);
      expect(t.proteinG, 64, reason: '1.6 * 40 = 64');
      final small = targets(
        profile: female,
        trendKg: 35,
        tdee: 1400,
        bmr: 1050,
        change: 0,
      );
      expect(small.proteinG, 60, reason: '1.2 * 35 = 42, raised to 60');
    });

    test('fat is always 30% of calories', () {
      for (final kcal in [1500.0, 2200.0, 3200.0]) {
        final t = targets(tdee: kcal, bmr: 1000, change: 0);
        expect(t.fatG, (t.kcal * 0.3 / 9).roundToDouble());
      }
    });

    test('carbs never go negative', () {
      final t = targets(
        profile: female.copyWith(strengthTraining: true),
        leanMassKg: 120,
        trendKg: 140,
        tdee: 1300,
        bmr: 1000,
      );
      expect(t.carbsG, greaterThanOrEqualTo(0));
    });
  });

  group('outlookFor', () {
    GoalOutlook outlook(Goal goal, {double tdee = 2500}) => outlookFor(
      goal: goal,
      profile: male,
      tdeeKcal: tdee,
      bmrKcal: 1800,
      trendKg: 100,
      today: today,
    );

    test('projects the date at the planned pace', () {
      final o = outlook(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceValue: 0.5,
        ),
      );
      expect(o.adjusted, isFalse);
      expect(o.projectedDate, DateTime(2027, 4, 14));
    });

    test('a floor-limited pace pushes the date later', () {
      final o = outlook(
        const Goal(
          kind: GoalKind.targetAndPace,
          targetWeightKg: 90,
          paceValue: 1,
        ),
        tdee: 2000,
      );
      expect(o.adjusted, isTrue);
      expect(o.projectedDate!.isAfter(DateTime(2027, 2, 3)), isTrue);
    });

    test('no date when nothing changes', () {
      expect(outlook(Goal.maintenance).projectedDate, isNull);
    });
  });
}
