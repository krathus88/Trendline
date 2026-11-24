import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/health/health_sync_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/domain/weigh_in.dart';
import 'package:trendline/platform/health_source.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeWeighInRepository weighIns;
  late FakeHealthSource health;
  late ProviderContainer container;
  // An hour ago, so it is never in the future whenever the tests run.
  final morning = DateTime.now().subtract(const Duration(hours: 1));

  HealthReading reading(String id, DateTime at, double value) =>
      HealthReading(id: id, at: at, value: value);

  Future<void> start() async {
    container =
        ProviderContainer.test(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              weighInRepositoryProvider.overrideWithValue(weighIns),
              healthSourceProvider.overrideWithValue(health),
            ],
          )
          // Riverpod 3 pauses providers nobody listens to.
          ..listen(authStatusProvider, (_, _) {})
          ..listen(weighInsProvider, (_, _) {})
          ..listen(healthSyncProvider, (_, _) {});
    await container.read(authStatusProvider.future);
    await container.read(healthSyncProvider.future);
  }

  HealthSyncState state() => container.read(healthSyncProvider).value!;
  HealthSyncNotifier notifier() => container.read(healthSyncProvider.notifier);

  /// Lets the sync that starts with the app run to the end.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    auth = FakeAuthRepository(initial: const SignedIn('user-1'));
    weighIns = FakeWeighInRepository();
    health = FakeHealthSource();
  });

  tearDown(() => auth.dispose());

  test('not connected: reads nothing', () async {
    await start();
    await settle();
    expect(state().availability, HealthAvailability.available);
    expect(state().connected, isFalse);
    expect(health.reads, isEmpty);
  });

  test('already connected: imports when the app starts', () async {
    health
      ..granted = true
      ..readings = BodyReadings(
        weightKg: [reading('w1', morning, 90)],
        bodyFatPct: [reading('f1', morning, 24.5)],
      );
    await start();
    await settle();

    expect(state().lastAdded, 1);
    expect(state().syncing, isFalse);
    final list = container.read(weighInsProvider).value!;
    expect(list.single.source, WeighInSource.healthConnect);
    expect(list.single.bodyFatPct, 24.5);
  });

  test('connecting asks for access and imports straight away', () async {
    health.readings = BodyReadings(weightKg: [reading('w1', morning, 90)]);
    await start();

    expect(await notifier().connect(), isTrue);
    expect(state().connected, isTrue);
    expect(weighIns.items, hasLength(1));
  });

  test('if access is refused, nothing is read', () async {
    health.grantOnRequest = false;
    await start();

    expect(await notifier().connect(), isFalse);
    expect(state().connected, isFalse);
    expect(health.reads, isEmpty);
  });

  test(
    'syncing again adds nothing new and rereads only the last week',
    () async {
      health
        ..granted = true
        ..readings = BodyReadings(weightKg: [reading('w1', morning, 90)]);
      await start();
      await settle();

      expect(await notifier().sync(), 0);
      expect(weighIns.items, hasLength(1));
      expect(health.reads.last.start, addDays(dayOf(morning), -7));
    },
  );

  test('a reading deleted in the app is not imported again', () async {
    health
      ..granted = true
      ..readings = BodyReadings(weightKg: [reading('w1', morning, 90)]);
    await start();
    await settle();

    final id = container.read(weighInsProvider).value!.single.id;
    await container.read(weighInsProvider.notifier).delete(id);
    expect(await notifier().sync(), 0);
    expect(container.read(weighInsProvider).value, isEmpty);
  });

  test('a failed read is reported and keeps earlier data', () async {
    health.granted = true;
    await start();
    await settle();
    health.readError = const HealthSourceException('Busy');

    await expectLater(notifier().sync(), throwsA(isA<HealthSourceException>()));
    expect(state().error, isA<HealthSourceException>());
    expect(state().syncing, isFalse);

    health.readError = null;
    await notifier().sync();
    expect(state().error, isNull);
  });

  test('unavailable platform: never connected', () async {
    health
      ..status = HealthAvailability.unavailable
      ..granted = true;
    await start();
    await settle();
    expect(state().connected, isFalse);
    expect(health.reads, isEmpty);
  });

  test('notices access withdrawn outside the app', () async {
    health.granted = true;
    await start();
    await settle();
    health.granted = false;

    await notifier().recheck();
    expect(state().connected, isFalse);
  });

  test(
    'coming back to the app soon after a sync does not sync again',
    () async {
      health.granted = true;
      await start();
      await settle();
      final before = health.reads.length;

      await notifier().recheck();
      expect(health.reads, hasLength(before));
    },
  );

  test('disconnecting keeps imported readings', () async {
    health
      ..granted = true
      ..readings = BodyReadings(weightKg: [reading('w1', morning, 90)]);
    await start();
    await settle();

    await notifier().disconnect();
    expect(state().connected, isFalse);
    expect(health.granted, isFalse);
    expect(weighIns.items, hasLength(1));
  });

  test('signed out: off', () async {
    auth = FakeAuthRepository();
    health.granted = true;
    await start();
    expect(state().connected, isFalse);
    expect(health.reads, isEmpty);
  });
}
