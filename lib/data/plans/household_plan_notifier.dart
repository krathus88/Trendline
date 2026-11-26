import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show AsyncNotifierProviderFamily, ProviderListenable;
import 'package:meta/meta.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/goals/targets_provider.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/plans/meal_plan_repository.dart';
import 'package:trendline/data/plans/plan_notifier.dart';
import 'package:trendline/data/plans/planner_catalogue.dart';
import 'package:trendline/data/prep/prep_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/dish_template_providers.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/recipe.dart';

/// One shared dish in one meal, with each eater's servings.
@immutable
class SharedDish {
  const new({
    required this.day,
    required this.slot,
    required this.key,
    required this.name,
    required this.perPortion,
    required this.amounts,
    this.minAmount = 0.5,
    this.maxAmount = 1.75,
    this.batch,
    this.estimated = const {},
  });

  /// 0 = the week's Monday.
  final int day;
  final MealSlot slot;

  /// A planner candidate key (`recipe:<household recipe id>` once saved).
  final String key;
  final String name;
  final Nutrition perPortion;

  /// Portions per eater (user ID).
  final Map<String, double> amounts;
  final double minAmount;
  final double maxAmount;
  final int? batch;

  /// Eaters whose amount is an estimate: set by someone's planning, not yet
  /// fitted by the eater to their own day.
  final Set<String> estimated;

  double get totalPortions => amounts.values.fold(0, (s, a) => s + a);
}

/// The household's week as shown: saved, or freshly planned and not saved.
@immutable
class HouseholdPlanState {
  const new({
    required this.weekStart,
    this.dishes = const [],
    this.notes = const [],
    this.saved = false,
  });

  final DateTime weekStart;
  final List<SharedDish> dishes;
  final List<String> notes;

  /// Whether [dishes] is what's saved.
  final bool saved;

  /// The meals the week shares.
  Set<MealSlot> get meals => {for (final d in dishes) d.slot};
}

/// Expands each dish into a serving per [eaters]: the planning user's
/// amount as planned, everyone else's one portion (within the dish's
/// range). All are estimates until each eater fits theirs to their own day
/// (see [carryOver] for keeping what's been fitted already).
List<SharedDish> servingsFor(
  List<PlannedItem> dishes,
  String me,
  Iterable<String> eaters,
) => [
  for (final i in dishes)
    SharedDish(
      day: i.day,
      slot: i.slot,
      key: i.key,
      name: i.name,
      perPortion: i.perUnit,
      minAmount: i.minAmount ?? 0.5,
      maxAmount: i.maxAmount ?? 1.75,
      batch: i.batch,
      amounts: {
        for (final e in eaters)
          e: e == me
              ? i.amount
              : 1.0.clamp(i.minAmount ?? 0.5, i.maxAmount ?? 1.75),
      },
      estimated: {...eaters},
    ),
];

/// [fresh] dishes with each eater's servings carried over from the week as
/// it was saved ([before]), so planning again doesn't undo what members
/// fitted:
///
/// * the same dish in the same meal keeps its amount, fitted or not (the
///   database keeps it too, whatever is sent);
/// * a new dish starts at about the calories the eater had in that meal
///   before, or else their average in that kind of meal that week, within
///   the dish's range, as an estimate;
/// * otherwise the planned amount, as an estimate.
List<SharedDish> carryOver(List<SharedDish> fresh, List<SharedDish> before) {
  double kcalOf(SharedDish d, String eater) =>
      d.amounts[eater]! * d.perPortion.kcal;
  final bySlot = <(MealSlot, String), List<double>>{};
  for (final d in before) {
    for (final e in d.amounts.keys) {
      (bySlot[(d.slot, e)] ??= []).add(kcalOf(d, e));
    }
  }
  return [
    for (final d in fresh)
      () {
        final amounts = <String, double>{};
        final estimated = <String>{};
        for (final MapEntry(key: e, value: planned) in d.amounts.entries) {
          final meal = [
            for (final b in before)
              if (b.day == d.day &&
                  b.slot == d.slot &&
                  b.amounts.containsKey(e))
                b,
          ];
          final same = meal.where((b) => b.key == d.key).firstOrNull;
          if (same != null) {
            amounts[e] = same.amounts[e]!.clamp(d.minAmount, d.maxAmount);
            if (same.estimated.contains(e)) estimated.add(e);
            continue;
          }
          estimated.add(e);
          final slotKcal = bySlot[(d.slot, e)];
          final kcal = meal.isNotEmpty
              ? meal.fold<double>(0, (s, b) => s + kcalOf(b, e))
              : slotKcal == null
              ? null
              : slotKcal.reduce((a, b) => a + b) / slotKcal.length;
          amounts[e] = kcal == null || d.perPortion.kcal <= 0
              ? planned
              : ((kcal / d.perPortion.kcal).clamp(d.minAmount, d.maxAmount) *
                            20)
                        .round() /
                    20;
        }
        return SharedDish(
          day: d.day,
          slot: d.slot,
          key: d.key,
          name: d.name,
          perPortion: d.perPortion,
          minAmount: d.minAmount,
          maxAmount: d.maxAmount,
          batch: d.batch,
          amounts: amounts,
          estimated: estimated,
        );
      }(),
  ];
}

