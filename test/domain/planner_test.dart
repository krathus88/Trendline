import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/recipe_library.dart';

DishCandidate _dish(
  String key,
  Set<MealSlot> meals,
  Nutrition n, {
  int keeps = 3,
  int servings = 4,
  Set<String> contains = const {},
  double preference = 1,
}) => DishCandidate(
  key: key,
  name: key,
  kind: CandidateKind.library,
  meals: meals,
  perPortion: n,
  maxServingsPerBatch: servings,
  keepsDays: keeps,
  contains: contains,
  preference: preference,
);

const Set<MealSlot> _mains = {MealSlot.lunch, MealSlot.dinner};
final List<DishCandidate> _dishes = [
  _dish(
    'chicken-rice',
    _mains,
    const Nutrition(kcal: 520, proteinG: 45, carbsG: 55, fatG: 10, fibreG: 5),
  ),
  _dish(
    'chilli',
    _mains,
    const Nutrition(kcal: 520, proteinG: 40, carbsG: 55, fatG: 12, fibreG: 9),
  ),
  _dish(
    'lentil-soup',
    _mains,
    const Nutrition(kcal: 250, proteinG: 16, carbsG: 36, fatG: 4, fibreG: 8),
    keeps: 4,
  ),
  _dish(
    'salmon-traybake',
    {MealSlot.dinner},
    const Nutrition(kcal: 490, proteinG: 33, carbsG: 33, fatG: 25, fibreG: 5),
    keeps: 1,
    servings: 2,
    contains: {'food:salmon'},
  ),
  _dish(
    'oats',
    {MealSlot.breakfast},
    const Nutrition(kcal: 360, proteinG: 14, carbsG: 49, fatG: 12, fibreG: 6),
    keeps: 2,
  ),
  _dish(
    'omelette',
    {MealSlot.breakfast, MealSlot.lunch},
    const Nutrition(kcal: 360, proteinG: 30, carbsG: 2, fatG: 26, fibreG: 2),
    keeps: 0,
    servings: 1,
  ),
];

const _targets = PlanTargets(
  kcal: 2000,
  proteinG: 140,
  carbsG: 200,
  fatG: 65,
  fibreG: 30,
);

const _cappuccino = PlannerRule(
  rule: MealRule(
    id: 'cap',
    foodId: 'cappuccino',
    slot: MealSlot.breakfast,
    frequency: RuleFrequency.daily,
    amountMin: 250,
    amountMax: 250,
  ),
  name: 'Cappuccino',
  perUnit: Nutrition(kcal: 0.4, proteinG: 0.02, carbsG: 0.04, fatG: 0.015),
);

WeekPlan _plan({
  List<DishCandidate>? dishes,
  List<PlannerRule> rules = const [],
  List<PlannedItem> locked = const [],
  PlanTargets targets = _targets,
  int seed = 1,
}) => planWeek(
  PlannerInput(
    targets: [targets],
    dishes: dishes ?? _dishes,
    rules: rules,
    locked: locked,
  ),
  Random(seed),
);

