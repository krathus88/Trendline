import 'dart:math';

import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe_library.dart';

/// Meals the planner fills with dishes. Snacks hold rule items (a daily
/// yoghurt, a piece of fruit) rather than cooked dishes.
const List<MealSlot> dishMeals = [
  MealSlot.breakfast,
  MealSlot.lunch,
  MealSlot.dinner,
];

/// A day's targets for the plan.
@immutable
class PlanTargets {
  const new({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fibreG,
  });

  final double kcal;

  /// A minimum: going over isn't penalised.
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// A minimum, like protein.
  final double fibreG;
}

enum CandidateKind { recipe, library, template }

/// A dish the planner can serve, in portions.
@immutable
class DishCandidate {
  const new({
    required this.key,
    required this.name,
    required this.kind,
    required this.meals,
    required this.perPortion,
    required this.maxServingsPerBatch,
    required this.keepsDays,
    this.cuisine,
    this.preference = 1,
    this.contains = const {},
    this.minServing = 0.5,
    this.maxServing = 1.75,
  });

  /// Stable for this dish: `recipe:<id>`, `library:<id>`,
  /// `template:<id>:<variant>`.
  final String key;
  final String name;
  final CandidateKind kind;
  final Set<MealSlot> meals;
  final Nutrition perPortion;

  /// Servings one cook can give: a recipe's portions; a library or template
  /// dish can be scaled, so this is just a sensible cap.
  final int maxServingsPerBatch;

  /// Days it keeps in the fridge after cooking. A batch spans at most
  /// [keepsDays] + 1 days.
  final int keepsDays;
  final Cuisine? cuisine;

  /// From the user's preferences: 3 liked, 1 neutral, 0.25 disliked.
  final double preference;

  /// Rule targets it includes (`food:<id>`, `recipe:<id>`), so a rule like
  /// "salmon twice a week" can be met by dishes with salmon in.
  final Set<String> contains;

  /// Portions one serving may be scaled between.
  final double minServing;
  final double maxServing;

  int get maxRun => min(keepsDays + 1, maxServingsPerBatch);
}

/// A meal rule with what the planner needs to place it.
@immutable
class PlannerRule {
  const new({required this.rule, required this.name, required this.perUnit});

  final MealRule rule;
  final String name;

  /// Nutrition per gram (a food) or per portion (a recipe).
  final Nutrition perUnit;

  /// `food:<id>` or `recipe:<id>`.
  String get target =>
      rule.isRecipe ? 'recipe:${rule.recipeId}' : 'food:${rule.foodId}';
}

/// One item in the plan: a dish serving, or a rule item.
@immutable
class PlannedItem {
  const new({
    required this.day,
    required this.slot,
    required this.key,
    required this.name,
    required this.amount,
    required this.isDish,
    required this.perUnit,
    this.minAmount,
    this.maxAmount,
    this.locked = false,
    this.batch,
    this.ruleId,
    this.id,
  });

  /// 0 = the plan's first day.
  final int day;
  final MealSlot slot;

  /// A [DishCandidate.key], or a rule target (`food:<id>`, `recipe:<id>`).
  final String key;
  final String name;

  /// Portions (a dish or a recipe) or grams (a food).
  final double amount;
  final bool isDish;
  final Nutrition perUnit;

  /// The range [amount] may be fitted within; null means fixed.
  final double? minAmount;
  final double? maxAmount;
  final bool locked;

  /// Servings of the same dish cooked once share a batch number.
  final int? batch;

  /// The rule that put it here, if one did.
  final String? ruleId;

  /// The saved plan item's ID; null until saved.
  final String? id;

  Nutrition get nutrition => _times(perUnit, amount);

  bool get isPortions => isDish || key.startsWith('recipe:');