/// A candidate sized for a household: one cook feeds every eater, so a
/// recipe's portions last fewer days.
DishCandidate forEaters(DishCandidate d, int eaters) => DishCandidate(
  key: d.key,
  name: d.name,
  kind: d.kind,
  meals: d.meals,
  perPortion: d.perPortion,
  maxServingsPerBatch: max(1, d.maxServingsPerBatch ~/ max(1, eaters)),
  keepsDays: d.keepsDays,
  cuisine: d.cuisine,
  preference: d.preference,
  favourite: d.favourite,
  mainProtein: d.mainProtein,
  contains: d.contains,
  minServing: d.minServing,
  maxServing: d.maxServing,
);

/// The household's shared dishes for the week starting on the given Monday.
final AsyncNotifierProviderFamily<
  HouseholdPlanNotifier,
  HouseholdPlanState,
  DateTime
>
householdPlanProvider =
    AsyncNotifierProvider.family<
      HouseholdPlanNotifier,
      HouseholdPlanState,
      DateTime
    >(HouseholdPlanNotifier.new);

class HouseholdPlanNotifier extends AsyncNotifier<HouseholdPlanState> {
  new(this.weekStart);

  final DateTime weekStart;
  PlannerCatalogue? _catalogue;

  @override
  Future<HouseholdPlanState> build() async {
    if (ref.watch(householdIdProvider) == null) {
      return HouseholdPlanState(weekStart: weekStart);
    }
    for (final source in <ProviderListenable<Object?>>[
      sharedRecipesProvider,
      sharedFoodsProvider,
      foodsProvider,
      recipeLibraryProvider,
      libraryFoodsProvider,
      dishTemplatesProvider,
      templateFoodsProvider,
      householdFoodPreferencesProvider,
      targetsProvider,
    ]) {
      ref.listen(source, (_, _) {});
    }
    final week = await ref
        .watch(mealPlanRepositoryProvider)
        .fetchHouseholdWeek(weekStart);
    if (week == null) return HouseholdPlanState(weekStart: weekStart);
    return HouseholdPlanState(
      weekStart: weekStart,
      dishes: await _fromSaved(week),
      notes: week.notes,
      saved: true,
    );
  }

