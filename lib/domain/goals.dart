import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/energy.dart';
import 'package:trendline/domain/profile.dart';

/// How the weekly pace is expressed.
enum PaceMode {
  /// A fixed amount each week.
  kgPerWeek,

  /// A share of current body weight each week, so it shrinks as weight drops.
  percentPerWeek,
}

/// Which two of target weight, pace and date the user fixed. The third is
/// worked out.
enum GoalKind { targetAndPace, targetAndDate, paceAndDate, maintain }

/// The fastest planned loss: 1% of current body weight per week.
const double maxPacePercent = 1;

/// Minimum daily calories regardless of the estimate.
double calorieFloor(Sex sex) => switch (sex) {
  Sex.male => 1500,
  Sex.female => 1200,
};

/// UK guidance for adults.
const double fibreTargetG = 30;

/// A goal as the user set it. Each kind stores only its two values.
@immutable
class Goal {
  const new({
    required this.kind,
    this.targetWeightKg,
    this.paceMode = PaceMode.kgPerWeek,
    this.paceValue,
    this.goalDate,
  });

  static const maintenance = Goal(kind: GoalKind.maintain);

  final GoalKind kind;
  final double? targetWeightKg;
  final PaceMode paceMode;

  /// kg per week, or percent of body weight per week (1 = 1%).
  final double? paceValue;

  /// Local calendar day.
  final DateTime? goalDate;

  /// Whether the values this kind needs are present and in range.
  bool get isComplete => switch (kind) {
    GoalKind.targetAndPace => targetWeightKg != null && _paceOk,
    GoalKind.targetAndDate => targetWeightKg != null && goalDate != null,
    GoalKind.paceAndDate => _paceOk && goalDate != null,
    GoalKind.maintain => true,
  };

  bool get _paceOk => paceValue != null && paceValue! >= 0;
}

enum GoalStatus {
  /// Losing towards the target or date.
  losing,

  /// Maintenance chosen, or a pace of zero.
  maintaining,

  /// The trend is at or below the target weight.
  reached,

  /// A goal date that has passed: maintaining until a new one is set.
  datePassed,
}

/// The goal worked out for today, from the current trend weight.
@immutable
class GoalPlan {
  const new({
    required this.status,
    required this.requestedKgPerWeek,
    required this.kgPerWeek,
    this.targetWeightKg,
    this.projectedDate,
  });

  final GoalStatus status;

  /// What the goal asks for this week.
  final double requestedKgPerWeek;

  /// What will be planned: [requestedKgPerWeek] limited by the 1% cap.
  final double kgPerWeek;

  /// Set or derived (pace and date goals derive it).
  final double? targetWeightKg;

  /// When the target is reached at [kgPerWeek]. Null without a target.
  final DateTime? projectedDate;

  bool get cappedByPace => kgPerWeek < requestedKgPerWeek - 1e-9;
}

/// Works out today's weekly pace for [goal] from the trend weight.
///
/// Never plans more than [maxPacePercent] of [trendKg] a week; when the goal
/// asks for more, [GoalPlan.cappedByPace] says so, and the projected date
/// moves later. Only losing or maintaining is planned: a target above the
/// current trend counts as reached.
GoalPlan resolveGoal(
  Goal goal, {
  required double trendKg,
  required DateTime today,
}) {
  final day = dayOf(today);
  final capKg = trendKg * maxPacePercent / 100;
  const maintaining = GoalPlan(
    status: GoalStatus.maintaining,
    requestedKgPerWeek: 0,
    kgPerWeek: 0,
  );

  switch (goal.kind) {
    case GoalKind.maintain:
      return maintaining;

    case GoalKind.targetAndPace:
      final target = goal.targetWeightKg!;
      if (trendKg <= target) return _reached(target);
      final requested = paceKgPerWeek(goal.paceMode, goal.paceValue!, trendKg);
      if (requested <= 0) {
        return GoalPlan(
          status: GoalStatus.maintaining,
          requestedKgPerWeek: 0,
          kgPerWeek: 0,
          targetWeightKg: target,
        );
      }
      final kg = math.min(requested, capKg);
      return GoalPlan(
        status: GoalStatus.losing,
        requestedKgPerWeek: requested,
        kgPerWeek: kg,
        targetWeightKg: target,
        projectedDate: projectDate(
          trendKg: trendKg,
          targetKg: target,
          mode: goal.paceMode,
          kgPerWeekNow: kg,
          from: day,
        ),
      );

    case GoalKind.targetAndDate:
      final target = goal.targetWeightKg!;
      if (trendKg <= target) return _reached(target);
      final daysLeft = daysBetween(day, goal.goalDate!);
      if (daysLeft <= 0) {
        return GoalPlan(
          status: GoalStatus.datePassed,
          requestedKgPerWeek: 0,
          kgPerWeek: 0,
          targetWeightKg: target,
        );
      }
      final requested = (trendKg - target) / (daysLeft / 7);
      final kg = math.min(requested, capKg);
      return GoalPlan(
        status: GoalStatus.losing,
        requestedKgPerWeek: requested,
        kgPerWeek: kg,
        targetWeightKg: target,
        projectedDate: kg < requested
            ? projectDate(
                trendKg: trendKg,
                targetKg: target,
                mode: PaceMode.kgPerWeek,
                kgPerWeekNow: kg,
                from: day,
              )
            : dayOf(goal.goalDate!),
      );

    case GoalKind.paceAndDate:
      final daysLeft = daysBetween(day, goal.goalDate!);
      if (daysLeft <= 0) {
        return const GoalPlan(
          status: GoalStatus.datePassed,
          requestedKgPerWeek: 0,
          kgPerWeek: 0,
        );
      }
      final requested = paceKgPerWeek(goal.paceMode, goal.paceValue!, trendKg);
      if (requested <= 0) return maintaining;
      final kg = math.min(requested, capKg);
      final weeks = daysLeft / 7;
      final target = switch (goal.paceMode) {
        PaceMode.kgPerWeek => trendKg - kg * weeks,
        PaceMode.percentPerWeek => trendKg * math.pow(1 - kg / trendKg, weeks),
      };
      return GoalPlan(
        status: GoalStatus.losing,
        requestedKgPerWeek: requested,
        kgPerWeek: kg,
        targetWeightKg: target,
        projectedDate: dayOf(goal.goalDate!),
      );
  }
}

