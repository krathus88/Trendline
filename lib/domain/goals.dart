import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/energy.dart';
import 'package:trendline/domain/profile.dart';

/// How the weekly pace is expressed.
enum PaceMode {
  /// A fixed amount each week.
  kgPerWeek,

  /// A share of current body weight each week, so it changes with the
  /// weight.
  percentPerWeek,
}

/// Which two of target weight, pace and date the user fixed. The third is
/// worked out.
enum GoalKind { targetAndPace, targetAndDate, paceAndDate, maintain }

enum GoalDirection { lose, gain }

/// The fastest planned loss: 1% of current body weight per week.
const double maxLossPacePercent = 1;

/// The fastest planned gain: 0.5% of body weight per week. Faster gain is
/// mostly fat rather than muscle.
const double maxGainPacePercent = 0.5;

double maxPacePercent(GoalDirection d) => switch (d) {
  GoalDirection.lose => maxLossPacePercent,
  GoalDirection.gain => maxGainPacePercent,
};

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
    this.direction = GoalDirection.lose,
    this.targetWeightKg,
    this.paceMode = PaceMode.kgPerWeek,
    this.paceValue,
    this.goalDate,
  });

  static const maintenance = Goal(kind: GoalKind.maintain);

  final GoalKind kind;

  /// Losing or gaining. Ignored for maintenance.
  final GoalDirection direction;
  final double? targetWeightKg;
  final PaceMode paceMode;

  /// kg per week, or percent of body weight per week (1 = 1%). Always
  /// positive; [direction] gives the sign.
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
  losing,
  gaining,

  /// Maintenance chosen, or a pace of zero.
  maintaining,

  /// The trend has reached the target weight.
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
    this.direction = GoalDirection.lose,
    this.targetWeightKg,
    this.projectedDate,
  });

  final GoalStatus status;
  final GoalDirection direction;

  /// What the goal asks for this week, as a positive amount.
  final double requestedKgPerWeek;

  /// What will be planned: [requestedKgPerWeek] limited by the pace cap.
  final double kgPerWeek;

  /// Set or derived (pace and date goals derive it).
  final double? targetWeightKg;

  /// When the target is reached at [kgPerWeek]. Null without a target.
  final DateTime? projectedDate;

  bool get cappedByPace => kgPerWeek < requestedKgPerWeek - 1e-9;

  /// Signed: negative when losing.
  double get weeklyChangeKg =>
      direction == GoalDirection.gain ? kgPerWeek : -kgPerWeek;
}

const GoalPlan _maintaining = GoalPlan(
  status: GoalStatus.maintaining,
  requestedKgPerWeek: 0,
  kgPerWeek: 0,
);