  PlannedItem copyWith({double? amount, bool? locked, int? batch}) =>
      PlannedItem(
        day: day,
        slot: slot,
        key: key,
        name: name,
        amount: amount ?? this.amount,
        isDish: isDish,
        perUnit: perUnit,
        minAmount: minAmount,
        maxAmount: maxAmount,
        locked: locked ?? this.locked,
        batch: batch ?? this.batch,
        ruleId: ruleId,
        id: id,
      );
}

/// A planned week.
@immutable
class WeekPlan {
  const new({required this.items, required this.notes});

  final List<PlannedItem> items;

  /// Things the plan couldn't do (a rule it couldn't keep, a day that
  /// misses its calories), to show the user. Never silent.
  final List<String> notes;

  List<PlannedItem> itemsOn(int day) => [
    for (final i in items)
      if (i.day == day) i,
  ];

  Nutrition totalOn(int day) =>
      Nutrition.sum([for (final i in itemsOn(day)) i.nutrition]);
}

/// Everything the planner needs.
@immutable
class PlannerInput {
  const new({
    required this.targets,
    required this.dishes,
    this.rules = const [],
    this.locked = const [],
    this.days = 7,
    this.iterations = 4000,
  });

  /// Each day's targets, in order ([days] of them; the last repeats).
  final List<PlanTargets> targets;
  final List<DishCandidate> dishes;
  final List<PlannerRule> rules;

  /// Items the user locked: kept as they are.
  final List<PlannedItem> locked;
  final int days;
  final int iterations;

  PlanTargets targetOn(int day) => targets[min(day, targets.length - 1)];
}

// ---------------------------------------------------------------------------
// Scoring weights, in one place so they can be tuned (see PLAN.md risks).
// ---------------------------------------------------------------------------

const double _wKcal = 10;
const double _wProteinShort = 6;
const double _wFat = 1;
const double _wCarbs = 1;
const double _wFibreShort = 1;
const double _wSameDishSameDay = 0.5;
const double _wRepeatBatch = 0.3;
const double _wCookSession = 0.08;
const double _wPreference = 0.25;
const double _wRuleBroken = 5;

