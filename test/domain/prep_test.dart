import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/prep.dart';
import 'package:trendline/domain/recipe.dart';

const _chicken = Food(
  id: 'f-chicken',
  name: 'Chicken',
  per100g: Nutrition(kcal: 100, proteinG: 24, carbsG: 0, fatG: 1),
  source: FoodSource.manual,
);
const _cumin = Food(
  id: 'f-cumin',
  name: 'Cumin',
  per100g: Nutrition(kcal: 400, proteinG: 18, carbsG: 40, fatG: 22),
  source: FoodSource.manual,
);

const _stew = Recipe(
  id: 'r1',
  name: 'Stew',
  ingredients: [
    RecipeIngredient(foodId: 'f-chicken', rawGrams: 800),
    RecipeIngredient(foodId: 'f-cumin', rawGrams: 6),
  ],
  estimatedCookedWeightG: 600,
);

PrepPortion _portion({
  DateTime? day,
  double amount = 1,
  DateTime? useBy,
  PortionStatus status = PortionStatus.planned,
}) => PrepPortion(
  id: 'p',
  sessionId: 's',
  day: day,
  slot: day == null ? null : MealSlot.dinner,
  amount: amount,
  useBy: useBy ?? DateTime(2026, 12, 10),
  status: status,
);

PrepSession _session({
  double portionCount = 3,
  double? weight,
  DateTime? cookOn,
  List<PrepPortion> portions = const [],
}) => PrepSession(
  id: 's',
  recipeId: 'r1',
  cookOn: cookOn ?? DateTime(2026, 12, 7),
  portionCount: portionCount,
  cookedAt: weight == null ? null : DateTime(2026, 12, 7, 19),
  cookedWeightG: weight,
  portions: portions,
);

