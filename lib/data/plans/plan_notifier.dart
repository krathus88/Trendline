import 'dart:isolate';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show AsyncNotifierProviderFamily, ProviderListenable;
import 'package:meta/meta.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/goals/targets_provider.dart';
import 'package:trendline/data/meal_rules/meal_rules_notifier.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/data/plans/planner_catalogue.dart';
import 'package:trendline/data/preferences/food_preferences_notifier.dart';
import 'package:trendline/data/prep/prep_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/dish_template_providers.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/replan.dart';

/// Raised when there's nothing to plan towards yet.
class PlanNeedsTargets implements Exception {
  const new();

  String get message =>
      'Set up your profile, goal and a weigh-in first: the plan is sized '
      'to your targets.';
}

/// Raised when a day is re-planned or logged from a plan that isn't saved
/// (or no longer matches the user's foods and recipes).
class PlanNotSaved implements Exception {
  const new();

  String get message =>
      'Save the week’s plan first, then its meals can be logged and '
      're-planned.';
}

/// A week's plan as shown: saved, or freshly made and not saved yet.
@immutable
class PlanState {
  const new({
    required this.weekStart,
    this.plan,
    this.targets,
    this.saved = false,
  });

  /// The Monday the week starts on.
  final DateTime weekStart;

  /// Null until a plan is made.
  final WeekPlan? plan;
  final PlanTargets? targets;

  /// Whether [plan] is what's saved.
  final bool saved;

  DateTime dayOf(int day) => addDays(weekStart, day);
}

/// Runs the planner. Off the UI thread in the app; tests run it directly.
final planRunnerProvider =
    Provider<Future<WeekPlan> Function(PlannerInput input, int seed)>(
      (ref) =>
          (input, seed) => Isolate.run(() => planWeek(input, Random(seed))),
    );

/// The plan for the week starting on the given Monday.
final AsyncNotifierProviderFamily<PlanNotifier, PlanState, DateTime>
planProvider = AsyncNotifierProvider.family<PlanNotifier, PlanState, DateTime>(
  PlanNotifier.new,
);

class PlanNotifier extends AsyncNotifier<PlanState> {
  new(this.weekStart);

  final DateTime weekStart;

  /// The candidates behind the last plan made, for saving its library and
  /// template dishes and offering swaps.
  PlannerCatalogue? _catalogue;

  @override
  Future<PlanState> build() async {
    if (ref.watch(currentUserIdProvider) == null) {
      return PlanState(weekStart: weekStart);
    }
    // Keep everything planning reads active: Riverpod pauses providers no
    // one listens to, and their futures would never complete. Listening
    // (not watching) so a change elsewhere doesn't throw away an unsaved
    // plan.
    for (final source in <ProviderListenable<Object?>>[
      recipesProvider,
      foodsProvider,
      recipeLibraryProvider,
      libraryFoodsProvider,
      dishTemplatesProvider,
      templateFoodsProvider,
      foodPreferencesProvider,
      mealRulesProvider,
      targetsProvider,
      prepProvider,
      profileProvider,
    ]) {
      ref.listen(source, (_, _) {});
    }
    final saved = await ref
        .watch(mealPlanRepositoryProvider)
        .fetchWeek(weekStart);
    if (saved == null) return PlanState(weekStart: weekStart);
    final recipes = await ref.read(recipesProvider.future);
    final foods = {
      for (final f in await ref.read(foodsProvider.future)) f.id: f,
    };
    return PlanState(
      weekStart: weekStart,
      plan: _fromSaved(saved, recipes, foods),
      targets: saved.targets,
      saved: true,
    );
  }

  Future<PlannerCatalogue> _buildCatalogue() async {
    Future<T?> orNull<T>(Future<T> f) async {
      try {
        return await f;
      } on Object {
        return null;
      }
    }

    final sources = PlannerSources(
      recipes: await ref.read(recipesProvider.future),
      foods: {for (final f in await ref.read(foodsProvider.future)) f.id: f},
      // The library and templates are extras: plan without them if they
      // can't be loaded.
      library: await orNull(ref.read(recipeLibraryProvider.future)) ?? const [],
      libraryFoods:
          await orNull(ref.read(libraryFoodsProvider.future)) ?? const {},
      templates: await orNull(ref.read(dishTemplatesProvider.future)),
      templateFoods:
          await orNull(ref.read(templateFoodsProvider.future)) ?? const {},
      preferences: await ref.read(foodPreferencesProvider.future),
      rules: await ref.read(mealRulesProvider.future),
    );
    return _catalogue = buildCatalogue(sources);
  }

