import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/health_import.dart';
import 'package:trendline/domain/weigh_in.dart';

final now = DateTime(2026, 11, 25, 23);
final morning = DateTime(2026, 11, 25, 7);

HealthReading r(String id, DateTime at, double value) =>
    HealthReading(id: id, at: at, value: value);

WeighIn imported(String id, DateTime at, double kg) => WeighIn(
  id: 'row-$id',
  measuredAt: at,
  weightKg: kg,
  source: WeighInSource.healthConnect,
  externalId: id,
);

WeighIn manual(DateTime at, double kg) =>
    WeighIn(id: 'manual-$at', measuredAt: at, weightKg: kg);

List<ImportedWeighIn> plan(
  BodyReadings readings, [
  List<WeighIn> existing = const [],
]) => planHealthImport(readings, existing: existing, now: now);

void main() {
  group('planHealthImport', () {
    test('nothing to read gives nothing to import', () {
      expect(plan(const BodyReadings()), isEmpty);
    });

    test('imports a weight with the body fat and lean mass beside it', () {
      final result = plan(
        BodyReadings(
          weightKg: [r('w1', morning, 90)],
          bodyFatPct: [r('f1', morning.add(const Duration(seconds: 2)), 25)],
          leanMassKg: [r('l1', morning, 67.5)],
        ),
      );
      expect(result, hasLength(1));
      expect(result.single.externalId, 'w1');
      expect(result.single.weightKg, 90);
      expect(result.single.bodyFatPct, 25);
      expect(result.single.leanMassKg, 67.5);
    });

    test('pairs body fat with the closest weight, not a later one', () {
      final evening = morning.add(const Duration(hours: 12));
      final result = plan(
        BodyReadings(
          weightKg: [r('w1', morning, 90), r('w2', evening, 91)],
          bodyFatPct: [r('f2', evening, 26)],
        ),
      );
      expect(result.map((w) => w.bodyFatPct), [null, 26]);
    });

    test('ignores body fat recorded too far from the weight', () {
      final result = plan(
        BodyReadings(
          weightKg: [r('w1', morning, 90)],
          bodyFatPct: [r('f1', morning.add(const Duration(minutes: 6)), 25)],
        ),
      );
      expect(result.single.bodyFatPct, isNull);
    });

    test('body fat without a weight is not imported on its own', () {
      expect(plan(BodyReadings(bodyFatPct: [r('f1', morning, 25)])), isEmpty);
    });

    test('skips readings already imported', () {
      final result = plan(BodyReadings(weightKg: [r('w1', morning, 90)]), [
        imported('w1', morning, 90),
      ]);
      expect(result, isEmpty);
    });

    test('skips impossible weights and drops impossible body values', () {
      final result = plan(
        BodyReadings(
          weightKg: [
            r('tiny', morning, 5),
            r('huge', morning.add(const Duration(hours: 1)), 900),
            r('nan', morning.add(const Duration(hours: 2)), double.nan),
            r('ok', morning.add(const Duration(hours: 3)), 90),
          ],
          bodyFatPct: [r('f', morning.add(const Duration(hours: 3)), 90)],
          leanMassKg: [r('l', morning.add(const Duration(hours: 3)), 95)],
        ),
      );
      expect(result.single.externalId, 'ok');
      expect(result.single.bodyFatPct, isNull, reason: '90% is out of range');
      expect(result.single.leanMassKg, isNull, reason: 'more than the weight');
    });

    test('skips readings dated in the future', () {
      final result = plan(
        BodyReadings(weightKg: [r('w1', now.add(const Duration(days: 1)), 90)]),
      );
      expect(result, isEmpty);
    });

    test('keeps one copy of a reading written by two apps', () {
      final result = plan(
        BodyReadings(
          weightKg: [
            r('scale-app', morning, 90),
            r('other-app', morning.add(const Duration(minutes: 1)), 90.1),
          ],
        ),
      );
      expect(result.single.externalId, 'scale-app');
    });

    test('a reading duplicating one imported earlier is skipped', () {
      final result = plan(
        BodyReadings(weightKg: [r('other-app', morning, 90)]),
        [imported('scale-app', morning, 90)],
      );
      expect(result, isEmpty);
    });

    test('two real weigh-ins close together are both kept', () {
      final result = plan(
        BodyReadings(
          weightKg: [
            r('w1', morning, 90),
            r('w2', morning.add(const Duration(minutes: 2)), 91),
          ],
        ),
      );
      expect(result, hasLength(2));
    });

    test('skips a reading already typed in by hand the same day', () {
      final result = plan(BodyReadings(weightKg: [r('w1', morning, 90.3)]), [
        manual(morning.add(const Duration(hours: 3)), 90),
      ]);
      expect(result, isEmpty);
    });

    test('keeps a reading that differs from the manual one', () {
      final result = plan(BodyReadings(weightKg: [r('w1', morning, 91)]), [
        manual(morning, 90),
      ]);
      expect(result, hasLength(1));
    });

    test('a manual weigh-in on another day does not block a reading', () {
      final result = plan(BodyReadings(weightKg: [r('w1', morning, 90)]), [
        manual(morning.subtract(const Duration(days: 1)), 90),
      ]);
      expect(result, hasLength(1));
    });

    test('returns readings oldest first', () {
      final result = plan(
        BodyReadings(
          weightKg: [
            r('later', morning, 89),
            r('earlier', morning.subtract(const Duration(days: 1)), 90),
          ],
        ),
      );
      expect(result.map((w) => w.externalId), ['earlier', 'later']);
    });
  });

  group('healthSyncStart', () {
    test('reads the whole history window the first time', () {
      expect(
        healthSyncStart(const [], now: now, historyDays: 400),
        DateTime(2025, 10, 21),
      );
    });

    test('starts a week before the newest imported reading', () {
      expect(
        healthSyncStart(
          [
            imported('a', DateTime(2026, 11, 20, 7), 90),
            imported('b', DateTime(2026, 11, 10, 7), 91),
            manual(DateTime(2026, 11, 24, 7), 89),
          ],
          now: now,
          historyDays: 400,
        ),
        DateTime(2026, 11, 13),
      );
    });

    test('never starts before the history window', () {
      expect(
        healthSyncStart(
          [imported('a', DateTime(2025, 10, 22, 7), 90)],
          now: now,
          historyDays: 400,
        ),
        DateTime(2025, 10, 21),
      );
    });
  });
}