void main() {
  test('fills every dish meal on every day', () {
    final plan = _plan();
    for (var d = 0; d < 7; d++) {
      final meals = plan.itemsOn(d).map((i) => i.slot).toSet();
      expect(meals, containsAll(dishMeals), reason: 'day $d');
    }
  });

  test('lands each day near its calories and protein', () {
    for (final seed in [1, 2, 3]) {
      final plan = _plan(seed: seed);
      for (var d = 0; d < 7; d++) {
        final n = plan.totalOn(d);
        expect(n.kcal, closeTo(2000, 200), reason: 'seed $seed day $d');
        expect(n.proteinG, greaterThan(140 * 0.75), reason: 'day $d');
      }
      expect(
        plan.notes.where((n) => n.contains('kcal')),
        isEmpty,
        reason: 'no day missed',
      );
    }
  });

  test('the same seed gives the same plan', () {
    final a = _plan(seed: 9).items.map((i) => '${i.day}${i.key}${i.amount}');
    final b = _plan(seed: 9).items.map((i) => '${i.day}${i.key}${i.amount}');
    expect(a, b);
  });

  test('batches never outlast the fridge or the portions', () {
    final byKey = {for (final d in _dishes) d.key: d};
    for (final seed in [1, 2, 3, 4]) {
      final plan = _plan(seed: seed);
      final batches = <int, List<PlannedItem>>{};
      for (final i in plan.items) {
        if (i.batch != null) (batches[i.batch!] ??= []).add(i);
      }
      for (final servings in batches.values) {
        final dish = byKey[servings.first.key]!;
        expect(servings.length, lessThanOrEqualTo(dish.maxRun));
        final days = servings.map((s) => s.day).toList()..sort();
        expect(days.last - days.first, lessThanOrEqualTo(dish.keepsDays));
      }
    }
  });

  test('serving sizes stay within each dish’s range', () {
    for (final i in _plan().items.where((i) => i.isDish)) {
      expect(i.amount, inInclusiveRange(0.5, 1.75));
    }
  });

  test('a daily rule is in every day, at its fixed amount', () {
    final plan = _plan(rules: [_cappuccino]);
    for (var d = 0; d < 7; d++) {
      final cap = plan.itemsOn(d).where((i) => i.key == 'food:cappuccino');
      expect(cap, hasLength(1));
      expect(cap.single.slot, MealSlot.breakfast);
      expect(cap.single.amount, 250);
    }
  });

  test('a daily dish recipe takes its meal; a drink mix sits beside one', () {
    PlannerRule daily(String id, {required bool isMeal}) => PlannerRule(
      rule: MealRule(
        id: id,
        recipeId: id,
        slot: MealSlot.breakfast,
        frequency: RuleFrequency.daily,
        amountMin: 1,
        amountMax: 1,
      ),
      name: id,
      perUnit: const Nutrition(kcal: 160, proteinG: 8, carbsG: 20, fatG: 5),
      isMeal: isMeal,
    );

    final withMix = _plan(rules: [daily('latte', isMeal: false)]);
    final withDish = _plan(rules: [daily('porridge', isMeal: true)]);
    for (var d = 0; d < 7; d++) {
      final mixBreakfast = withMix
          .itemsOn(d)
          .where((i) => i.slot == MealSlot.breakfast);
      expect(mixBreakfast.map((i) => i.key), contains('recipe:latte'));
      expect(
        mixBreakfast.where((i) => i.isDish),
        hasLength(1),
        reason: 'day $d still gets a breakfast dish',
      );

      final dishBreakfast = withDish
          .itemsOn(d)
          .where((i) => i.slot == MealSlot.breakfast);
      expect(dishBreakfast.map((i) => i.key), ['recipe:porridge']);
    }
  });

  group('snacks', () {
    final snacks = [
      for (final (i, kcal) in [180.0, 220.0, 250.0].indexed)
        _dish(
          'snack-$i',
          {MealSlot.snack},
          Nutrition(kcal: kcal, proteinG: 10, carbsG: 20, fatG: 8, fibreG: 3),
          keeps: 0,
          servings: 1,
        ),
    ];

    test('a snack every day, never batched, and varied', () {
      final plan = _plan(dishes: [..._dishes, ...snacks]);
      final planned = plan.items.where((i) => i.slot == MealSlot.snack);
      expect(planned, hasLength(7));
      expect(planned.every((i) => i.batch == null), isTrue);
      expect(planned.map((i) => i.key).toSet().length, greaterThan(1));
      for (var d = 0; d < 7; d++) {
        expect(plan.totalOn(d).kcal, closeTo(2000, 200), reason: 'day $d');
      }
    });

    test('a rule item in the snack takes its place', () {
      const yogurt = PlannerRule(
        rule: MealRule(
          id: 'yog',
          foodId: 'yogurt',
          slot: MealSlot.snack,
          frequency: RuleFrequency.daily,
          amountMin: 150,
          amountMax: 150,
        ),
        name: 'Yogurt',
        perUnit: Nutrition(kcal: 1, proteinG: 0.1, carbsG: 0.05, fatG: 0.03),
      );
      final plan = _plan(dishes: [..._dishes, ...snacks], rules: [yogurt]);
      for (var d = 0; d < 7; d++) {
        final snack = plan.itemsOn(d).where((i) => i.slot == MealSlot.snack);
        expect(snack.map((i) => i.key), ['food:yogurt'], reason: 'day $d');
      }
    });

    test('without snack dishes, the snack stays empty and unremarked', () {
      final plan = _plan();
      expect(plan.items.where((i) => i.slot == MealSlot.snack), isEmpty);
      expect(plan.notes.where((n) => n.contains('snack')), isEmpty);
    });
  });

  test('"at least" rules count dishes that contain the food', () {
    const salmon = PlannerRule(
      rule: MealRule(
        id: 'salmon',
        foodId: 'salmon',
        frequency: RuleFrequency.minPerWeek,
        timesPerWeek: 3,
        amountMin: 120,
        amountMax: 180,
      ),
      name: 'Salmon',
      perUnit: Nutrition(kcal: 2.17, proteinG: 0.2, carbsG: 0, fatG: 0.15),
    );
    for (final seed in [1, 2, 3]) {
      final plan = _plan(rules: [salmon], seed: seed);
      final inDishes = plan.items
          .where((i) => i.key == 'salmon-traybake')
          .length;
      final placed = plan.items.where((i) => i.key == 'food:salmon').length;
      expect(inDishes + placed, greaterThanOrEqualTo(3), reason: 'seed $seed');
      expect(plan.notes.where((n) => n.startsWith('Salmon')), isEmpty);
    }
  });

  test('"at most" rules hold, or are reported', () {
    const chilli = PlannerRule(
      rule: MealRule(
        id: 'chilli',
        recipeId: 'chilli',
        frequency: RuleFrequency.maxPerWeek,
        timesPerWeek: 1,
        amountMin: 1,
        amountMax: 1,
      ),
      name: 'Chilli',
      perUnit: Nutrition(kcal: 520, proteinG: 40, carbsG: 55, fatG: 12),
    );
    final dishes = [
      for (final d in _dishes)
        if (d.key == 'chilli')
          _dish('chilli', _mains, d.perPortion, contains: {'recipe:chilli'})
        else
          d,
    ];
    for (final seed in [1, 2, 3]) {
      final plan = _plan(dishes: dishes, rules: [chilli], seed: seed);
      final times = plan.items.where((i) => i.key == 'chilli').length;
      expect(
        times <= 1 || plan.notes.any((n) => n.startsWith('Chilli')),
        isTrue,
      );
    }
  });

  test('locked items are kept on regenerating', () {
    final first = _plan();
    final lunch = first.itemsOn(2).firstWhere((i) => i.slot == MealSlot.lunch);
    final locked = lunch.copyWith(amount: 1.2, locked: true);
    final again = _plan(locked: [locked], seed: 42);
    final kept = again
        .itemsOn(2)
        .where((i) => i.slot == MealSlot.lunch)
        .toList();
    expect(kept, hasLength(1));
    expect(kept.single.key, lunch.key);
    expect(kept.single.amount, 1.2, reason: 'not refitted');
  });

  test('a meal with no suitable dishes is left empty and reported', () {
    final plan = _plan(
      dishes: [
        for (final d in _dishes)
          if (!d.meals.contains(MealSlot.breakfast)) d,
      ],
    );
    expect(plan.items.where((i) => i.slot == MealSlot.breakfast), isEmpty);
    expect(plan.notes, contains(contains('breakfast')));
  });

  test('a target the dishes can’t get down to is reported, not hidden', () {
    final plan = _plan(
      targets: const PlanTargets(
        kcal: 300,
        proteinG: 60,
        carbsG: 30,
        fatG: 10,
        fibreG: 30,
      ),
    );
    for (final i in plan.items.where((i) => i.isDish)) {
      expect(i.amount, greaterThanOrEqualTo(0.5), reason: 'never below min');
    }
    expect(plan.notes.where((n) => n.contains('kcal')), isNotEmpty);
  });

  test('no dishes at all still gives the rule items', () {
    final plan = _plan(dishes: const [], rules: [_cappuccino]);
    expect(plan.items, hasLength(7));
    expect(plan.notes, isNotEmpty);
  });

  test('liked dishes come up more', () {
    int soups(double preference) => [
      for (final seed in [1, 2, 3, 4, 5])
        ..._plan(
          seed: seed,
          dishes: [
            for (final d in _dishes)
              if (d.key == 'lentil-soup')
                _dish(
                  'lentil-soup',
                  _mains,
                  d.perPortion,
                  keeps: 4,
                  preference: preference,
                )
              else
                d,
          ],
        ).items.where((i) => i.key == 'lentil-soup'),
    ].length;
    expect(soups(3), greaterThan(soups(0.25)));
  });

  group('variety', () {
    // Four lunch and dinner dishes with the same nutrition, so only variety
    // tells them apart: two chicken ones (both Indian), a bean chilli and
    // a fish stew. Short batches, so there are plenty of choices to make.
    const n = Nutrition(
      kcal: 600,
      proteinG: 45,
      carbsG: 60,
      fatG: 18,
      fibreG: 8,
    );
    List<DishCandidate> dishes({bool known = true}) => [
      for (final (key, protein, cuisine) in [
        ('chicken-curry', 'cofid:chicken', Cuisine.indian),
        ('chicken-tikka', 'cofid:chicken', Cuisine.indian),
        ('bean-chilli', 'cofid:beans', Cuisine.mexican),
        ('fish-stew', 'cofid:cod', Cuisine.mediterranean),
      ])
        DishCandidate(
          key: key,
          name: key,
          kind: CandidateKind.library,
          meals: _mains,
          perPortion: n,
          maxServingsPerBatch: 2,
          keepsDays: 1,
          mainProtein: known ? protein : null,
          cuisine: known ? cuisine : null,
        ),
      _dishes.firstWhere((d) => d.key == 'oats'),
    ];

    List<WeekPlan> plans({
      bool known = true,
      Set<String> recent = const {},
    }) => [
      for (final seed in [1, 2, 3, 4, 5, 6])
        planWeek(
          PlannerInput(
            targets: const [_targets],
            dishes: dishes(known: known),
            recent: recent,
          ),
          Random(seed),
        ),
    ];

    String proteinOf(String key) =>
        key.startsWith('chicken') ? 'chicken' : key;

    /// Days with two different dishes at lunch and dinner that match by
    /// [by].
    int matchingDays(List<WeekPlan> plans, String? Function(String key) by) {
      var count = 0;
      for (final plan in plans) {
        for (var d = 0; d < 7; d++) {
          String? at(MealSlot slot) => plan
              .itemsOn(d)
              .where((i) => i.slot == slot && i.isDish)
              .firstOrNull
              ?.key;
          final lunch = at(MealSlot.lunch);
          final dinner = at(MealSlot.dinner);
          if (lunch != null &&
              dinner != null &&
              lunch != dinner &&
              by(lunch) == by(dinner)) {
            count++;
          }
        }
      }
      return count;
    }

    int servingsOf(List<WeekPlan> plans, Set<String> keys) => [
      for (final p in plans) ...p.items.where((i) => keys.contains(i.key)),
    ].length;

    test('lunch and dinner on one day avoid sharing a protein', () {
      expect(
        matchingDays(plans(), proteinOf),
        lessThan(matchingDays(plans(known: false), proteinOf)),
      );
    });

    test('and a cuisine', () {
      String cuisineOf(String key) =>
          key.startsWith('chicken') ? 'indian' : key;
      expect(
        matchingDays(plans(), cuisineOf),
        lessThan(matchingDays(plans(known: false), cuisineOf)),
      );
    });

    test('the week leans less on one protein', () {
      const chicken = {'chicken-curry', 'chicken-tikka'};
      expect(
        servingsOf(plans(), chicken),
        lessThan(servingsOf(plans(known: false), chicken)),
      );
    });

    test('last week’s dishes come up less', () {
      const lastWeek = {'chicken-curry', 'bean-chilli'};
      expect(
        servingsOf(plans(recent: lastWeek), lastWeek),
        lessThan(servingsOf(plans(), lastWeek)),
      );
    });

    test('last week is matched by name too', () {
      const input = PlannerInput(
        targets: [_targets],
        dishes: [],
        recent: {'Indian chicken rice bowl'},
      );
      const renamedKey = DishCandidate(
        key: 'template:rice-bowl:indian:1',
        name: 'Indian chicken rice bowl',
        kind: CandidateKind.template,
        meals: _mains,
        perPortion: n,
        maxServingsPerBatch: 4,
        keepsDays: 3,
      );
      expect(input.isRecent(renamedKey), isTrue);
      expect(input.isRecent(dishes().first), isFalse);
    });

    test('variety never costs the calories', () {
      for (final plan in plans(recent: const {'chicken-curry'})) {
        for (var d = 0; d < 7; d++) {
          expect(
            plan.totalOn(d).kcal,
            closeTo(_targets.kcal, _targets.kcal * 0.1),
            reason: 'day $d',
          );
        }
      }
    });
  });
}