  /// Makes a plan for the week, keeping the items the user locked.
  Future<void> generate({int? seed}) async {
    final today = await ref.read(targetsProvider.future);
    if (today == null) throw const PlanNeedsTargets();
    final t = today.targets;
    final targets = PlanTargets(
      kcal: t.kcal,
      proteinG: t.proteinG,
      carbsG: t.carbsG,
      fatG: t.fatG,
      fibreG: t.fibreG,
    );
    final catalogue = await _buildCatalogue();
    // Snack dishes only when the user wants a snack planned each day.
    final snacks = (await ref.read(profileProvider.future))?.planSnacks ?? true;
    final dishes = [
      for (final d in catalogue.dishes)
        if (snacks || !d.meals.contains(MealSlot.snack)) d,
    ];
    final locked = [
      for (final i in state.value?.plan?.items ?? const <PlannedItem>[])
        if (i.locked) i,
    ];
    final plan = await ref.read(planRunnerProvider)(
      PlannerInput(
        targets: [targets],
        dishes: dishes,
        rules: catalogue.rules,
        locked: locked,
      ),
      seed ?? Random().nextInt(1 << 31),
    );
    state = AsyncData(
      PlanState(weekStart: weekStart, plan: plan, targets: targets),
    );
  }

  /// Locks or unlocks [item]: locked items stay when regenerating.
  void toggleLock(PlannedItem item) =>
      _replace(item, item.copyWith(locked: !item.locked));

  void remove(PlannedItem item) => _replace(item, null);

  /// Dishes that could go in [slot] instead.
  Future<List<DishCandidate>> swapOptions(MealSlot slot) async {
    final catalogue = _catalogue ?? await _buildCatalogue();
    return [
      for (final d in catalogue.dishes)
        if (d.meals.contains(slot)) d,
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Puts [dish] in [item]'s place, one portion, locked.
  void swap(PlannedItem item, DishCandidate dish) => _replace(
    item,
    PlannedItem(
      day: item.day,
      slot: item.slot,
      key: dish.key,
      name: dish.name,
      amount: 1,
      isDish: true,
      perUnit: dish.perPortion,
      minAmount: dish.minServing,
      maxAmount: dish.maxServing,
      locked: true,
    ),
  );

  void _replace(PlannedItem item, PlannedItem? replacement) {
    final current = state.value;
    final plan = current?.plan;
    if (current == null || plan == null) return;
    bool same(PlannedItem i) =>
        i.day == item.day && i.slot == item.slot && i.key == item.key;
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        targets: current.targets,
        plan: WeekPlan(
          items: [
            for (final i in plan.items)
              if (!same(i)) i else ?replacement,
          ],
          notes: plan.notes,
        ),
      ),
    );
  }

