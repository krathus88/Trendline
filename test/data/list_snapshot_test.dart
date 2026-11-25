import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/foods/food_repository.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipe_repository.dart';
import 'package:trendline/data/snapshots/snapshot_store.dart';
import 'package:trendline/data/snapshots/today_snapshot_notifier.dart';
import 'package:trendline/data/weigh_ins/weigh_in_repository.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/weigh_in.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

Food _food(String id, String name) => Food(
  id: id,
  name: name,
  per100g: const Nutrition(kcal: 100, proteinG: 10, carbsG: 5, fatG: 2),
  source: FoodSource.manual,
);

String _foodsSnapshot(String userId, List<Food> foods) => ListSnapshot(
  userId: userId,
  savedAt: DateTime(2026, 11, 25, 9),
  rows: [for (final f in foods) foodToRow(f)],
).encode();

/// Foods whose list arrives only when [live] completes, or fails.
class _SlowFoods extends FakeFoodRepository {
  final live = Completer<List<Food>>();

  @override
  Future<List<Food>> fetchAll() => live.future;
}

Future<ProviderContainer> _container(
  FakeSnapshotStore store, {
  FoodRepository? foods,
  WeighInRepository? weighIns,
  FakeAuthRepository? auth,
}) async {
  auth ??= FakeAuthRepository(initial: const SignedIn('user-1'));
  final c = ProviderContainer.test(
    overrides: [
      snapshotStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(auth),
      foodRepositoryProvider.overrideWithValue(foods ?? FakeFoodRepository()),
      weighInRepositoryProvider.overrideWithValue(
        weighIns ?? FakeWeighInRepository(),
      ),
    ],
  );
  addTearDown(auth.dispose);
  // Signing out clears snapshots through this, as in the app.
  c.listen(todaySnapshotProvider, (_, _) {});
  await c.read(authStatusProvider.future);
  return c;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('rows round-trip through the repositories’ parsers', () {
    test('foods', () {
      const food = Food(
        id: 'f1',
        name: 'Bananas, flesh only',
        brand: 'Brand',
        barcode: '01234567',
        per100g: Nutrition(
          kcal: 81,
          proteinG: 1.2,
          carbsG: 20.3,
          fatG: 0.1,
          fibreG: 0,
          fibreUnknown: true,
        ),
        sugarG: 16.2,
        saltG: 0,
        servingG: 100,
        source: FoodSource.cofid,
        referenceCode: '14-874',
      );
      final back = foodFromRow(foodToRow(food));
      expect(back.name, food.name);
      expect(back.brand, 'Brand');
      expect(back.barcode, '01234567');
      expect(back.per100g.kcal, 81);
      expect(back.per100g.fibreUnknown, isTrue);
      expect(back.sugarG, 16.2);
      expect(back.servingG, 100);
      expect(back.source, FoodSource.cofid);
      expect(back.referenceCode, '14-874');
    });

    test('weigh-ins', () {
      final w = WeighIn(
        id: 'w1',
        measuredAt: DateTime(2026, 11, 25, 7, 30),
        weightKg: 82.35,
        bodyFatPct: 21.5,
        leanMassKg: 64.6,
        source: WeighInSource.healthConnect,
        externalId: 'hc-1',
      );
      final back = weighInFromRow(weighInToRow(w));
      expect(back.measuredAt, w.measuredAt);
      expect(back.weightKg, 82.35);
      expect(back.bodyFatPct, 21.5);
      expect(back.leanMassKg, 64.6);
      expect(back.source, WeighInSource.healthConnect);
      expect(back.externalId, 'hc-1');
    });

    test('recipes, ingredients in order', () {
      const recipe = Recipe(
        id: 'r1',
        name: 'Stew',
        ingredients: [
          RecipeIngredient(foodId: 'b', rawGrams: 500),
          RecipeIngredient(foodId: 'a', rawGrams: 2.5),
        ],
        portions: 5,
        cookedWeightG: 1600,
        fridgeDays: 2,
        freezable: false,
        method: 'Simmer.',
        origin: RecipeOrigin.template,
        sourceId: 'curry',
        sourceVersion: 3,
        estimatedCookedWeightG: 1550,
        listed: false,
      );
      final back = recipeFromRow(recipeToRow(recipe));
      expect([for (final i in back.ingredients) i.foodId], ['b', 'a']);
      expect(back.ingredients.last.rawGrams, 2.5);
      expect(back.portions, 5);
      expect(back.cookedWeightG, 1600);
      expect(back.freezable, isFalse);
      expect(back.method, 'Simmer.');
      expect(back.origin, RecipeOrigin.template);
      expect(back.sourceVersion, 3);
      expect(back.estimatedCookedWeightG, 1550);
      expect(back.listed, isFalse);
    });
  });

  group('food library snapshot', () {
    test('shows the snapshot at once, then the live list, and keeps '
        'that', () async {
      final store = FakeSnapshotStore()
        ..values[SnapshotKeys.foods] = _foodsSnapshot('user-1', [
          _food('f1', 'Old oats'),
        ]);
      final foods = _SlowFoods();
      final c = await _container(store, foods: foods);
      final seen = <List<String>>[];
      c.listen(foodsProvider, (_, next) {
        if (next case AsyncData(:final value)) {
          seen.add([for (final f in value) f.name]);
        }
      });
      await _settle();
      expect(c.read(foodsProvider).value?.single.name, 'Old oats');

      foods.live.complete([_food('f2', 'Oats')]);
      await c.read(foodsProvider.future);
      await _settle();
      expect(seen, [
        ['Old oats'],
        ['Oats'],
      ]);
      expect(store.values[SnapshotKeys.foods], contains('"Oats"'));
      expect(store.values[SnapshotKeys.foods], isNot(contains('Old oats')));
    });

    test('without signal, the snapshot is the list', () async {
      final store = FakeSnapshotStore()
        ..values[SnapshotKeys.foods] = _foodsSnapshot('user-1', [
          _food('f1', 'Oats'),
        ]);
      final foods = _SlowFoods();
      final c = await _container(store, foods: foods);
      c.listen(foodsProvider, (_, _) {});
      foods.live.completeError(FakeNetworkError());
      final list = await c.read(foodsProvider.future);
      expect(list.single.name, 'Oats');
    });

    test('with no snapshot, a failure stands', () async {
      final foods = _SlowFoods();
      final c = await _container(FakeSnapshotStore(), foods: foods);
      final errors = <Object>[];
      c.listen(foodsProvider, (_, next) {
        // Retrying keeps the error on the loading state, so ask hasError.
        if (next.hasError) errors.add(next.error!);
      });
      foods.live.completeError(FakeNetworkError());
      await _settle();
      await _settle();
      expect(errors.first, isA<FakeNetworkError>());
      expect(c.read(foodsProvider).value, isNull);
    });

    test('another account’s snapshot is never shown, and deleted', () async {
      final store = FakeSnapshotStore()
        ..values[SnapshotKeys.foods] = _foodsSnapshot('someone-else', [
          _food('f1', 'Their oats'),
        ]);
      final foods = _SlowFoods();
      final c = await _container(store, foods: foods);
      c.listen(foodsProvider, (_, _) {});
      await _settle();
      expect(c.read(foodsProvider).value, isNull);
      expect(store.values[SnapshotKeys.foods], isNull);
      foods.live.complete(const []);
      expect(await c.read(foodsProvider.future), isEmpty);
    });

    test('a damaged snapshot is dropped', () async {
      final store = FakeSnapshotStore()
        ..values[SnapshotKeys.foods] = '{"v": 1, "user": "user-1"}';
      final c = await _container(store);
      c.listen(foodsProvider, (_, _) {});
      expect(await c.read(foodsProvider.future), isEmpty);
      await _settle();
      expect(store.values[SnapshotKeys.foods], isNot(contains('"v": 1')));
    });

    test('a change is written; the same list isn’t written again', () async {
      final store = FakeSnapshotStore();
      final c = await _container(store);
      c.listen(foodsProvider, (_, _) {});
      await c.read(foodsProvider.future);
      await _settle();
      final writes = store.writes;

      await c
          .read(foodsProvider.notifier)
          .save(
            const FoodDraft(
              name: 'Milk',
              per100g: Nutrition(kcal: 50, proteinG: 3.6, carbsG: 4.8, fatG: 2),
              source: FoodSource.manual,
            ),
          );
      await _settle();
      expect(store.writes, writes + 1);
      expect(store.values[SnapshotKeys.foods], contains('"Milk"'));

      c.invalidate(foodsProvider);
      await c.read(foodsProvider.future);
      await _settle();
      expect(store.writes, writes + 1);
    });
  });

  group('weigh-ins snapshot', () {
    test('readings that left the window are dropped', () async {
      final today = dayOf(DateTime.now());
      final old = WeighIn(
        id: 'w0',
        measuredAt: addDays(today, -WeighInsNotifier.historyDays - 5),
        weightKg: 90,
      );
      final recent = WeighIn(
        id: 'w1',
        measuredAt: addDays(today, -1),
        weightKg: 85,
      );
      final store = FakeSnapshotStore()
        ..values[SnapshotKeys.weighIns] = ListSnapshot(
          userId: 'user-1',
          savedAt: DateTime.now(),
          rows: [weighInToRow(recent), weighInToRow(old)],
        ).encode();
      final weighIns = _OfflineWeighIns();
      final c = await _container(store, weighIns: weighIns);
      c.listen(weighInsProvider, (_, _) {});
      final list = await c.read(weighInsProvider.future);
      expect([for (final w in list) w.id], ['w1']);
    });
  });

  test('signing out deletes every snapshot', () async {
    final store = FakeSnapshotStore();
    for (final key in SnapshotKeys.all) {
      store.values[key] = 'x';
    }
    final auth = FakeAuthRepository(initial: const SignedIn('user-1'));
    final c = await _container(store, auth: auth);
    await c.read(todaySnapshotProvider.future);
    auth.emit(const SignedOut());
    await _settle();
    await c.read(todaySnapshotProvider.future);
    expect(store.values, isEmpty);
  });
}

/// Weigh-ins that can't be fetched (no signal).
class _OfflineWeighIns extends FakeWeighInRepository {
  @override
  Future<List<WeighIn>> fetchSince(DateTime since) async =>
      throw FakeNetworkError();
}