/// Plans [input]'s days: dishes for breakfast, lunch and dinner, cooked in
/// batches that keep, plus the rule items; amounts fitted to each day's
/// targets. [random] drives the search, so a seed gives the same plan.
///
/// Rules: daily ones go in every day; "at least" ones count dishes that
/// contain the food or recipe, and the planner places the item itself only
/// where dishes fall short; "at most" ones are penalised when broken.
/// Anything it couldn't keep is reported in [WeekPlan.notes].
WeekPlan planWeek(PlannerInput input, Random random) {
  final days = input.days;
  final dishesBySlot = {
    for (final slot in dishMeals)
      slot: [
        for (final d in input.dishes)
          if (d.meals.contains(slot)) d,
      ],
  };
  final byKey = {for (final d in input.dishes) d.key: d};

  // Days already taken in each dish meal (a locked dish, or a recipe placed
  // by a rule).
  final fixed = <PlannedItem>[...input.locked];
  final notes = <String>[];
  for (final r in input.rules) {
    if (r.rule.frequency != RuleFrequency.daily) continue;
    for (var d = 0; d < days; d++) {
      final slot = r.rule.slot ?? MealSlot.snack;
      if (fixed.any((i) => i.day == d && i.key == r.target)) continue;
      fixed.add(_ruleItem(r, d, slot));
    }
  }
  bool taken(MealSlot slot, int day) => fixed.any(
    (i) => i.day == day && i.slot == slot && (i.isDish || i.isPortions),
  );

  // The search state: for each dish meal, a dish key per day (null: free
  // and empty, or taken).
  final assign = {
    for (final slot in dishMeals) slot: List<String?>.filled(days, null),
  };

  // Greedy start: fill each meal with runs of dishes that keep.
  for (final slot in dishMeals) {
    final options = dishesBySlot[slot]!;
    if (options.isEmpty) continue;
    var d = 0;
    while (d < days) {
      if (taken(slot, d)) {
        d++;
        continue;
      }
      final dish = _pick(options, random);
      for (var k = 0; k < dish.maxRun && d < days && !taken(slot, d); k++) {
        assign[slot]![d++] = dish.key;
      }
    }
  }

  var current = _build(input, fixed, assign, byKey);
  var currentCost = _cost(input, current, byKey);
  var best = current;
  var bestCost = currentCost;

  // Simulated annealing: change a run of days in one meal to another dish.
  final free = [
    for (final slot in dishMeals)
      if (dishesBySlot[slot]!.isNotEmpty)
        for (var d = 0; d < days; d++)
          if (!taken(slot, d)) (slot: slot, day: d),
  ];
  if (free.isNotEmpty) {
    for (var it = 0; it < input.iterations; it++) {
      final temperature = 1.0 * pow(0.002, it / input.iterations);
      final spot = free[random.nextInt(free.length)];
      final dish = _pick(dishesBySlot[spot.slot]!, random);
      final row = assign[spot.slot]!;
      final saved = List<String?>.of(row);
      final run = 1 + random.nextInt(dish.maxRun);
      for (var k = 0; k < run; k++) {
        final d = spot.day + k;
        if (d >= days || taken(spot.slot, d)) break;
        row[d] = dish.key;
      }
      final candidate = _build(input, fixed, assign, byKey);
      final cost = _cost(input, candidate, byKey);
      final accept =
          cost <= currentCost ||
          random.nextDouble() < exp((currentCost - cost) / temperature);
      if (accept) {
        current = candidate;
        currentCost = cost;
        if (cost < bestCost) {
          best = candidate;
          bestCost = cost;
        }
      } else {
        assign[spot.slot] = saved;
      }
    }
  }

  // "At least" rules the dishes didn't meet: place the item itself.
  final items = [...best];
  for (final r in input.rules) {
    if (r.rule.frequency != RuleFrequency.minPerWeek) continue;
    var have = _count(items, r.target, byKey);
    final need = r.rule.timesPerWeek!;
    for (var step = 0; have < need && step < days; step++) {
      // Spread the days: 0, 3, 6, 1, 4, ...
      final d = (step * 3) % days;
      final slot = r.rule.slot ?? MealSlot.dinner;
      if (items.any((i) => i.day == d && i.key == r.target)) continue;
      items.add(_ruleItem(r, d, slot));
      have++;
    }
    if (have < need) {
      notes.add('${r.name}: could only fit $have of $need this week.');
    }
  }
  final fitted = _fitDays(input, items);

  for (final r in input.rules) {
    if (r.rule.frequency != RuleFrequency.maxPerWeek) continue;
    final have = _count(fitted, r.target, byKey);
    if (have > r.rule.timesPerWeek!) {
      notes.add(
        '${r.name}: in $have meals, over your limit of '
        '${r.rule.timesPerWeek}.',
      );
    }
  }
  for (var d = 0; d < days; d++) {
    final target = input.targetOn(d).kcal;
    final total = Nutrition.sum([
      for (final i in fitted)
        if (i.day == d) i.nutrition,
    ]).kcal;
    if ((total - target).abs() > target * 0.1) {
      notes.add(
        'Day ${d + 1}: ${total.round()} kcal against ${target.round()}. '
        'Add recipes, or widen rule amounts, to get closer.',
      );
    }
  }
  for (final slot in dishMeals) {
    if (dishesBySlot[slot]!.isEmpty &&
        !List.generate(days, (d) => taken(slot, d)).every((t) => t)) {
      notes.add('No dishes suit ${slot.name}, so it’s left empty.');
    }
  }

  return WeekPlan(items: _numberBatches(fitted, byKey), notes: notes);
}

DishCandidate _pick(List<DishCandidate> options, Random random) {
  final total = options.fold<double>(0, (s, d) => s + d.preference);
  var r = random.nextDouble() * total;
  for (final d in options) {
    r -= d.preference;
    if (r <= 0) return d;
  }
  return options.last;
}

