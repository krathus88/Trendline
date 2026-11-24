import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeWeighInRepository weighIns;
  late FakeFoodRepository foods;
  late FakeFoodLogRepository logs;
  late ProviderContainer container;

  setUp(() async {
    auth = FakeAuthRepository(initial: const SignedIn('user-1'));
    weighIns = FakeWeighInRepository();
    foods = FakeFoodRepository();
    logs = FakeFoodLogRepository();
    // Riverpod 3 pauses providers nobody listens to, so tests keep a
    // listener on anything they read (see keep below).
    container = ProviderContainer.test(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        weighInRepositoryProvider.overrideWithValue(weighIns),
        foodRepositoryProvider.overrideWithValue(foods),
        foodLogRepositoryProvider.overrideWithValue(logs),
      ],
    )..listen(authStatusProvider, (_, _) {});
    await container.read(authStatusProvider.future);
  });

  tearDown(() => auth.dispose());

  void keep(ProviderListenable<Object?> provider) =>
      container.listen(provider, (_, _) {});

  group('WeighInsNotifier', () {
    test('adds newest first and feeds the trend', () async {
      keep(weighInsProvider);
      await container.read(weighInsProvider.future);
      final n = container.read(weighInsProvider.notifier);
      final today = DateTime.now();
      await n.add(measuredAt: addDays(today, -1), weightKg: 90);
      await n.add(measuredAt: today, weightKg: 89);

      final list = container.read(weighInsProvider).value!;
      expect(list.map((w) => w.weightKg), [89, 90]);
      expect(container.read(trendProvider).last.trendKg, closeTo(89.9, 1e-9));
    });

    test('a failed delete puts the weigh-in back', () async {
      await weighIns.add(measuredAt: DateTime.now(), weightKg: 80);
      keep(weighInsProvider);
      final before = await container.read(weighInsProvider.future);
      weighIns.failDeletes = true;

      await expectLater(
        container.read(weighInsProvider.notifier).delete(before.single.id),
        throwsA(isA<FakeNetworkError>()),
      );
      expect(container.read(weighInsProvider).value, hasLength(1));
    });
  });

  group('FoodsNotifier', () {
    const draft = FoodDraft(
      name: 'Semi skimmed milk',
      barcode: '01219494',
      per100g: Nutrition(kcal: 50, proteinG: 3.6, carbsG: 4.8, fatG: 1.8),
      source: FoodSource.openFoodFacts,
    );

    test('saving the same barcode twice keeps one food', () async {
      keep(foodsProvider);
      await container.read(foodsProvider.future);
      final n = container.read(foodsProvider.notifier);
      final a = await n.save(draft);
      final b = await n.save(draft);

      expect(b.id, a.id);
      expect(foods.saves, 1);
      expect(container.read(foodsProvider).value, hasLength(1));
      expect(n.byBarcode('01219494')?.id, a.id);
    });

    test('choosing the same basic food twice keeps one copy', () async {
      keep(foodsProvider);
      await container.read(foodsProvider.future);
      final n = container.read(foodsProvider.notifier);
      final a = await n.save(bananas);
      final b = await n.save(bananas);

      expect(b.id, a.id);
      expect(foods.saves, 1);
      expect(a.source, FoodSource.cofid);
      expect(n.byReference('13-001', 'Bananas, flesh only')?.id, a.id);
    });

    test('another food sharing a CoFID code is a separate copy', () async {
      // CoFID 2021 gives one code to two different foods.
      keep(foodsProvider);
      await container.read(foodsProvider.future);
      final n = container.read(foodsProvider.notifier);
      final a = await n.save(bananas);
      final b = await n.save(
        const FoodDraft(
          name: 'Watercress, raw',
          per100g: Nutrition(kcal: 10, proteinG: 1.9, carbsG: 0, fatG: 0.3),
          source: FoodSource.cofid,
          referenceCode: '13-001',
        ),
      );

      expect(b.id, isNot(a.id));
      expect(foods.saves, 2);
    });
  });

  group('FoodLogNotifier', () {
    final day = DateTime(2026, 11, 24);
    const oats = Food(
      id: 'f1',
      name: 'Oats',
      per100g: Nutrition(kcal: 379, proteinG: 13, carbsG: 60, fatG: 7),
      source: FoodSource.manual,
    );

    test('logs into the day and rescales portions', () async {
      keep(foodLogProvider(day));
      await container.read(foodLogProvider(day).future);
      final n = container.read(foodLogProvider(day).notifier);
      await n.add(slot: MealSlot.breakfast, food: oats, grams: 50);
      final entry = container.read(foodLogProvider(day)).value!.single;
      expect(entry.nutrition.kcal, 189.5);

      await n.updateGrams(entry, 100);
      final updated = container.read(foodLogProvider(day)).value!.single;
      expect(updated.nutrition.kcal, 379);
    });

    test('a failed portion change reverts', () async {
      keep(foodLogProvider(day));
      await container.read(foodLogProvider(day).future);
      final n = container.read(foodLogProvider(day).notifier);
      await n.add(slot: MealSlot.lunch, food: oats, grams: 50);
      final entry = container.read(foodLogProvider(day)).value!.single;
      logs.failUpdates = true;

      await expectLater(
        n.updateGrams(entry, 200),
        throwsA(isA<FakeNetworkError>()),
      );
      expect(container.read(foodLogProvider(day)).value!.single.grams, 50);
    });
  });

  test('signing out drops cached data', () async {
    await weighIns.add(measuredAt: DateTime.now(), weightKg: 80);
    keep(weighInsProvider);
    expect(await container.read(weighInsProvider.future), hasLength(1));

    auth.emit(const SignedOut());
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentUserIdProvider), isNull);
    expect(await container.read(weighInsProvider.future), isEmpty);
  });
}
