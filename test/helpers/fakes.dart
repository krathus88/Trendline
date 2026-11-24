import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/energy/energy_repository.dart';
import 'package:trendline/data/food_logs/food_log_repository.dart';
import 'package:trendline/data/foods/food_repository.dart';
import 'package:trendline/data/foods/reference_food_repository.dart';
import 'package:trendline/data/goals/goal_repository.dart';
import 'package:trendline/data/off/off_client.dart';
import 'package:trendline/data/profile/profile_repository.dart';
import 'package:trendline/data/recipes/recipe_repository.dart';
import 'package:trendline/data/weigh_ins/weigh_in_repository.dart';
import 'package:trendline/domain/adaptive_tdee.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/domain/weigh_in.dart';
import 'package:trendline/platform/barcode_scanner.dart';
import 'package:trendline/platform/health_source.dart';

/// Thrown by fakes to simulate a failed network call.
class FakeNetworkError implements Exception;

final testProfile = Profile(
  sex: Sex.male,
  birthYear: 1990,
  heightCm: 180,
  activityLevel: ActivityLevel.light,
  weightUnit: WeightUnit.kg,
  disclaimerAcceptedAt: DateTime(2026),
  healthScreenedAt: DateTime(2026),
);

class FakeProfileRepository implements ProfileRepository {
  new({this.profile});

  Profile? profile;
  int saves = 0;

  @override
  Future<Profile?> fetch() async => profile;

  @override
  Future<Profile> save(Profile p) async {
    saves++;
    return profile = p;
  }
}

class FakeWeighInRepository implements WeighInRepository {
  final items = <WeighIn>[];
  bool failDeletes = false;
  int _next = 0;

  @override
  Future<List<WeighIn>> fetchSince(DateTime since) async => [
    for (final w in items)
      if (!w.measuredAt.isBefore(since)) w,
  ]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));

  @override
  Future<WeighIn> add({
    required DateTime measuredAt,
    required double weightKg,
    double? bodyFatPct,
  }) async {
    final w = WeighIn(
      id: 'w${_next++}',
      measuredAt: measuredAt,
      weightKg: weightKg,
      bodyFatPct: bodyFatPct,
    );
    items.add(w);
    return w;
  }

  /// IDs of imported readings the user deleted, as the database keeps them.
  final dismissed = <String>{};

  @override
  Future<void> delete(String id) async {
    if (failDeletes) throw FakeNetworkError();
    for (final w in items.where((w) => w.id == id)) {
      if (w.externalId != null) dismissed.add(w.externalId!);
    }
    items.removeWhere((w) => w.id == id);
  }

  @override
  Future<int> importHealthConnect(List<ImportedWeighIn> readings) async {
    var added = 0;
    for (final r in readings) {
      if (dismissed.contains(r.externalId) ||
          items.any((w) => w.externalId == r.externalId)) {
        continue;
      }
      items.add(
        WeighIn(
          id: 'w${_next++}',
          measuredAt: r.measuredAt,
          weightKg: r.weightKg,
          bodyFatPct: r.bodyFatPct,
          leanMassKg: r.leanMassKg,
          source: WeighInSource.healthConnect,
          externalId: r.externalId,
        ),
      );
      added++;
    }
    return added;
  }
}

class FakeFoodRepository implements FoodRepository {
  final items = <Food>[];
  int saves = 0;
  int _next = 0;

  @override
  Future<List<Food>> fetchAll() async => List.of(items);

  @override
  Future<Food> save(FoodDraft d) async {
    saves++;
    final food = Food(
      id: 'f${_next++}',
      name: d.name,
      brand: d.brand,
      barcode: d.barcode,
      per100g: d.per100g,
      sugarG: d.sugarG,
      saltG: d.saltG,
      servingG: d.servingG,
      source: d.source,
      referenceCode: d.referenceCode,
    );
    items.add(food);
    return food;
  }

  /// Foods a recipe uses: deleting them fails, as in the database.
  final inUse = <String>{};

  @override
  Future<void> delete(String id) async {
    if (inUse.contains(id)) throw const FoodInUse();
    items.removeWhere((f) => f.id == id);
  }
}

/// Recipes in memory. New ones get IDs r0, r1, ...
class FakeRecipeRepository implements RecipeRepository {
  final items = <Recipe>[];
  int saves = 0;
  int _next = 0;

  @override
  Future<List<Recipe>> fetchAll() async => List.of(items);

  @override
  Future<Recipe> save(Recipe r) async {
    saves++;
    final saved = Recipe(
      id: r.id.isEmpty ? 'r${_next++}' : r.id,
      name: r.name.trim(),
      ingredients: r.ingredients,
      portions: r.portions,
      cookedWeightG: r.cookedWeightG,
      fridgeDays: r.fridgeDays,
      freezable: r.freezable,
      method: r.method,
      origin: r.origin,
      sourceId: r.sourceId,
      sourceVersion: r.sourceVersion,
    );
    items
      ..removeWhere((x) => x.id == saved.id)
      ..add(saved);
    return saved;
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((r) => r.id == id);
}

/// Basic foods whose name contains the query.
class FakeReferenceFoodRepository implements ReferenceFoodRepository {
  final items = <FoodDraft>[];
  final queries = <String>[];

  /// Basic foods by CoFID code and (CoFID) name, for library recipes.
  final byKey = <({String code, String name}), FoodDraft>{};

  @override
  Future<Map<({String code, String name}), FoodDraft>> fetchByKeys(
    Set<({String code, String name})> keys,
  ) async => {
    for (final k in keys)
      if (byKey.containsKey(k)) k: byKey[k]!,
  };