PlannedItem _ruleItem(PlannerRule r, int day, MealSlot slot) => PlannedItem(
  day: day,
  slot: slot,
  key: r.target,
  name: r.name,
  amount: (r.rule.amountMin + r.rule.amountMax) / 2,
  isDish: false,
  perUnit: r.perUnit,
  minAmount: r.rule.amountMin,
  maxAmount: r.rule.amountMax,
  ruleId: r.rule.id,
);

/// The plan's items from the fixed ones and the dish assignment, with each
/// day's amounts fitted.
List<PlannedItem> _build(
  PlannerInput input,
  List<PlannedItem> fixed,
  Map<MealSlot, List<String?>> assign,
  Map<String, DishCandidate> byKey,
) {
  final items = <PlannedItem>[...fixed];
  for (final MapEntry(key: slot, value: row) in assign.entries) {
    for (final (d, key) in row.indexed) {
      final dish = key == null ? null : byKey[key];
      if (dish == null) continue;
      items.add(
        PlannedItem(
          day: d,
          slot: slot,
          key: dish.key,
          name: dish.name,
          amount: 1,
          isDish: true,
          perUnit: dish.perPortion,
          minAmount: dish.minServing,
          maxAmount: dish.maxServing,
        ),
      );
    }
  }
  return _fitDays(input, items);
}

/// Fits each day's amounts to its calories (see [fitToKcal]).
List<PlannedItem> _fitDays(PlannerInput input, List<PlannedItem> items) => [
  for (var d = 0; d < input.days; d++)
    ...fitToKcal([
      for (final i in items)
        if (i.day == d) i,
    ], input.targetOn(d).kcal),
];

/// Scales [items]' flexible amounts together so they add up to [kcal] as
/// closely as their ranges allow, rounded to practical amounts. Locked
/// items, items with no range and any [fixed] stay as they are.
List<PlannedItem> fitToKcal(
  List<PlannedItem> items,
  double kcal, {
  bool Function(PlannedItem item)? fixed,
}) {
  var out = items;
  // Two passes: items clamped in the first leave the rest to make up.
  for (var pass = 0; pass < 2; pass++) {
    bool flexible(PlannedItem i) =>
        !i.locked &&
        !(fixed?.call(i) ?? false) &&
        i.minAmount != null &&
        i.maxAmount != null &&
        i.minAmount! < i.maxAmount! &&
        (pass == 0 || (i.amount > i.minAmount! && i.amount < i.maxAmount!));
    final fixedKcal = out
        .where((i) => !flexible(i))
        .fold<double>(0, (s, i) => s + i.nutrition.kcal);
    final flexKcal = out
        .where(flexible)
        .fold<double>(0, (s, i) => s + i.nutrition.kcal);
    if (flexKcal <= 0) break;
    final factor = max(0, kcal - fixedKcal) / flexKcal;
    out = [
      for (final i in out)
        if (flexible(i))
          i.copyWith(
            amount: _round(
              (i.amount * factor).clamp(i.minAmount!, i.maxAmount!),
              portions: i.isPortions,
            ),
          )
        else
          i,
    ];
  }
  return out;
}

/// Portions to the nearest 0.05; grams to the nearest 5.
double _round(double v, {required bool portions}) =>
    portions ? (v * 20).round() / 20 : (v / 5).round() * 5;

