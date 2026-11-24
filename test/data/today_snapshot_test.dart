import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/snapshots/today_snapshot.dart';
import 'package:trendline/data/snapshots/today_snapshot_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

TodaySnapshot _snapshot({String userId = 'user-1'}) => TodaySnapshot(
  userId: userId,
  day: DateTime(2026, 12, 7),
  savedAt: DateTime(2026, 12, 7, 13, 5),
  entries: [
    FoodLogEntry(
      id: 'l1',
      eatenOn: DateTime(2026, 12, 7),
      eatenAt: DateTime(2026, 12, 7, 8, 30),
      slot: MealSlot.breakfast,
      foodId: 'f1',
      foodName: 'Porridge',
      foodBrand: 'Brand',
      grams: 80,
      nutrition: const Nutrition(
        kcal: 304,
        proteinG: 8.8,
        carbsG: 48,
        fatG: 6.4,
        fibreG: 0,
        fibreUnknown: true,
      ),
    ),
  ],
  targets: const DailyTargets(
    kcal: 2100,
    proteinG: 150,
    proteinBasis: ProteinBasis.leanMass,
    fatG: 70,
    carbsG: 220,
    fibreG: 30,
    weeklyChangeKg: -0.5,
    floorKcal: 1600,
    limitedByFloor: false,
  ),
  planned: const [
    PlannedItem(
      day: 0,
      slot: MealSlot.dinner,
      key: 'recipe:r1',
      name: 'Stew',
      amount: 1.25,
      isDish: true,
      perUnit: Nutrition(kcal: 500, proteinG: 40, carbsG: 30, fatG: 20),
      minAmount: 0.5,
      maxAmount: 1.75,
      locked: true,
      batch: 2,
      id: 'i1',
    ),
  ],
);

/// A container signed in as user-1 (unless [auth] says otherwise), once
/// the auth status has loaded.
Future<ProviderContainer> _container(
  FakeSnapshotStore store, [
  FakeAuthRepository? auth,
]) async {
  auth ??= FakeAuthRepository(initial: const SignedIn('user-1'));
  final c = ProviderContainer.test(
    overrides: [
      snapshotStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(auth),
    ],
  );
  addTearDown(auth.dispose);
  // Keep it alive, as the auth gate does.
  c.listen(todaySnapshotProvider, (_, _) {});
  await c.read(authStatusProvider.future);
  return c;
}

void main() {
  test('round-trips everything Today shows', () {
    final back = TodaySnapshot.decode(_snapshot().encode())!;
    expect(back.userId, 'user-1');
    expect(back.day, DateTime(2026, 12, 7));
    expect(back.savedAt, DateTime(2026, 12, 7, 13, 5));
    final e = back.entries.single;
    expect(e.foodName, 'Porridge');
    expect(e.foodBrand, 'Brand');
    expect(e.eatenAt, DateTime(2026, 12, 7, 8, 30));
    expect(e.nutrition.fibreUnknown, isTrue);
    expect(e.nutrition.kcal, 304);
    expect(back.targets!.proteinBasis, ProteinBasis.leanMass);
    expect(back.targets!.floorKcal, 1600);
    final i = back.planned.single;
    expect(i.amount, 1.25);
    expect(i.maxAmount, 1.75);
    expect(i.locked, isTrue);
    expect(i.batch, 2);
    expect(i.id, 'i1');
    expect(i.nutrition.kcal, 625);
  });

  test('damaged or old snapshots are ignored', () {
    expect(TodaySnapshot.decode(null), isNull);
    expect(TodaySnapshot.decode('not json'), isNull);
    expect(TodaySnapshot.decode('{"v": 1}'), isNull);
    final old = _snapshot().encode().replaceFirst('"v":1', '"v":0');
    expect(TodaySnapshot.decode(old), isNull);
  });

  test('loads the signed-in user’s snapshot', () async {
    final store = FakeSnapshotStore()..values['today'] = _snapshot().encode();
    final c = await _container(store);
    final s = await c.read(todaySnapshotProvider.future);
    expect(s?.entries.single.foodName, 'Porridge');
  });

  test('another account’s snapshot is never shown, and deleted', () async {
    final store = FakeSnapshotStore()
      ..values['today'] = _snapshot(userId: 'someone-else').encode();
    final c = await _container(store);
    expect(await c.read(todaySnapshotProvider.future), isNull);
    expect(store.values, isEmpty);
  });

  test('signing out deletes it', () async {
    final store = FakeSnapshotStore()..values['today'] = _snapshot().encode();
    final auth = FakeAuthRepository(initial: const SignedIn('user-1'));
    final c = await _container(store, auth);
    expect(await c.read(todaySnapshotProvider.future), isNotNull);
    auth.emit(const SignedOut());
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(todaySnapshotProvider.future), isNull);
    expect(store.values, isEmpty);
  });

  test('saves only changes, and only for the signed-in user', () async {
    final store = FakeSnapshotStore();
    final c = await _container(store);
    await c.read(todaySnapshotProvider.future);
    final notifier = c.read(todaySnapshotProvider.notifier);

    await notifier.save(_snapshot());
    expect(store.writes, 1);
    // The same screen a moment later isn't written again.
    final later = _snapshot();
    await notifier.save(
      TodaySnapshot(
        userId: later.userId,
        day: later.day,
        savedAt: later.savedAt.add(const Duration(minutes: 5)),
        entries: later.entries,
        targets: later.targets,
        planned: later.planned,
      ),
    );
    expect(store.writes, 1);
    await notifier.save(_snapshot(userId: 'someone-else'));
    expect(store.writes, 1);
  });
}
