import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:trendline/data/energy/energy_notifier.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/domain/goals.dart';

/// Today's goal, targets and the energy estimate behind them.
@immutable
class TodayTargets {
  const new({required this.goal, required this.outlook, required this.energy});

  final Goal goal;
  final GoalOutlook outlook;
  final EnergyState energy;

  GoalPlan get plan => outlook.plan;
  DailyTargets get targets => outlook.targets;
  DateTime? get projectedDate => outlook.projectedDate;
  bool get adjusted => outlook.adjusted;
}

/// Null until there's a profile, a goal and a weigh-in.
final targetsProvider = FutureProvider<TodayTargets?>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final goal = await ref.watch(goalProvider.future);
  final energy = await ref.watch(energyProvider.future);
  if (profile == null || goal == null || energy == null) return null;

  return TodayTargets(
    goal: goal,
    energy: energy,
    outlook: outlookFor(
      goal: goal,
      profile: profile,
      tdeeKcal: energy.tdeeKcal,
      bmrKcal: energy.bmrKcal,
      trendKg: energy.trendKg,
      leanMassKg: energy.leanMassKg,
      today: DateTime.now(),
    ),
  );
});