GoalPlan _reached(double target) => GoalPlan(
  status: GoalStatus.reached,
  requestedKgPerWeek: 0,
  kgPerWeek: 0,
  targetWeightKg: target,
);

/// This week's pace in kg for a pace set in [mode].
double paceKgPerWeek(PaceMode mode, double value, double trendKg) =>
    switch (mode) {
      PaceMode.kgPerWeek => value,
      PaceMode.percentPerWeek => trendKg * value / 100,
    };

/// The day the trend reaches [targetKg] losing [kgPerWeekNow] this week. In
/// percent mode the weekly amount shrinks with the weight.
DateTime projectDate({
  required double trendKg,
  required double targetKg,
  required PaceMode mode,
  required double kgPerWeekNow,
  required DateTime from,
}) {
  if (trendKg <= targetKg) return dayOf(from);
  final weeks = switch (mode) {
    PaceMode.kgPerWeek => (trendKg - targetKg) / kgPerWeekNow,
    PaceMode.percentPerWeek =>
      math.log(targetKg / trendKg) / math.log(1 - kgPerWeekNow / trendKg),
  };
  return addDays(dayOf(from), (weeks * 7).ceil());
}

/// Daily targets for one day.
@immutable
class DailyTargets {
  const new({
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.fibreG,
    required this.kgPerWeek,
    required this.floorKcal,
    required this.limitedByFloor,
  });

  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final double fibreG;

  /// The weekly loss these calories plan for, after the floor.
  final double kgPerWeek;

  /// The lowest calories allowed: the higher of BMR and the fixed minimum.
  final double floorKcal;

  /// True when the floor stopped the goal's pace (or the estimated burn is
  /// below the floor, so even maintenance sits on it).
  final bool limitedByFloor;
}

/// Protein per kg of body weight, mid-range of the 1.2–1.6 guidance.
const double proteinPerKg = 1.5;

/// Protein per kg of lean mass, for users who opted in to lean mass.
const double proteinPerKgLean = 2;

/// Minimum fat per kg of body weight.
const double minFatPerKg = 0.6;

/// Fat's usual share of calories, kept above [minFatPerKg].
const double fatShare = 0.25;

/// Calories and macros for [kgPerWeek] of loss.
///
/// Calories never go below the higher of [bmrKcal] and the fixed floor for
/// the user's sex; when that limits the pace, [DailyTargets.limitedByFloor]
/// is set and [DailyTargets.kgPerWeek] holds the pace actually planned.
DailyTargets computeTargets({
  required Profile profile,
  required double tdeeKcal,
  required double bmrKcal,
  required double trendKg,
  required double kgPerWeek,
  double? leanMassKg,
}) {
  final floor = math.max(bmrKcal, calorieFloor(profile.sex));
  final wanted = tdeeKcal - kgPerWeek * kcalPerKg / 7;
  // Rounded to 10 kcal, but never rounded down below the floor.
  final kcal = math.max(_round10(wanted), (floor / 10).ceil() * 10.0);
  final limited = wanted < floor - 1e-9;
  final plannedKgPerWeek = math.max(0, (tdeeKcal - kcal) * 7 / kcalPerKg);

  final protein = profile.useLeanMass && leanMassKg != null
      ? leanMassKg * proteinPerKgLean
      : trendKg * proteinPerKg;
  final fat = math.max(trendKg * minFatPerKg, kcal * fatShare / 9);
  final carbs = math.max(0, (kcal - protein * 4 - fat * 9) / 4);

  return DailyTargets(
    kcal: kcal,
    proteinG: protein.roundToDouble(),
    fatG: fat.roundToDouble(),
    carbsG: carbs.roundToDouble(),
    fibreG: fibreTargetG,
    kgPerWeek: limited ? plannedKgPerWeek.toDouble() : kgPerWeek,
    floorKcal: floor,
    limitedByFloor: limited,
  );
}

double _round10(double kcal) => (kcal / 10).round() * 10;
