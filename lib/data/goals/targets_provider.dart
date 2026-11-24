import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:trendline/data/energy/energy_notifier.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/domain/goals.dart';

/// Today's goal and targets.
@immutable
class TodayTargets {
  const new({
    required this.goal,
    required this.plan,
    required this.targets,
    required this.energy,
    this.projectedDate,
  });

  final Goal goal;
  final GoalPlan plan;
  final DailyTargets targets;
  final EnergyState energy;

  /// When the target is reached at the pace actually planned (after the cap
  /// and the floors). Null without a target, or when no loss is planned.
  final DateTime? projectedDate;

  /// The pace the goal asked for isn't what's planned.
  bool get adjusted => plan.cappedByPace || targets.limitedByFloor;
}

/// Null until there's a profile, a goal and a weigh-in.
final targetsProvider = FutureProvider<TodayTargets?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final goal = await ref.watch(goalProvider.future);
  final energy = await ref.watch(energyProvider.future);
  if (profile == null || goal == null || energy == null) return null;

  final today = DateTime.now();
  final plan = resolveGoal(goal, trendKg: energy.trendKg, today: today);
  final targets = computeTargets(
    profile: profile,
    tdeeKcal: energy.tdeeKcal,
    bmrKcal: energy.bmrKcal,
    trendKg: energy.trendKg,
    kgPerWeek: plan.kgPerWeek,
    leanMassKg: energy.leanMassKg,
  );

  final target = plan.targetWeightKg;
  DateTime? projected;
  if (target != null && targets.kgPerWeek > 0) {
    projected = targets.limitedByFloor
        ? projectDate(
            trendKg: energy.trendKg,
            targetKg: target,
            mode: PaceMode.kgPerWeek,
            kgPerWeekNow: targets.kgPerWeek,
            from: today,
          )
        : plan.projectedDate;
  }

  return TodayTargets(
    goal: goal,
    plan: plan,
    targets: targets,
    energy: energy,
    projectedDate: projected,
  );
});