double _cost(
  PlannerInput input,
  List<PlannedItem> items,
  Map<String, DishCandidate> byKey,
) {
  var cost = 0.0;
  for (var d = 0; d < input.days; d++) {
    final t = input.targetOn(d);
    final day = [
      for (final i in items)
        if (i.day == d) i,
    ];
    final n = Nutrition.sum([for (final i in day) i.nutrition]);
    double sq(double v) => v * v;
    cost += _wKcal * sq((n.kcal - t.kcal) / t.kcal);
    cost += _wProteinShort * sq(max(0, t.proteinG - n.proteinG) / t.proteinG);
    cost += _wFat * sq((n.fatG - t.fatG) / t.fatG);
    cost += _wCarbs * sq((n.carbsG - t.carbsG) / max(t.carbsG, 1));
    cost += _wFibreShort * sq(max(0, t.fibreG - n.fibreG) / t.fibreG);
    final dishes = [
      for (final i in day)
        if (i.isDish) i.key,
    ];
    cost += _wSameDishSameDay * (dishes.length - dishes.toSet().length);
  }
  for (final i in items) {
    final dish = byKey[i.key];
    if (dish != null) cost -= _wPreference * log(dish.preference);
  }
  final batches = _batches(items, byKey);
  cost += _wCookSession * batches.length;
  final perDish = <String, int>{};
  for (final b in batches) {
    perDish[b.key] = (perDish[b.key] ?? 0) + 1;
  }
  for (final n in perDish.values) {
    cost += _wRepeatBatch * (n - 1);
  }
  for (final r in input.rules) {
    final have = _count(items, r.target, byKey);
    final times = r.rule.timesPerWeek;
    if (times == null) continue;
    if (r.rule.frequency == RuleFrequency.maxPerWeek && have > times) {
      cost += _wRuleBroken * (have - times);
    }
    if (r.rule.frequency == RuleFrequency.minPerWeek && have < times) {
      // Softer: the planner can place the item itself afterwards.
      cost += _wRuleBroken * 0.2 * (times - have);
    }
  }
  return cost;
}

/// How many meals include [target], directly or inside a dish.
int _count(
  List<PlannedItem> items,
  String target,
  Map<String, DishCandidate> byKey,
) => items
    .where(
      (i) =>
          i.key == target || (byKey[i.key]?.contains.contains(target) ?? false),
    )
    .length;

/// Servings of one dish on consecutive days in one meal, split where a
/// batch would outlast the fridge or the recipe's portions.
List<({String key, MealSlot slot, int start, int length})> _batches(
  List<PlannedItem> items,
  Map<String, DishCandidate> byKey,
) {
  final out = <({String key, MealSlot slot, int start, int length})>[];
  for (final slot in dishMeals) {
    final row = {
      for (final i in items)
        if (i.slot == slot && i.isDish) i.day: i.key,
    };
    final days = row.keys.toList()..sort();
    for (final d in days) {
      final key = row[d]!;
      final last = out.isEmpty ? null : out.last;
      final cap = byKey[key]?.maxRun ?? 1;
      if (last != null &&
          last.key == key &&
          last.slot == slot &&
          last.start + last.length == d &&
          last.length < cap) {
        out[out.length - 1] = (
          key: key,
          slot: slot,
          start: last.start,
          length: last.length + 1,
        );
      } else {
        out.add((key: key, slot: slot, start: d, length: 1));
      }
    }
  }
  return out;
}

List<PlannedItem> _numberBatches(
  List<PlannedItem> items,
  Map<String, DishCandidate> byKey,
) {
  final batches = _batches(items, byKey);
  int? batchOf(PlannedItem i) {
    if (!i.isDish) return null;
    for (final (n, b) in batches.indexed) {
      if (b.key == i.key &&
          b.slot == i.slot &&
          i.day >= b.start &&
          i.day < b.start + b.length) {
        return n;
      }
    }
    return null;
  }

  final numbered = [for (final i in items) i.copyWith(batch: batchOf(i))]
    ..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.slot.index.compareTo(b.slot.index);
    });
  return numbered;
}

Nutrition _times(Nutrition n, double f) => Nutrition(
  kcal: n.kcal * f,
  proteinG: n.proteinG * f,
  carbsG: n.carbsG * f,
  fatG: n.fatG * f,
  fibreG: n.fibreG * f,
  fibreUnknown: n.fibreUnknown,
);
