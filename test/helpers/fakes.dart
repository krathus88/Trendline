import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/food_logs/food_log_repository.dart';
import 'package:trendline/data/foods/food_repository.dart';
import 'package:trendline/data/off/off_client.dart';
import 'package:trendline/data/profile/profile_repository.dart';
import 'package:trendline/data/weigh_ins/weigh_in_repository.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/domain/profile.dart';
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
    );
    items.add(food);
    return food;
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((f) => f.id == id);
}

class FakeFoodLogRepository implements FoodLogRepository {
  final items = <FoodLogEntry>[];
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
  Future<FoodLogEntry> updateGrams(FoodLogEntry entry, double grams) async {
    if (failUpdates) throw FakeNetworkError();
    final updated = FoodLogEntry(
      id: entry.id,
      eatenOn: entry.eatenOn,
      eatenAt: entry.eatenAt,
      slot: entry.slot,
      foodId: entry.foodId,
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

/// An [OffClient] whose HTTP calls are answered by [handler].
OffClient fakeOffClient(Future<http.Response> Function(http.Request) handler) =>
    OffClient(userAgent: 'Trendline/test', httpClient: MockClient(handler));