  @override
  Future<List<FoodDraft>> search(String query) async {
    queries.add(query);
    final q = cleanReferenceQuery(query);
    return [
      for (final d in items)
        if (d.name.toLowerCase().contains(q)) d,
    ];
  }
}

/// A basic food as the reference repository returns it.
const bananas = FoodDraft(
  name: 'Bananas, flesh only',
  per100g: Nutrition(kcal: 81, proteinG: 1.2, carbsG: 20.3, fatG: 0.1),
  source: FoodSource.cofid,
  referenceCode: '13-001',
);

class FakeFoodLogRepository implements FoodLogRepository {
  final items = <FoodLogEntry>[];

  /// Extra per-day totals, for tests that need weeks of intake.
  final dailyKcal = <DateTime, double>{};

  @override
  Future<Map<DateTime, double>> fetchDailyKcal(
    DateTime from,
    DateTime to,
  ) async {
    final totals = <DateTime, double>{
      for (final e in dailyKcal.entries)
        if (!e.key.isBefore(from) && !e.key.isAfter(to)) e.key: e.value,
    };
    for (final e in items) {
      if (e.eatenOn.isBefore(from) || e.eatenOn.isAfter(to)) continue;
      totals[e.eatenOn] = (totals[e.eatenOn] ?? 0) + e.nutrition.kcal;
    }
    return totals;
  }

  bool failUpdates = false;
  int _next = 0;

  @override
  Future<List<FoodLogEntry>> fetchDay(DateTime day) async => [
    for (final e in items)
      if (e.eatenOn == day) e,
  ];

  @override
  Future<FoodLogEntry> add({
    required DateTime day,
    required MealSlot slot,
    required Food food,
    required double grams,
  }) async {
    final e = FoodLogEntry(
      id: 'l${_next++}',
      eatenOn: day,
      eatenAt: DateTime.now(),
      slot: slot,
      foodId: food.id,
      foodName: food.name,
      foodBrand: food.brand,
      grams: grams,
      nutrition: food.per100g.forGrams(grams),
    );
    items.add(e);
    return e;
  }

  @override
  Future<FoodLogEntry> addRecipe({
    required DateTime day,
    required MealSlot slot,
    required Recipe recipe,
    required Nutrition per100gCooked,
    required double grams,
  }) async {
    final e = FoodLogEntry(
      id: 'l${_next++}',
      eatenOn: day,
      eatenAt: DateTime.now(),
      slot: slot,
      recipeId: recipe.id,
      foodName: recipe.name,
      grams: grams,
      nutrition: per100gCooked.forGrams(grams),
    );
    items.add(e);
    return e;
  }

  @override
  Future<FoodLogEntry> updateGrams(FoodLogEntry entry, double grams) async {
    if (failUpdates) throw FakeNetworkError();
    final updated = FoodLogEntry(
      id: entry.id,
      eatenOn: entry.eatenOn,
      eatenAt: entry.eatenAt,
      slot: entry.slot,
      foodId: entry.foodId,
      recipeId: entry.recipeId,
      foodName: entry.foodName,
      foodBrand: entry.foodBrand,
      grams: grams,
      nutrition: rescale(entry.nutrition, from: entry.grams, to: grams),
    );
    final i = items.indexWhere((e) => e.id == entry.id);
    items[i] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((e) => e.id == id);
}

class FakeBarcodeScanner implements BarcodeScanner {
  new({this.result});

  String? result;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> scan(BuildContext context) async => result;
}

class FakeHealthSource implements HealthSource {
  new({
    this.status = HealthAvailability.available,
    this.granted = false,
    this.grantOnRequest = true,
  });

  HealthAvailability status;
  bool granted;
  bool grantOnRequest;
  BodyReadings readings = const BodyReadings();
  Exception? readError;
  final reads = <({DateTime start, DateTime end})>[];
  int installs = 0;

  @override
  String get name => 'Health Connect';

  @override
  Future<HealthAvailability> availability() async => status;

  @override
  Future<void> install() async => installs++;

  @override
  Future<bool> hasAccess() async => granted;

  @override
  Future<bool> requestAccess() async => granted = grantOnRequest;

  @override
  Future<void> disconnect() async => granted = false;

  @override
  Future<BodyReadings> read(DateTime start, DateTime end) async {
    reads.add((start: start, end: end));
    if (readError case final e?) throw e;
    return readings;
  }
}

class FakeGoalRepository implements GoalRepository {
  new({this.goal});

  Goal? goal;
  int saves = 0;

  @override
  Future<Goal?> fetchActive() async => goal;

  @override
  Future<Goal> save(Goal goal) async {
    saves++;
    return this.goal = goal;
  }
}

class FakeEnergyRepository implements EnergyRepository {
  final completeDays = <DateTime>{};
  final estimates = <EnergyEstimate>[];

  @override
  Future<Set<DateTime>> fetchCompleteDays(DateTime from, DateTime to) async => {
    for (final d in completeDays)
      if (!d.isBefore(dayOf(from)) && !d.isAfter(dayOf(to))) d,
  };

  @override
  Future<void> setComplete(DateTime day, {required bool complete}) async {
    if (complete) {
      completeDays.add(dayOf(day));
    } else {
      completeDays.remove(dayOf(day));
    }
  }

  @override
  Future<EnergyEstimate?> fetchLatest() async => estimates.isEmpty
      ? null
      : (estimates.toList()
              ..sort((a, b) => a.computedOn.compareTo(b.computedOn)))
            .last;

  @override
  Future<void> save(EnergyEstimate estimate) async {
    if (estimates.any((e) => e.computedOn == estimate.computedOn)) return;
    estimates.add(estimate);
  }
}

/// An [OffClient] whose HTTP calls are answered by [handler].
OffClient fakeOffClient(Future<http.Response> Function(http.Request) handler) =>
    OffClient(userAgent: 'Trendline/test', httpClient: MockClient(handler));
