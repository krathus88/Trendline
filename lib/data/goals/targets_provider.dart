import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:trendline/data/energy/energy_notifier.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/profile.dart';

/// Today's goal, targets and the energy estimate behind them.
@immutable
class TodayTargets {
  const new({
    required this.goal,
    required this.outlook,
    required this.energy,
    required this.profile,
    required this.today,
  });

  final Goal goal;
  final Profile profile;

  /// The day these targets are for.
  final DateTime today;
  final GoalOutlook outlook;
  final EnergyState energy;

  GoalPlan get plan => outlook.plan;
  DailyTargets get targets => outlook.targets;
  DateTime? get projectedDate => outlook.projectedDate;
  bool get adjusted => outlook.adjusted;

  /// Each day's targets for planning the week starting [weekStart] (see
  /// [weekTargets]), Monday first.
  List<PlanTargets> forWeek(DateTime weekStart) => [
    for (final t in weekTargets(
      goal: goal,
      profile: profile,
      tdeeKcal: energy.tdeeKcal,
      bmrKcal: energy.bmrKcal,
      trendKg: energy.trendKg,
      leanMassKg: energy.leanMassKg,
      today: today,
      weekStart: weekStart,
    ))
      PlanTargets(
        kcal: t.kcal,
        proteinG: t.proteinG,
        carbsG: t.carbsG,
        fatG: t.fatG,
        fibreG: t.fibreG,
      ),
  ];
}

/// Null until there's a profile, a goal and a weigh-in.
final targetsProvider = FutureProvider<TodayTargets?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final goal = await ref.watch(goalProvider.future);
  final energy = await ref.watch(energyProvider.future);
  if (profile == null || goal == null || energy == null) return null;

  final today = DateTime.now();
  return TodayTargets(
    goal: goal,
    energy: energy,
    profile: profile,
    today: today,
    outlook: outlookFor(
      goal: goal,
      profile: profile,
      tdeeKcal: energy.tdeeKcal,
      bmrKcal: energy.bmrKcal,
      trendKg: energy.trendKg,
      leanMassKg: energy.leanMassKg,
      today: today,
    ),
  );
});
