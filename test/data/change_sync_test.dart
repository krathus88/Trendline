import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/snapshots/snapshot_store.dart';
import 'package:trendline/data/sync/change_signals.dart';
import 'package:trendline/data/sync/change_sync.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

const _oats = FoodDraft(
  name: 'Oats',
  per100g: Nutrition(kcal: 379, proteinG: 13, carbsG: 60, fatG: 7),
  source: FoodSource.manual,
);

void main() {
  group('changedTable', () {
    test('reads the table from a broadcast, nested or not', () {
      expect(
        changedTable({
          'type': 'broadcast',
          'event': 'changed',
          'payload': {'table': 'food_logs', 'id': 'x'},
        }),
        'food_logs',
      );
      expect(changedTable({'table': 'weigh_ins'}), 'weigh_ins');
    });

    test('ignores anything unexpected', () {
      expect(changedTable({}), isNull);
      expect(changedTable({'payload': 'food_logs'}), isNull);
      expect(changedTable({'table': 42}), isNull);
      expect(changedTable({'table': 'x' * 65}), isNull);
    });
  });

  group('changeSyncProvider', () {
    late FakeChangeSignals signals;
    late FakeFoodRepository foods;
    late FakeAuthRepository auth;

    ProviderContainer container({AuthStatus? status}) {
      signals = FakeChangeSignals();
      foods = FakeFoodRepository();
      auth = FakeAuthRepository(initial: status ?? const SignedIn('user-1'));
      addTearDown(auth.dispose);
      final c = ProviderContainer.test(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          changeSignalsProvider.overrideWithValue(signals),
          foodRepositoryProvider.overrideWithValue(foods),
          snapshotStoreProvider.overrideWithValue(FakeSnapshotStore()),
          householdRepositoryProvider.overrideWithValue(
            FakeHouseholdRepository(),
          ),
        ],
      );
      // As the home screen does.
      return c..listen(changeSyncProvider, (_, _) {});
    }

    test('a change on another device shows up', () async {
      final c = container();
      await c.read(authStatusProvider.future);
      // Riverpod rebuilds the sync on its next tick after signing in.
      await Future<void>.delayed(Duration.zero);
      c.listen(foodsProvider, (_, _) {});
      expect(await c.read(foodsProvider.future), isEmpty);
      expect(signals.watching.last.$1, 'user-1');

      // Saved elsewhere: this device doesn't know yet.
      await foods.save(_oats);
      signals.send('foods');
      await Future<void>.delayed(changeSyncDelay * 2);
      expect((await c.read(foodsProvider.future)).single.name, 'Oats');
    });

    test('a burst of signals refreshes once', () async {
      final c = container();
      await c.read(authStatusProvider.future);
      // Riverpod rebuilds the sync on its next tick after signing in.
      await Future<void>.delayed(Duration.zero);
      c.listen(foodsProvider, (_, _) {});
      await c.read(foodsProvider.future);
      final before = foods.fetches;
      for (var i = 0; i < 5; i++) {
        signals.send('foods');
      }
      await Future<void>.delayed(changeSyncDelay * 2);
      await c.read(foodsProvider.future);
      expect(foods.fetches, before + 1);
    });

    test('after a reconnect everything is refetched', () async {
      final c = container();
      await c.read(authStatusProvider.future);
      // Riverpod rebuilds the sync on its next tick after signing in.
      await Future<void>.delayed(Duration.zero);
      c.listen(foodsProvider, (_, _) {});
      await c.read(foodsProvider.future);

      // Saved while the connection was down: its signal was lost.
      await foods.save(_oats);
      signals.send(everyTable);
      await Future<void>.delayed(changeSyncDelay * 2);
      expect((await c.read(foodsProvider.future)).single.name, 'Oats');
    });

    test('other tables leave the food list alone', () async {
      final c = container();
      await c.read(authStatusProvider.future);
      // Riverpod rebuilds the sync on its next tick after signing in.
      await Future<void>.delayed(Duration.zero);
      c.listen(foodsProvider, (_, _) {});
      await c.read(foodsProvider.future);
      final before = foods.fetches;
      signals
        ..send('weigh_ins')
        ..send('no_such_table');
      await Future<void>.delayed(changeSyncDelay * 2);
      expect(foods.fetches, before);
    });

    test('nobody signed in: nothing is listened to', () async {
      final c = container(status: const SignedOut());
      await c.read(authStatusProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(signals.watching, isEmpty);
    });
  });
}