void main() {
  test('ingredients scale to the portions cooked, rounded for a scale', () {
    final scaled = scaledIngredients(_stew, 3);
    expect(scaled.first.rawGrams, 600);
    expect(scaled.last.rawGrams, 4.5, reason: '6 × 3/4, to the half gram');
    expect(roundIngredientGrams(123.4), 123);
    expect(roundIngredientGrams(2.2), 2);
    expect(roundIngredientGrams(0.2), 0);
  });

  test('expected weight prefers the measured one, then the estimate', () {
    expect(expectedCookedWeightG(_stew, 2), 300);
    final weighed = Recipe(
      id: 'r1',
      name: 'Stew',
      ingredients: _stew.ingredients,
      cookedWeightG: 700,
      estimatedCookedWeightG: 600,
    );
    expect(expectedCookedWeightG(weighed, 4), 700);
    expect(
      expectedCookedWeightG(
        const Recipe(id: 'x', name: 'x', ingredients: []),
        2,
      ),
      isNull,
    );
  });

  test('portion grams are shares of the measured batch', () {
    final session = _session(weight: 900);
    expect(session.gramsOf(_portion(amount: 1.25)), closeTo(375, 1e-9));
    expect(_session().gramsOf(_portion()), isNull, reason: 'not weighed');
  });

  test('nutrition per 100 g cooked comes from the scaled batch', () {
    final foods = {_chicken.id: _chicken, _cumin.id: _cumin};
    // 3 of 4 portions: 600 g chicken (600 kcal) + 4.5 g cumin (18 kcal),
    // cooked down to 450 g.
    final n = sessionPer100gCooked(_session(weight: 450), _stew, foods)!;
    expect(n.kcal, closeTo((800 + 24) * 0.75 / 450 * 100, 1e-9));
    // Food portions are rounded to 0.1 g, so the cumin gives 1.1 g.
    expect(n.proteinG, closeTo((192 + 1.1) * 0.75 / 450 * 100, 1e-9));
    expect(sessionPer100gCooked(_session(), _stew, foods), isNull);
    expect(
      sessionPer100gCooked(_session(weight: 450), _stew, {
        _chicken.id: _chicken,
      }),
      isNull,
      reason: 'an ingredient’s food is missing',
    );
  });

  test('a batch weight far off its raw weight is questioned', () {
    final session = _session();
    expect(sessionWeightWarning(_stew, session, 450), isNull);
    expect(sessionWeightWarning(_stew, session, 100), isNotNull);
    expect(sessionWeightWarning(_stew, session, 3000), isNotNull);
  });

  test('timing: upcoming, today, missed, expired', () {
    final today = DateTime(2026, 12, 8);
    expect(
      portionTiming(_portion(day: DateTime(2026, 12, 9)), today),
      PortionTiming.upcoming,
    );
    expect(portionTiming(_portion(day: today), today), PortionTiming.today);
    expect(
      portionTiming(_portion(day: DateTime(2026, 12, 7)), today),
      PortionTiming.missed,
    );
    expect(portionTiming(_portion(), today), PortionTiming.missed);
    expect(
      portionTiming(
        _portion(day: DateTime(2026, 12, 7), useBy: DateTime(2026, 12, 7)),
        today,
      ),
      PortionTiming.expired,
    );
    expect(
      portionTiming(_portion(useBy: today), today),
      PortionTiming.missed,
      reason: 'fine on its use-by day itself',
    );
  });

  test('frozen portions are best within three months', () {
    expect(freezerUseBy(DateTime(2026, 12, 8)), DateTime(2027, 3, 8));
  });

  test('shows sessions to cook and batches with portions left', () {
    final today = DateTime(2026, 12, 20);
    final open = _portion(day: today);
    final eaten = _portion(status: PortionStatus.eaten);
    final sessions = [
      _session(cookOn: DateTime(2026, 12, 21), portions: [open]),
      _session(cookOn: DateTime(2026, 12, 15), portions: [open]),
      _session(cookOn: DateTime(2026, 12, 2), portions: [open]),
      _session(cookOn: DateTime(2026, 12, 2), weight: 500, portions: [open]),
      _session(cookOn: DateTime(2026, 12, 18), weight: 500, portions: [eaten]),
    ];
    final shown = activeSessions(sessions, today);
    expect(shown.map((s) => s.cookOn), [
      DateTime(2026, 12, 2),
      DateTime(2026, 12, 15),
      DateTime(2026, 12, 21),
    ]);
    expect(shown.first.cooked, isTrue, reason: 'cooked, portions left');
  });

  group('placing leftovers', () {
    final monday = DateTime(2026, 12, 7);
    PrepPortion leftover(String id, DateTime useBy) => PrepPortion(
      id: id,
      sessionId: 's',
      amount: 1,
      useBy: useBy,
      status: PortionStatus.leftover,
    );

    test('the soonest to go off takes the earliest free meal', () {
      final placed = placeLeftovers(
        leftovers: [
          leftover('later', DateTime(2026, 12, 30)),
          leftover('soon', DateTime(2026, 12, 9)),
        ],
        weekStart: monday,
        from: DateTime(2026, 12, 8),
        taken: (day, slot) => day == 1 && slot == MealSlot.lunch,
      );
      expect(
        {for (final e in placed.entries) e.key.id: e.value},
        {'soon': (1, MealSlot.dinner), 'later': (2, MealSlot.lunch)},
      );
    });

    test('nothing goes after its use-by date or before today', () {
      final placed = placeLeftovers(
        leftovers: [leftover('p', DateTime(2026, 12, 8))],
        weekStart: monday,
        from: DateTime(2026, 12, 8),
        taken: (day, slot) => day == 1,
      );
      expect(placed, isEmpty);
    });

    test('next week’s plan starts on its Monday', () {
      final placed = placeLeftovers(
        leftovers: [leftover('p', DateTime(2026, 12, 20))],
        weekStart: DateTime(2026, 12, 14),
        from: DateTime(2026, 12, 10),
        taken: (_, _) => false,
      );
      expect(placed.values.single, (0, MealSlot.lunch));
    });

    test('a leftover gone off before the week isn’t placed', () {
      final placed = placeLeftovers(
        leftovers: [leftover('p', DateTime(2026, 12, 12))],
        weekStart: DateTime(2026, 12, 14),
        from: DateTime(2026, 12, 10),
        taken: (_, _) => false,
      );
      expect(placed, isEmpty);
    });
  });
}
