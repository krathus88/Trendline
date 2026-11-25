import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/health/health_sync_notifier.dart';
import 'package:trendline/data/meal_rules/meal_rules_notifier.dart';
import 'package:trendline/data/preferences/food_preferences_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/schedule/schedule_notifier.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/platform/health_source.dart';

/// The things to set up before (and for better) planning.
enum SetupStep {
  profile,
  goal,
  weighIn,
  daySchedule,
  mealRules,
  foodPreferences,
  healthConnect;

  /// Planning can't run without these: targets need a profile, a goal and a
  /// weigh-in. The rest make plans fit better.
  bool get isRequired => this == profile || this == goal || this == weighIn;
}

/// Which setup steps are done.
@immutable
class SetupStatus {
  const new({required this.done, required this.offered});

  final Set<SetupStep> done;

  /// The steps that apply here (Health Connect only where it's available).
  final Set<SetupStep> offered;

  List<SetupStep> get steps => [
    for (final s in SetupStep.values)
      if (offered.contains(s)) s,
  ];

  bool isDone(SetupStep step) => done.contains(step);

  /// Whether a plan can be made: every required step is done.
  bool get canPlan =>
      SetupStep.values.where((s) => s.isRequired).every(done.contains);

  int get doneCount => steps.where(done.contains).length;
}

/// The setup checklist, kept current as each step is done.
final setupStatusProvider = FutureProvider<SetupStatus>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final goal = await ref.watch(goalProvider.future);
  final weighIns = await ref.watch(weighInsProvider.future);
  final schedule = await ref.watch(scheduleProvider.future);
  final rules = await ref.watch(mealRulesProvider.future);
  final preferences = await ref.watch(foodPreferencesProvider.future);
  // Health Connect is optional and its check may be slow or fail: it never
  // holds up the rest of the list.
  final health = ref.watch(healthSyncProvider).value;
  final healthOffered =
      health != null && health.availability != HealthAvailability.unavailable;

  return SetupStatus(
    offered: {
      for (final s in SetupStep.values)
        if (s != SetupStep.healthConnect || healthOffered) s,
    },
    done: {
      if (profile != null) SetupStep.profile,
      if (goal != null) SetupStep.goal,
      if (weighIns.isNotEmpty) SetupStep.weighIn,
      // The schedule always has seven days; unset ones are stand-ins.
      if (schedule.any((d) => d.isSet)) SetupStep.daySchedule,
      if (rules.isNotEmpty) SetupStep.mealRules,
      if (preferences.ingredients.isNotEmpty || preferences.cuisines.isNotEmpty)
        SetupStep.foodPreferences,
      if (health?.connected ?? false) SetupStep.healthConnect,
    },
  );
});
