import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/energy/day_complete_notifier.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/meal_rules/meal_rules_notifier.dart';
import 'package:trendline/data/plans/household_plan_notifier.dart';
import 'package:trendline/data/plans/plan_notifier.dart';
import 'package:trendline/data/preferences/food_preferences_notifier.dart';
import 'package:trendline/data/prep/prep_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipe_favourites_notifier.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/data/schedule/schedule_notifier.dart';
import 'package:trendline/data/sync/change_signals.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/dates.dart';

/// How long to wait after a signal for more before refreshing, so a burst
/// of changes (saving a recipe touches two tables) refreshes once.
const Duration changeSyncDelay = Duration(milliseconds: 500);

/// While someone is signed in, listens for change signals and refreshes
/// what changed. Kept alive by the home screen.
final changeSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return;
  final householdId = ref.watch(householdIdProvider);
  final pending = <String>{};
  Timer? timer;
  final subscription = ref
      .watch(changeSignalsProvider)
      .watch(userId, householdId)
      .listen(
        (table) {
          pending.add(table);
          timer?.cancel();
          timer = Timer(changeSyncDelay, () {
            final tables = {...pending};
            pending.clear();
            refreshChanged(ref, tables);
          });
        },
        // Live updates are a convenience: a dropped connection just means
        // pulling to refresh, as before.
        onError: (Object _) {},
      );
  ref.onDispose(() {
    timer?.cancel();
    subscription.cancel().ignore();
  });
});

/// The tables [refreshChanged] refetches data for.
const Set<String> syncedTables = {
  'profiles',
  'goals',
  'weigh_ins',
  'day_logs',
  'food_logs',
  'foods',
  'recipes',
  'recipe_favourites',
  'food_preferences',
  'day_schedules',
  'meal_rules',
  'meal_plans',
  'prep_sessions',
};

/// Refetches the data held for [tables], or for all of it on
/// [everyTable]. Plans with unsaved changes are
/// left alone (see [PlanNotifier.refresh]).
void refreshChanged(Ref ref, Set<String> tables) {
  for (final table in tables.contains(everyTable) ? syncedTables : tables) {
    switch (table) {
      case 'profiles':
        ref.invalidate(profileProvider);
      case 'goals':
        ref.invalidate(goalProvider);
      case 'weigh_ins':
        ref.invalidate(weighInsProvider);
      case 'day_logs':
        ref.invalidate(dayCompleteProvider);
      case 'food_logs':
        ref.invalidate(foodLogProvider);
      case 'foods':
        ref
          ..invalidate(foodsProvider)
          ..invalidate(sharedFoodsProvider);
      case 'recipes' || 'recipe_ingredients':
        ref
          ..invalidate(recipesProvider)
          ..invalidate(sharedRecipesProvider);
      case 'recipe_favourites':
        ref.invalidate(recipeFavouritesProvider);
      case 'food_preferences':
        ref
          ..invalidate(foodPreferencesProvider)
          ..invalidate(householdFoodPreferencesProvider);
      case 'day_schedules':
        ref.invalidate(scheduleProvider);
      case 'meal_rules':
        ref.invalidate(mealRulesProvider);
      case 'meal_plans' || 'plan_items':
        final thisWeek = weekStartOf(DateTime.now());
        for (final week in [thisWeek, addDays(thisWeek, 7)]) {
          if (ref.read(planProvider(week).exists)) {
            ref.read(planProvider(week).notifier).refresh();
          }
          if (ref.read(householdPlanProvider(week).exists)) {
            ref.read(householdPlanProvider(week).notifier).refresh();
          }
        }
      case 'prep_sessions' || 'prep_portions':
        ref.invalidate(prepProvider);
      default:
        // Nothing held for it.
        break;
    }
  }
}