  Future<List<SharedDish>> _fromSaved(HouseholdWeek week) async {
    final recipes = {
      for (final r in await ref.read(sharedRecipesProvider.future)) r.id: r,
    };
    final foods = {
      for (final f in await ref.read(sharedFoodsProvider.future)) f.id: f,
    };
    final byMeal = <(DateTime, MealSlot, String), List<SavedPlanItem>>{};
    for (final i in week.items) {
      final id = i.recipeId;
      if (id == null || i.eaterId == null) continue;
      (byMeal[(i.day, i.slot, id)] ??= []).add(i);
    }
    return [
      for (final MapEntry(key: (day, slot, id), value: items) in byMeal.entries)
        if (recipes[id] case final r?)
          SharedDish(
            day: daysBetween(weekStart, day),
            slot: slot,
            key: 'recipe:$id',
            name: r.name,
            perPortion: recipeNutrition(r, foods).perPortion,
            minAmount: items.first.amountMin ?? 0.5,
            maxAmount: items.first.amountMax ?? 1.75,
            batch: items.first.batch,
            amounts: {for (final i in items) i.eaterId!: i.amount},
            estimated: {
              for (final i in items)
                if (i.estimated) i.eaterId!,
            },
          ),
    ]..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.slot.index.compareTo(b.slot.index);
    });
  }

  Future<PlannerCatalogue> _buildCatalogue() async {
    Future<T?> orNull<T>(Future<T> f) async {
      try {
        return await f;
      } on Object {
        return null;
      }
    }

    final shared = await ref.read(sharedRecipesProvider.future);
    return _catalogue = buildCatalogue(
      PlannerSources(
        // The household's recipes, and the library and templates; not the
        // member's own recipes (they can share one first).
        recipes: shared,
        foods: {
          for (final f in await ref.read(sharedFoodsProvider.future)) f.id: f,
        },
        library:
            await orNull(ref.read(recipeLibraryProvider.future)) ?? const [],
        libraryFoods:
            await orNull(ref.read(libraryFoodsProvider.future)) ?? const {},
        templates: await orNull(ref.read(dishTemplatesProvider.future)),
        templateFoods:
            await orNull(ref.read(templateFoodsProvider.future)) ?? const {},
        // Everyone's preferences, combined: a food anyone never wants is
        // left out.
        preferences: await ref.read(householdFoodPreferencesProvider.future),
        rules: const [],
        // Everyone's stars, combined: fetched each time, since other
        // members' changes aren't signalled to this device.
        favourites:
            await orNull(
              ref.read(householdRepositoryProvider).fetchRecipeFavourites(),
            ) ??
            const {},
      ),
    );
  }

  /// The household's dishes last week, by key and by name, so this week
  /// tries others. Empty when there was no week or it can't be loaded.
  Future<Set<String>> _recentDishes() async {
    try {
      final last = await ref
          .read(mealPlanRepositoryProvider)
          .fetchHouseholdWeek(addDays(weekStart, -7));
      if (last == null) return const {};
      final names = {
        for (final r in await ref.read(sharedRecipesProvider.future))
          r.id: r.name,
      };
      return {
        for (final i in last.items)
          if (i.recipeId case final id?) ...['recipe:$id', ?names[id]],
      };
    } on Object {
      return const {};
    }
  }

  /// Plans the shared [meals] for every member: the dishes are chosen
  /// under everyone's preferences and sized against the planning member's
  /// day. Servings that stay as they were keep their amounts; the rest are
  /// estimates each member fits when they plan their week.
  Future<void> generate({required Set<MealSlot> meals, int? seed}) async {
    final household = ref.read(householdProvider).value;
    final me = ref.read(currentUserIdProvider);
    if (household == null || me == null || meals.isEmpty) return;
    final today = await ref.read(targetsProvider.future);
    if (today == null) throw const PlanNeedsTargets();
    final targets = [
      for (final t in today.forWeek(weekStart)) targetsForMeals(t, meals),
    ];
    final catalogue = await _buildCatalogue();
    final eaters = household.members.length;
    final ordered = [
      for (final m in plannedMeals)
        if (meals.contains(m)) m,
    ];
    final plan = await ref.read(planRunnerProvider)(
      PlannerInput(
        targets: targets,
        dishes: [
          for (final d in catalogue.dishes)
            if (d.meals.any(meals.contains)) forEaters(d, eaters),
        ],
        meals: ordered,
        recent: await _recentDishes(),
      ),
      seed ?? Random().nextInt(1 << 31),
    );
    final saved = await ref
        .read(mealPlanRepositoryProvider)
        .fetchHouseholdWeek(weekStart);
    state = AsyncData(
      HouseholdPlanState(
        weekStart: weekStart,
        dishes: carryOver(
          servingsFor(plan.items, me, [
            for (final m in household.members) m.userId,
          ]),
          saved == null ? const [] : await _fromSaved(saved),
        ),
        notes: [
          for (final n in plan.notes)
            if (!n.startsWith('Day ')) n,
        ],
      ),
    );
  }

  /// Saves the week for everyone. Library and template dishes are copied
  /// into the household's recipes first (template ones hidden until kept).
  /// The database lays out the joint prep as it saves.
  Future<void> save() async {
    final current = state.value;
    final household = ref.read(householdProvider).value;
    if (current == null || household == null) return;
    final recipeIds = <String, String>{};

    Future<String?> recipeFor(String key) async {
      if (recipeIds[key] case final id?) return id;
      final catalogue = _catalogue;
      final recipes = ref.read(recipesProvider.notifier);
      String? id;
      if (key.startsWith('recipe:')) {
        id = key.substring('recipe:'.length);
      } else if (catalogue?.library[key] case final library?) {
        id = (await recipes.addFromLibrary(
          library,
          householdId: household.id,
        )).id;
      } else if (catalogue?.generated[key] case final option?) {
        final made = option.dish.madeWeightG;
        final copy = await recipes.addFromLibrary(
          option.dish.toRecipe(),
          origin: RecipeOrigin.template,
          foods: await ref.read(templateFoodsProvider.future),
          estimatedCookedWeightG: made == null ? option.expectedCookedG : null,
          cookedWeightG: made,
          householdId: household.id,
        );
        await ref
            .read(sharedRecipesProvider.notifier)
            .setListed(copy.id, listed: false);
        id = copy.id;
      }
      if (id != null) recipeIds[key] = id;
      return id;
    }

    final items = <SavedPlanItem>[];
    for (final d in current.dishes) {
      final recipeId = await recipeFor(d.key);
      if (recipeId == null) continue;
      for (final MapEntry(key: eater, value: amount) in d.amounts.entries) {
        // Someone who left since the plan was made.
        if (household.memberFor(eater) == null) continue;
        items.add(
          SavedPlanItem(
            day: addDays(weekStart, d.day),
            slot: d.slot,
            recipeId: recipeId,
            eaterId: eater,
            amount: amount,
            amountMin: d.minAmount,
            amountMax: d.maxAmount,
            batch: d.batch,
          ),
        );
      }
    }
    final repository = ref.read(mealPlanRepositoryProvider);
    await repository.saveHouseholdWeek(
      HouseholdWeek(weekStart: weekStart, notes: current.notes, items: items),
    );
    // Each member's own week shows their servings.
    ref
      ..invalidate(prepProvider)
      ..invalidate(sharedFoodsProvider)
      ..invalidate(planProvider(weekStart));
    final saved = await repository.fetchHouseholdWeek(weekStart);
    state = AsyncData(
      HouseholdPlanState(
        weekStart: weekStart,
        dishes: saved == null ? const [] : await _fromSaved(saved),
        notes: saved?.notes ?? const [],
        saved: saved != null,
      ),
    );
  }

  /// Fetches the week again, unless it has changes not saved yet: another
  /// member may have planned it.
  void refresh() {
    final current = state.value;
    if (current == null || current.saved || current.dishes.isEmpty) {
      ref.invalidateSelf();
    }
  }

  /// Takes [dish] out of the unsaved week.
  void remove(SharedDish dish) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      HouseholdPlanState(
        weekStart: weekStart,
        notes: current.notes,
        dishes: [
          for (final d in current.dishes)
            if (!identical(d, dish)) d,
        ],
      ),
    );
  }

  /// The names members show each other, by user ID.
  Map<String, String> memberNames() => {
    for (final m
        in ref.read(householdProvider).value?.members ??
            const <HouseholdMember>[])
      m.userId: m.displayName,
  };
}

/// Fetches again what other household members may have changed: the
/// household, its recipes and batches, and this and next week's plans
/// (those open with changes not saved yet are left alone). Run when the app
/// comes back to the foreground and on pull to refresh, so a household week
/// someone else planned shows up without restarting.
final householdRefreshProvider = Provider<void Function()>(
  (ref) => () {
    if (ref.read(householdIdProvider) == null) return;
    ref
      ..invalidate(householdProvider)
      ..invalidate(sharedRecipesProvider)
      ..invalidate(sharedFoodsProvider)
      ..invalidate(householdFoodPreferencesProvider)
      ..invalidate(prepProvider);
    final thisWeek = weekStartOf(DateTime.now());
    for (final week in [thisWeek, addDays(thisWeek, 7)]) {
      if (ref.read(planProvider(week).exists)) {
        ref.read(planProvider(week).notifier).refresh();
      }
      if (ref.read(householdPlanProvider(week).exists)) {
        ref.read(householdPlanProvider(week).notifier).refresh();
      }
    }
  },
);