  /// Saves the plan. Library and template dishes it uses are copied into
  /// the user's recipes first (template ones stay out of the Recipes list
  /// until kept), so the saved plan only points at the user's own data.
  /// The database lays out its prep sessions from the batches as it saves.
  Future<void> save() async {
    final current = state.value;
    final plan = current?.plan;
    final targets = current?.targets;
    if (current == null || plan == null || targets == null) return;
    final recipes = ref.read(recipesProvider.notifier);
    final recipeIds = <String, String>{};

    Future<String?> recipeFor(String key) async {
      if (recipeIds[key] case final id?) return id;
      final catalogue = _catalogue;
      String? id;
      if (key.startsWith('recipe:')) {
        id = key.substring('recipe:'.length);
      } else if (catalogue?.library[key] case final library?) {
        id = (recipes.copyOf(library) ?? await recipes.addFromLibrary(library))
            .id;
      } else if (catalogue?.generated[key] case final option?) {
        final made = option.dish.madeWeightG;
        final copy = await recipes.addFromLibrary(
          option.dish.toRecipe(),
          origin: RecipeOrigin.template,
          foods: await ref.read(templateFoodsProvider.future),
          // A no-cook snack weighs what goes in, so it can be logged by
          // weight without weighing anything.
          estimatedCookedWeightG: made == null ? option.expectedCookedG : null,
          cookedWeightG: made,
        );
        await recipes.setListed(copy.id, listed: false);
        id = copy.id;
      }
      if (id != null) recipeIds[key] = id;
      return id;
    }

    final items = <SavedPlanItem>[];
    for (final i in plan.items) {
      final foodId = i.key.startsWith('food:')
          ? i.key.substring('food:'.length)
          : null;
      final recipeId = foodId == null ? await recipeFor(i.key) : null;
      if (foodId == null && recipeId == null) continue;
      items.add(
        SavedPlanItem(
          day: current.dayOf(i.day),
          slot: i.slot,
          foodId: foodId,
          recipeId: recipeId,
          amount: i.amount,
          amountMin: i.minAmount,
          amountMax: i.maxAmount,
          locked: i.locked,
          batch: i.batch,
          mealRuleId: i.ruleId,
        ),
      );
    }
    final repository = ref.read(mealPlanRepositoryProvider);
    await repository.save(
      SavedPlan(
        weekStart: weekStart,
        targets: targets,
        notes: plan.notes,
        items: items,
      ),
    );
    // Saving lays out the plan's prep sessions.
    ref.invalidate(prepProvider);
    // Read it back for the items' IDs, which re-planning a day needs.
    final saved = await repository.fetchWeek(weekStart);
    if (saved == null) return;
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        targets: saved.targets,
        plan: _fromSaved(saved, await ref.read(recipesProvider.future), {
          for (final f in await ref.read(foodsProvider.future)) f.id: f,
        }),
        saved: true,
      ),
    );
  }

  /// Re-plans the rest of [date] around what's been [eaten]: the saved
  /// plan's items not yet eaten are refitted to [targetKcal] within their
  /// ranges, and saved. Portions of batches already cooked stay as boxed.
  /// Returns the outcome, with a note when the day can't land near its
  /// target.
  Future<DayReplan> replanDay({
    required DateTime date,
    required List<FoodLogEntry> eaten,
    required double targetKcal,
  }) async {
    final current = state.value;
    final plan = current?.plan;
    if (current == null || plan == null || !current.saved) {
      throw const PlanNotSaved();
    }
    final day = daysBetween(weekStart, date);
    final remaining = remainingItems(plan.itemsOn(day), eaten);
    final boxed = <(String, MealSlot)>{
      for (final s in await ref.read(prepProvider.future))
        if (s.cooked)
          for (final p in s.openPortions)
            if (p.day == date) ('recipe:${s.recipeId}', p.slot!),
    };
    final result = replanRestOfDay(
      remaining: remaining,
      eaten: Nutrition.sum(eaten.map((e) => e.nutrition)),
      targetKcal: targetKcal,
      fixed: (i) => boxed.contains((i.key, i.slot)),
    );
    final changed = {
      for (final i in result.changedFrom(remaining)) ?i.id: i.amount,
    };
    if (changed.isEmpty) return result;
    await ref.read(mealPlanRepositoryProvider).updateAmounts(changed);
    // Prep for batches not yet cooked follows the new amounts.
    ref.invalidate(prepProvider);
    final latest = state.value ?? current;
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        targets: latest.targets,
        saved: true,
        plan: WeekPlan(
          items: [
            for (final i in latest.plan?.items ?? const <PlannedItem>[])
              if (changed[i.id] case final amount?)
                i.copyWith(amount: amount)
              else
                i,
          ],
          notes: latest.plan?.notes ?? const [],
        ),
      ),
    );
    return result;
  }

  /// Logs [item] as eaten on [date], as planned: a food by its grams; a
  /// dish by its portion of the cooked batch (or of the recipe's weighed
  /// batch when it isn't prepped).
  Future<void> logPlanned(PlannedItem item, DateTime date) async {
    final log = ref.read(foodLogProvider(date).notifier);
    final foods = {
      for (final f in await ref.read(foodsProvider.future)) f.id: f,
    };
    if (item.key.startsWith('food:')) {
      final food = foods[item.key.substring('food:'.length)];
      if (food == null) throw const PlanNotSaved();
      await log.add(slot: item.slot, food: food, grams: item.amount);
      return;
    }
    final recipeId = item.key.substring('recipe:'.length);
    final recipes = await ref.read(recipesProvider.future);
    final recipe = recipes.where((r) => r.id == recipeId).firstOrNull;
    if (recipe == null) throw const PlanNotSaved();
    for (final s in await ref.read(prepProvider.future)) {
      if (s.recipeId != recipeId) continue;
      for (final p in s.openPortions) {
        if (p.day != date || p.slot != item.slot) continue;
        await ref
            .read(prepProvider.notifier)
            .eat(
              session: s,
              portion: p,
              recipe: recipe,
              foods: foods,
              day: date,
              slot: item.slot,
            );
        return;
      }
    }
    final per100g = recipeNutrition(recipe, foods).per100gCooked;
    final portionG = recipe.portionG;
    if (per100g == null || portionG == null) throw const PrepNotWeighed();
    await log.addRecipe(
      slot: item.slot,
      recipe: recipe,
      per100gCooked: per100g,
      grams: (item.amount * portionG * 10).round() / 10,
    );
  }
}

WeekPlan _fromSaved(
  SavedPlan saved,
  List<Recipe> recipes,
  Map<String, Food> foods,
) {
  final recipesById = {for (final r in recipes) r.id: r};
  final items = <PlannedItem>[];
  for (final i in saved.items) {
    final day = daysBetween(saved.weekStart, i.day);
    if (i.recipeId case final id?) {
      final r = recipesById[id];
      if (r == null) continue;
      items.add(
        PlannedItem(
          day: day,
          slot: i.slot,
          key: 'recipe:$id',
          name: r.name,
          amount: i.amount,
          isDish: i.mealRuleId == null,
          perUnit: recipeNutrition(r, foods).perPortion,
          minAmount: i.amountMin,
          maxAmount: i.amountMax,
          locked: i.locked,
          batch: i.batch,
          ruleId: i.mealRuleId,
          id: i.id,
        ),
      );
    } else if (foods[i.foodId] case final f?) {
      items.add(
        PlannedItem(
          day: day,
          slot: i.slot,
          key: 'food:${f.id}',
          name: f.name,
          amount: i.amount,
          isDish: false,
          perUnit: perGram(f.per100g),
          minAmount: i.amountMin,
          maxAmount: i.amountMax,
          locked: i.locked,
          ruleId: i.mealRuleId,
          id: i.id,
        ),
      );
    }
  }
  items.sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    return byDay != 0 ? byDay : a.slot.index.compareTo(b.slot.index);
  });
  return WeekPlan(items: items, notes: saved.notes);
}
