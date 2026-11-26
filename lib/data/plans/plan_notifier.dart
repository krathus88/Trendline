import 'dart:isolate';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show AsyncNotifierProviderFamily, ProviderListenable;
import 'package:meta/meta.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/goals/targets_provider.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/meal_rules/meal_rules_notifier.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/data/plans/planner_catalogue.dart';
import 'package:trendline/data/preferences/food_preferences_notifier.dart';
import 'package:trendline/data/prep/prep_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/dish_template_providers.dart';
import 'package:trendline/data/recipes/recipe_favourites_notifier.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/prep.dart';
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
    this.estimated = const {},
    this.leftovers = const {},
  });

  /// The Monday the week starts on.
  final DateTime weekStart;

  /// Null until a plan is made.
  final WeekPlan? plan;

  /// Each day's targets, Monday first (seven). Null until a plan is made.
  final List<PlanTargets>? targets;

  /// Whether [plan] is what's saved.
  final bool saved;

  /// IDs of the user's servings of household dishes whose amounts are
  /// estimates (someone planned the household week since the user last
  /// fitted them).
  final Set<String> estimated;

  /// Items (by day, meal and key) that eat up a leftover portion, in a
  /// plan not saved yet.
  final Set<(int, MealSlot, String)> leftovers;

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

  /// The leftover portions the plan not saved yet eats, by the item (day,
  /// meal and key) that eats each: saving moves them to those meals.
  Map<(int, MealSlot, String), PrepPortion> _leftovers = {};

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
      householdProvider,
      sharedRecipesProvider,
      sharedFoodsProvider,
    ]) {
      ref.listen(source, (_, _) {});
    }
    final saved = await ref
        .watch(mealPlanRepositoryProvider)
        .fetchWeek(weekStart);
    final (shared, estimated) = await _sharedItems();
    if (saved == null) {
      // Only the household's servings so far: those are saved, and Today
      // follows them.
      return PlanState(
        weekStart: weekStart,
        plan: shared.isEmpty
            ? null
            : WeekPlan(items: _sorted(shared), notes: const []),
        saved: shared.isNotEmpty,
        estimated: estimated,
      );
    }
    final recipes = await ref.read(recipesProvider.future);
    final foods = {
      for (final f in await ref.read(foodsProvider.future)) f.id: f,
    };
    final own = _fromSaved(saved, recipes, foods);
    return PlanState(
      weekStart: weekStart,
      plan: WeekPlan(
        items: _sorted([...own.items, ...shared]),
        notes: own.notes,
      ),
      targets: saved.targets,
      saved: true,
      estimated: estimated,
    );
  }

  /// The user's servings in the household's week, if there is one: shared
  /// dishes whose amounts are theirs to fit. Also the IDs of those whose
  /// amounts are still estimates.
  Future<(List<PlannedItem>, Set<String>)> _sharedItems() async {
    const none = (<PlannedItem>[], <String>{});
    final me = ref.read(currentUserIdProvider);
    final household = await ref.read(householdProvider.future);
    if (me == null || household == null) return none;
    final week = await ref
        .read(mealPlanRepositoryProvider)
        .fetchHouseholdWeek(weekStart);
    if (week == null) return none;
    final recipes = {
      for (final r in await ref.read(sharedRecipesProvider.future)) r.id: r,
    };
    final foods = {
      for (final f in await ref.read(sharedFoodsProvider.future)) f.id: f,
    };
    final items = [
      for (final i in week.itemsFor(me))
        if (recipes[i.recipeId] case final r?)
          PlannedItem(
            day: daysBetween(weekStart, i.day),
            slot: i.slot,
            key: 'recipe:${r.id}',
            name: r.name,
            amount: i.amount,
            isDish: true,
            perUnit: recipeNutrition(r, foods).perPortion,
            minAmount: i.amountMin,
            maxAmount: i.amountMax,
            batch: i.batch,
            id: i.id,
            shared: true,
          ),
    ];
    return (
      items,
      {
        for (final i in week.itemsFor(me))
          if (i.estimated) ?i.id,
      },
    );
  }

  /// The user's open portions of cooked batches, by day, meal and dish:
  /// boxed, so their amounts can't change.
  Future<Set<(DateTime, MealSlot, String)>> _boxed() async {
    final me = ref.read(currentUserIdProvider);
    return {
      for (final s in await ref.read(prepProvider.future))
        if (s.cooked)
          for (final p in s.openPortionsFor(me))
            if (p.day != null) (p.day!, p.slot!, 'recipe:${s.recipeId}'),
    };
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
      favourites: {
        for (final id in await ref.read(recipeFavouritesProvider.future))
          id: 1,
      },
    );
    return _catalogue = buildCatalogue(sources);
  }

  /// Makes a plan for the week, keeping the items the user locked.
  Future<void> generate({int? seed}) async {
    final today = await ref.read(targetsProvider.future);
    if (today == null) throw const PlanNeedsTargets();
    final targets = today.forWeek(weekStart);
    final catalogue = await _buildCatalogue();
    // Snack dishes only when the user wants a snack planned each day.
    final snacks = (await ref.read(profileProvider.future))?.planSnacks ?? true;
    final dishes = [
      for (final d in catalogue.dishes)
        if (snacks || !d.meals.contains(MealSlot.snack)) d,
    ];
    // The household's servings stay where they are; their amounts are
    // fitted to the user's day unless the batch is already cooked.
    final boxed = await _boxed();
    final thisDay = dayOf(DateTime.now());
    bool isBoxed(PlannedItem i) =>
        boxed.contains((addDays(weekStart, i.day), i.slot, i.key));
    final locked = [
      for (final i in state.value?.plan?.items ?? const <PlannedItem>[])
        if (i.shared)
          i.copyWith(locked: isBoxed(i))
        // Leftovers are placed again below.
        else if (_leftovers.containsKey((i.day, i.slot, i.key)))
          ?null
        // Food already cooked for a meal still to come stays there.
        else if (isBoxed(i) && !addDays(weekStart, i.day).isBefore(thisDay))
          i.copyWith(locked: true)
        else if (i.locked)
          i,
    ];
    // Leftovers first, so they're eaten rather than forgotten.
    _leftovers = {};
    for (final (portion, item) in await _leftoverItems(locked)) {
      _leftovers[(item.day, item.slot, item.key)] = portion;
      locked.add(item);
    }
    final plan = await ref.read(planRunnerProvider)(
      PlannerInput(
        targets: targets,
        dishes: dishes,
        rules: catalogue.rules,
        locked: locked,
        recent: await _recentDishes(),
      ),
      seed ?? Random().nextInt(1 << 31),
    );
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        plan: plan,
        targets: targets,
        leftovers: _leftovers.keys.toSet(),
      ),
    );
  }

  /// Portions of the user's own cooked batches planned for a meal from
  /// today on in this week that the saved plan ([items]) no longer has
  /// (the dish was swapped or taken out) become leftovers, so they show in
  /// Prep and the next plan places them, instead of waiting in a meal that
  /// won't come. Household batches follow the household's week.
  Future<void> _keepUnplannedAsLeftovers(List<SavedPlanItem> items) async {
    final me = ref.read(currentUserIdProvider);
    final today = dayOf(DateTime.now());
    final planned = {
      for (final i in items)
        if (i.recipeId case final id?) (i.day, i.slot, id),
    };
    final moved = {for (final p in _leftovers.values) p.id};
    final weekEnd = addDays(weekStart, 7);
    final prep = ref.read(prepRepositoryProvider);
    for (final s in await ref.read(prepProvider.future)) {
      if (!s.cooked || s.isShared) continue;
      for (final p in s.openPortionsFor(me)) {
        final day = p.day;
        final slot = p.slot;
        if (day == null ||
            slot == null ||
            moved.contains(p.id) ||
            day.isBefore(today) ||
            day.isBefore(weekStart) ||
            !day.isBefore(weekEnd) ||
            planned.contains((day, slot, s.recipeId))) {
          continue;
        }
        await prep.updatePortion(
          p.copyWith(
            day: () => null,
            slot: () => null,
            status: PortionStatus.leftover,
          ),
        );
      }
    }
  }

  /// Last week's dishes, by key and by name, so this week tries others.
  /// Empty when there was no plan or it can't be loaded: variety is a nice
  /// extra, never a reason planning fails.
  Future<Set<String>> _recentDishes() async {
    try {
      final last = await ref
          .read(mealPlanRepositoryProvider)
          .fetchWeek(addDays(weekStart, -7));
      if (last == null) return const {};
      final names = {
        for (final r in await ref.read(recipesProvider.future)) r.id: r.name,
      };
      return {
        for (final i in last.items)
          if (i.recipeId case final id?) ...['recipe:$id', ?names[id]],
      };
    } on Object {
      return const {};
    }
  }

  /// The user's leftover portions of their own cooked batches (missed
  /// meals and portions kept for no meal, still within their use-by date),
  /// each as a locked item in the earliest free lunch or dinner from today.
  /// Household batches' leftovers are eaten from Prep.
  Future<List<(PrepPortion, PlannedItem)>> _leftoverItems(
    List<PlannedItem> locked,
  ) async {
    final me = ref.read(currentUserIdProvider);
    final today = dayOf(DateTime.now());
    final recipes = {
      for (final r in await ref.read(recipesProvider.future)) r.id: r,
    };
    final foods = {
      for (final f in await ref.read(foodsProvider.future)) f.id: f,
    };
    final recipeOf = <PrepPortion, Recipe>{};
    for (final s in await ref.read(prepProvider.future)) {
      final r = recipes[s.recipeId];
      if (!s.cooked || s.isShared || r == null) continue;
      for (final p in s.openPortionsFor(me)) {
        if (portionTiming(p, today) == PortionTiming.missed) recipeOf[p] = r;
      }
    }
    final placed = placeLeftovers(
      leftovers: recipeOf.keys.toList(),
      weekStart: weekStart,
      from: today,
      taken: (day, slot) =>
          locked.any((i) => i.day == day && i.slot == slot && i.isDish),
    );
    return [
      for (final MapEntry(key: p, value: (day, slot)) in placed.entries)
        (
          p,
          PlannedItem(
            day: day,
            slot: slot,
            key: 'recipe:${recipeOf[p]!.id}',
            name: recipeOf[p]!.name,
            amount: p.amount,
            isDish: true,
            perUnit: recipeNutrition(recipeOf[p]!, foods).perPortion,
            locked: true,
          ),
        ),
    ];
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
    ]..sort(
      // Favourites first, then by name.
      (a, b) => a.favourite != b.favourite
          ? (a.favourite ? -1 : 1)
          : a.name.compareTo(b.name),
    );
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
    // The household's dishes are changed in the household's week.
    if (current == null || plan == null || item.shared) return;
    bool same(PlannedItem i) =>
        i.day == item.day && i.slot == item.slot && i.key == item.key;
    // A leftover taken out (or swapped) stays a leftover in Prep.
    if (replacement?.key != item.key) {
      _leftovers.remove((item.day, item.slot, item.key));
    }
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        leftovers: _leftovers.keys.toSet(),
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
    final sharedAmounts = <String, double>{};
    for (final i in plan.items) {
      if (i.shared) {
        if (i.id case final id?) sharedAmounts[id] = i.amount;
        continue;
      }
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
    // The user's servings of the household's dishes, as fitted to their
    // day: those that changed, and estimates, which are now fitted (a
    // cooked batch's portions keep their amounts).
    final (sharedBefore, estimated) = await _sharedItems();
    final before = <String, double>{
      for (final i in sharedBefore) ?i.id: i.amount,
    };
    final changed = {
      for (final MapEntry(key: id, value: amount) in sharedAmounts.entries)
        if (before[id] != null &&
            (before[id] != amount || estimated.contains(id)))
          id: amount,
    };
    if (changed.isNotEmpty) await repository.updateAmounts(changed);
    // The leftovers the plan eats move to their meals.
    final prep = ref.read(prepRepositoryProvider);
    for (final i in plan.items) {
      if (_leftovers[(i.day, i.slot, i.key)] case final portion?) {
        await prep.updatePortion(
          portion.copyWith(
            day: () => current.dayOf(i.day),
            slot: () => i.slot,
            status: PortionStatus.planned,
          ),
        );
      }
    }
    await _keepUnplannedAsLeftovers(items);
    _leftovers = {};
    // Saving lays out the plan's prep sessions.
    ref.invalidate(prepProvider);
    // Read it back for the items' IDs, which re-planning a day needs.
    final saved = await repository.fetchWeek(weekStart);
    if (saved == null) return;
    final own = _fromSaved(saved, await ref.read(recipesProvider.future), {
      for (final f in await ref.read(foodsProvider.future)) f.id: f,
    });
    final (sharedAfter, stillEstimated) = await _sharedItems();
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        targets: saved.targets,
        plan: WeekPlan(
          items: _sorted([...own.items, ...sharedAfter]),
          notes: own.notes,
        ),
        saved: true,
        estimated: stillEstimated,
      ),
    );
  }

  /// Fetches the week again, unless it has changes not saved yet: another
  /// member may have planned the household's.
  void refresh() {
    final current = state.value;
    if (current == null || current.saved || current.plan == null) {
      ref.invalidateSelf();
    }
  }

  /// Fits the user's servings of the household's dishes to their own days
  /// (from today on), leaving the rest of their plan as it is: each day's
  /// servings take what the day's calories leave after the user's own
  /// items or, on a day with nothing else planned, their meals' usual
  /// share of it. Portions of cooked batches keep their amounts. Saved
  /// straight away.
  Future<void> fitShared() async {
    final current = state.value;
    final plan = current?.plan;
    if (current == null || plan == null || !current.saved) return;
    var targets = current.targets;
    if (targets == null) {
      final today = await ref.read(targetsProvider.future);
      if (today == null) throw const PlanNeedsTargets();
      targets = today.forWeek(weekStart);
    }
    final boxed = await _boxed();
    final today = dayOf(DateTime.now());
    final fitted = <PlannedItem>[];
    for (var d = 0; d < 7; d++) {
      final date = addDays(weekStart, d);
      final items = plan.itemsOn(d);
      final shared = [
        for (final i in items)
          if (i.shared) i,
      ];
      if (shared.isEmpty || date.isBefore(today)) {
        fitted.addAll(items);
        continue;
      }
      bool fixed(PlannedItem i) =>
          !i.shared || boxed.contains((date, i.slot, i.key));
      fitted.addAll(
        items.length > shared.length
            ? fitToKcal(items, targets[d].kcal, fixed: fixed)
            : fitToKcal(
                shared,
                targetsForMeals(targets[d], {
                  for (final i in shared) i.slot,
                }).kcal,
                fixed: fixed,
              ),
      );
    }
    final before = {for (final i in plan.items) ?i.id: i.amount};
    final changed = <String, double>{
      for (final i in fitted)
        if (i.shared && i.id != null)
          if (before[i.id] != i.amount || current.estimated.contains(i.id))
            i.id!: i.amount,
    };
    if (changed.isNotEmpty) {
      await ref.read(mealPlanRepositoryProvider).updateAmounts(changed);
      // Prep for batches not yet cooked follows the new amounts.
      ref.invalidate(prepProvider);
    }
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        targets: current.targets,
        saved: true,
        plan: WeekPlan(items: _sorted(fitted), notes: plan.notes),
      ),
    );
  }

  /// Re-plans the rest of [date] around what's been [eaten]: the saved
  /// plan's items not yet eaten are refitted to [target] (calories first,
  /// then protein and the other macros) within their ranges, and saved.
  /// Portions of batches already cooked stay as boxed. Returns the
  /// outcome, with a note when the day can't land near its targets.
  Future<DayReplan> replanDay({
    required DateTime date,
    required List<FoodLogEntry> eaten,
    required PlanTargets target,
  }) async {
    final current = state.value;
    final plan = current?.plan;
    if (current == null || plan == null || !current.saved) {
      throw const PlanNotSaved();
    }
    final day = daysBetween(weekStart, date);
    final remaining = remainingItems(plan.itemsOn(day), eaten);
    final me = ref.read(currentUserIdProvider);
    final boxed = <(String, MealSlot)>{
      for (final s in await ref.read(prepProvider.future))
        if (s.cooked)
          for (final p in s.openPortionsFor(me))
            if (p.day == date) ('recipe:${s.recipeId}', p.slot!),
    };
    final result = replanRestOfDay(
      remaining: remaining,
      eaten: Nutrition.sum(eaten.map((e) => e.nutrition)),
      target: target,
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
        estimated: latest.estimated.difference(changed.keys.toSet()),
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

  /// Takes [item], one of the user's own saved items, out of the plan: a
  /// meal they won't have. Its prep follows in the database (a cooked
  /// portion is kept as a leftover; a batch not yet cooked shrinks).
  /// Re-planning the rest of the day then makes up for it. The
  /// household's dishes are changed in the household's week.
  Future<void> skip(PlannedItem item) async {
    final current = state.value;
    final id = item.id;
    if (current == null || !current.saved || id == null || item.shared) {
      throw const PlanNotSaved();
    }
    await ref.read(mealPlanRepositoryProvider).skipItem(id);
    ref.invalidate(prepProvider);
    final latest = state.value ?? current;
    state = AsyncData(
      PlanState(
        weekStart: weekStart,
        targets: latest.targets,
        saved: true,
        estimated: latest.estimated,
        plan: WeekPlan(
          items: [
            for (final i in latest.plan?.items ?? const <PlannedItem>[])
              if (i.id != id) i,
          ],
          notes: latest.plan?.notes ?? const [],
        ),
      ),
    );
  }

  /// Logs [item] as eaten on [date], as planned: a food by its grams; a
  /// dish by its portion of the cooked batch (or of the recipe's weighed
  /// batch when it isn't prepped).
  Future<void> logPlanned(PlannedItem item, DateTime date) async {
    final log = ref.read(foodLogProvider(date).notifier);
    final foods = {
      for (final f in await ref.read(foodsProvider.future)) f.id: f,
      for (final f in await ref.read(sharedFoodsProvider.future)) f.id: f,
    };
    if (item.key.startsWith('food:')) {
      final food = foods[item.key.substring('food:'.length)];
      if (food == null) throw const PlanNotSaved();
      await log.add(slot: item.slot, food: food, grams: item.amount);
      return;
    }
    final recipeId = item.key.substring('recipe:'.length);
    final recipes = [
      ...await ref.read(recipesProvider.future),
      if (item.shared) ...await ref.read(sharedRecipesProvider.future),
    ];
    final recipe = recipes.where((r) => r.id == recipeId).firstOrNull;
    if (recipe == null) throw const PlanNotSaved();
    final me = ref.read(currentUserIdProvider);
    for (final s in await ref.read(prepProvider.future)) {
      if (s.recipeId != recipeId) continue;
      for (final p in s.openPortionsFor(me)) {
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

List<PlannedItem> _sorted(List<PlannedItem> items) => items
  ..sort((a, b) {
    final byDay = a.day.compareTo(b.day);
    return byDay != 0 ? byDay : a.slot.index.compareTo(b.slot.index);
  });

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