/// Works out today's weekly pace for [goal] from the trend weight.
///
/// Never plans more than [maxPacePercent] of [trendKg] a week (1% losing,
/// 0.5% gaining); when the goal asks for more, [GoalPlan.cappedByPace] says
/// so and the projected date moves later. Once the trend reaches the target
/// (from the goal's direction) the goal counts as reached.
GoalPlan resolveGoal(
  Goal goal, {
  required double trendKg,
  required DateTime today,
}) {
  if (goal.kind == GoalKind.maintain) return _maintaining;

  final day = dayOf(today);
  final direction = goal.direction;
  final capKg = trendKg * maxPacePercent(direction) / 100;
  final losing = direction == GoalDirection.lose;
  final moving = losing ? GoalStatus.losing : GoalStatus.gaining;

  bool reached(double target) => losing ? trendKg <= target : trendKg >= target;
  GoalPlan reachedPlan(double target) => GoalPlan(
    status: GoalStatus.reached,
    direction: direction,
    requestedKgPerWeek: 0,
    kgPerWeek: 0,
    targetWeightKg: target,
  );

  switch (goal.kind) {
    case GoalKind.maintain:
      return _maintaining;

    case GoalKind.targetAndPace:
      final target = goal.targetWeightKg!;
      if (reached(target)) return reachedPlan(target);
      final requested = paceKgPerWeek(goal.paceMode, goal.paceValue!, trendKg);
      if (requested <= 0) {
        return GoalPlan(
          status: GoalStatus.maintaining,
          direction: direction,
          requestedKgPerWeek: 0,
          kgPerWeek: 0,
          targetWeightKg: target,
        );
      }
      final kg = math.min(requested, capKg);
      return GoalPlan(
        status: moving,
        direction: direction,
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
      if (reached(target)) return reachedPlan(target);
      final daysLeft = daysBetween(day, goal.goalDate!);
      if (daysLeft <= 0) {
        return GoalPlan(
          status: GoalStatus.datePassed,
          direction: direction,
          requestedKgPerWeek: 0,
          kgPerWeek: 0,
          targetWeightKg: target,
        );
      }
      final requested = (trendKg - target).abs() / (daysLeft / 7);
      final kg = math.min(requested, capKg);
      return GoalPlan(
        status: moving,
        direction: direction,
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
        return GoalPlan(
          status: GoalStatus.datePassed,
          direction: direction,
          requestedKgPerWeek: 0,
          kgPerWeek: 0,
        );
      }
      final requested = paceKgPerWeek(goal.paceMode, goal.paceValue!, trendKg);
      if (requested <= 0) return _maintaining;
      final kg = math.min(requested, capKg);
      final weeks = daysLeft / 7;
      final sign = losing ? -1 : 1;
      final target = switch (goal.paceMode) {
        PaceMode.kgPerWeek => trendKg + sign * kg * weeks,
        PaceMode.percentPerWeek =>
          trendKg * math.pow(1 + sign * kg / trendKg, weeks),
      };
      return GoalPlan(
        status: moving,
        direction: direction,
        requestedKgPerWeek: requested,
        kgPerWeek: kg,
        targetWeightKg: target,
        projectedDate: dayOf(goal.goalDate!),
      );
  }
}

/// This week's pace in kg for a pace set in [mode].
double paceKgPerWeek(PaceMode mode, double value, double trendKg) =>
    switch (mode) {
      PaceMode.kgPerWeek => value,
      PaceMode.percentPerWeek => trendKg * value / 100,
    };

/// The day the trend reaches [targetKg], changing by [kgPerWeekNow] this
/// week (towards the target, whichever way that is). In percent mode the
/// weekly amount changes with the weight.
DateTime projectDate({
  required double trendKg,
  required double targetKg,
  required PaceMode mode,
  required double kgPerWeekNow,
  required DateTime from,
}) {
  if (trendKg == targetKg || kgPerWeekNow <= 0) return dayOf(from);
  final sign = targetKg < trendKg ? -1 : 1;
  final weeks = switch (mode) {
    PaceMode.kgPerWeek => (trendKg - targetKg).abs() / kgPerWeekNow,
    PaceMode.percentPerWeek =>
      math.log(targetKg / trendKg) /
          math.log(1 + sign * kgPerWeekNow / trendKg),
  };
  return addDays(dayOf(from), (weeks * 7).ceil());
}

/// What protein was based on.
enum ProteinBasis {
  /// Lean mass from recent scale readings: the fairest basis, since it
  /// ignores fat and doesn't penalise muscular builds.
  leanMass,

  /// Body weight, adjusted down above a BMI of 25 (see [proteinWeightKg]).
  bodyWeight,
}

/// Daily targets for one day.
@immutable
class DailyTargets {
  const new({
    required this.kcal,
    required this.proteinG,
    required this.proteinBasis,
    required this.fatG,
    required this.carbsG,
    required this.fibreG,
    required this.weeklyChangeKg,
    required this.floorKcal,
    required this.limitedByFloor,
  });

  final double kcal;

  /// A minimum to reach, not a budget.
  final double proteinG;
  final ProteinBasis proteinBasis;
  final double fatG;
  final double carbsG;
  final double fibreG;

  /// The weekly change these calories plan for, after the floor: negative
  /// when losing, positive when gaining.
  final double weeklyChangeKg;

  /// The lowest calories allowed: the higher of BMR and the fixed minimum.
  final double floorKcal;

  /// True when the floor stopped the goal's pace (or the estimated burn is
  /// below the floor, so even maintenance sits on it).
  final bool limitedByFloor;
}

/// Protein in grams per kg of [proteinWeightKg], by goal and training.
///
/// * Losing: enough to hold on to muscle by default (1.6), more with
///   strength training (2.0), as higher intakes protect lean mass in a
///   deficit (ISSN 2017; 1.2–2.0 g/kg reference weight in weight-loss
///   reviews).
/// * Maintaining: 1.2 without training (within the 1.0–1.5 g/kg consensus),
///   1.6 with it (where muscle gains level off, Morton 2018).
/// * Gaining: 1.6, assuming the aim is muscle.
double proteinPerKgBodyWeight({
  required double weeklyChangeKg,
  required bool strengthTraining,
}) {
  if (weeklyChangeKg < 0) return strengthTraining ? 2.0 : 1.6;
  if (weeklyChangeKg > 0) return 1.6;
  return strengthTraining ? 1.6 : 1.2;
}

/// The same targets per kg of lean mass. Lean mass is roughly 75–80% of body
/// weight for most adults, so these are the body-weight figures divided by
/// about 0.8, rounded; the losing-with-training figure sits inside the
/// 2.3–3.1 g/kg lean mass range for resistance-trained people in a deficit
/// (Helms 2014).
double proteinPerKgLeanMass({
  required double weeklyChangeKg,
  required bool strengthTraining,
}) {
  if (weeklyChangeKg < 0) return strengthTraining ? 2.5 : 2.0;
  if (weeklyChangeKg > 0) return 2;
  return strengthTraining ? 2.0 : 1.5;
}

/// No protein target below this (2025 European obesity consensus).
const double minProteinG = 60;

/// Fat's share of calories: inside the UK ceiling of 35% and the 20–35%
/// range dietitians use.
const double fatShare = 0.3;

/// The BMI above which body weight is adjusted for protein.
const double referenceBmi = 25;

/// Share of the weight above [referenceBmi] that still counts for protein.
/// The usual clinical adjustment: excess weight is mostly fat, which needs
/// little protein.
const double excessWeightShare = 0.25;

/// The weight protein is based on when there's no lean mass reading: actual
/// weight up to a BMI of 25, and above that the BMI 25 weight plus a quarter
/// of the excess (adjusted body weight). BMI can't tell muscle from fat, so
/// lean mass from the scale is used instead whenever it's available.
double proteinWeightKg(double trendKg, double heightCm) {
  final metres = heightCm / 100;
  final atReference = referenceBmi * metres * metres;
  if (trendKg <= atReference) return trendKg;
  return atReference + excessWeightShare * (trendKg - atReference);
}

/// Calories and macros for a signed [weeklyChangeKg] (negative to lose).
///
/// Calories never go below the higher of [bmrKcal] and the fixed floor for
/// the user's sex; when that limits the pace, [DailyTargets.limitedByFloor]
/// is set and [DailyTargets.weeklyChangeKg] holds what is actually planned.
///
/// Protein comes from [leanMassKg] when there is a recent reading, else from
/// [proteinWeightKg]. Fat is [fatShare] of calories; carbs are the rest.
DailyTargets computeTargets({
  required Profile profile,
  required double tdeeKcal,
  required double bmrKcal,
  required double trendKg,
  required double weeklyChangeKg,
  double? leanMassKg,
}) {
  final floor = math.max(bmrKcal, calorieFloor(profile.sex));
  final wanted = tdeeKcal + weeklyChangeKg * kcalPerKg / 7;
  // Rounded to 10 kcal, but never rounded down below the floor.
  final kcal = math.max(_round10(wanted), (floor / 10).ceil() * 10.0);
  final limited = wanted < floor - 1e-9;
  final change = limited ? (kcal - tdeeKcal) * 7 / kcalPerKg : weeklyChangeKg;

  final training = profile.strengthTraining;
  final byLean = leanMassKg != null;
  final perKgProtein = byLean
      ? leanMassKg *
            proteinPerKgLeanMass(
              weeklyChangeKg: change,
              strengthTraining: training,
            )
      : proteinWeightKg(trendKg, profile.heightCm) *
            proteinPerKgBodyWeight(
              weeklyChangeKg: change,
              strengthTraining: training,
            );
  final protein = math.max(minProteinG, perKgProtein);
  final fat = kcal * fatShare / 9;
  final carbs = math.max(0, (kcal - protein * 4 - fat * 9) / 4);

  return DailyTargets(
    kcal: kcal,
    proteinG: protein.roundToDouble(),
    proteinBasis: byLean ? ProteinBasis.leanMass : ProteinBasis.bodyWeight,
    fatG: fat.roundToDouble(),
    carbsG: carbs.roundToDouble(),
    fibreG: fibreTargetG,
    weeklyChangeKg: change,
    floorKcal: floor,
    limitedByFloor: limited,
  );
}

double _round10(double kcal) => (kcal / 10).round() * 10;

/// A goal worked through to today's targets and projected date.
@immutable
class GoalOutlook {
  const new({required this.plan, required this.targets, this.projectedDate});

  final GoalPlan plan;
  final DailyTargets targets;

  /// When the target is reached at the pace actually planned (after the cap
  /// and the floor). Null without a target, or when no change is planned.
  final DateTime? projectedDate;

  /// The pace asked for isn't what's planned.
  bool get adjusted => plan.cappedByPace || targets.limitedByFloor;
}

/// Resolves [goal] and computes the day's targets in one step.
GoalOutlook outlookFor({
  required Goal goal,
  required Profile profile,
  required double tdeeKcal,
  required double bmrKcal,
  required double trendKg,
  required DateTime today,
  double? leanMassKg,
}) {
  final plan = resolveGoal(goal, trendKg: trendKg, today: today);
  final targets = computeTargets(
    profile: profile,
    tdeeKcal: tdeeKcal,
    bmrKcal: bmrKcal,
    trendKg: trendKg,
    weeklyChangeKg: plan.weeklyChangeKg,
    leanMassKg: leanMassKg,
  );
  final target = plan.targetWeightKg;
  final change = targets.weeklyChangeKg;
  final towardsTarget =
      target != null && change != 0 && (target < trendKg) == (change < 0);
  return GoalOutlook(
    plan: plan,
    targets: targets,
    projectedDate: !towardsTarget
        ? null
        : targets.limitedByFloor
        ? projectDate(
            trendKg: trendKg,
            targetKg: target,
            mode: PaceMode.kgPerWeek,
            kgPerWeekNow: change.abs(),
            from: today,
          )
        : plan.projectedDate,
  );
}
