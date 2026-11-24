import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/trend.dart';
import 'package:trendline/domain/weigh_in.dart';

WeighIn w(DateTime at, double kg) =>
    WeighIn(id: '${at.toIso8601String()}-$kg', measuredAt: at, weightKg: kg);

void main() {
  group('computeTrend', () {
    test('no weigh-ins gives no trend', () {
      expect(computeTrend(const []), isEmpty);
    });

    test('a single weigh-in starts the trend at that weight', () {
      final trend = computeTrend([w(DateTime(2026, 11, 1, 7), 90)]);
      expect(trend, hasLength(1));
      expect(trend.single.trendKg, 90);
      expect(trend.single.weightKg, 90);
      expect(trend.single.day, DateTime(2026, 11));
    });

    test('applies the moving average to each new reading', () {
      final trend = computeTrend([
        w(DateTime(2026, 11, 1, 7), 90),
        w(DateTime(2026, 11, 2, 7), 89),
      ]);
      // 90 + 0.1 * (89 - 90)
      expect(trend.last.trendKg, closeTo(89.9, 1e-9));
    });

    test('missing days carry the trend forward', () {
      final trend = computeTrend([
        w(DateTime(2026, 11, 1, 7), 90),
        w(DateTime(2026, 11, 4, 7), 89),
      ]);
      expect(trend.map((p) => p.day), [
        DateTime(2026, 11),
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 4),
      ]);
      expect(trend[1].trendKg, 90);
      expect(trend[1].weightKg, isNull);
      expect(trend[2].trendKg, 90);
      expect(trend[3].trendKg, closeTo(89.9, 1e-9));
    });

    test('uses the earliest reading of a day and ignores later ones', () {
      final trend = computeTrend([
        w(DateTime(2026, 11, 1, 7), 90),
        w(DateTime(2026, 11, 2, 21), 95), // evening, after dinner
        w(DateTime(2026, 11, 2, 7), 89), // morning
      ]);
      expect(trend.last.weightKg, 89);
      expect(trend.last.trendKg, closeTo(89.9, 1e-9));
    });

    test('input order does not matter', () {
      final a = computeTrend([
        w(DateTime(2026, 11, 1, 7), 90),
        w(DateTime(2026, 11, 2, 7), 89),
        w(DateTime(2026, 11, 3, 7), 88),
      ]);
      final b = computeTrend([
        w(DateTime(2026, 11, 3, 7), 88),
        w(DateTime(2026, 11, 1, 7), 90),
        w(DateTime(2026, 11, 2, 7), 89),
      ]);
      expect(b.map((p) => p.trendKg), a.map((p) => p.trendKg));
    });

    test('extends to [until], carrying the last trend', () {
      final trend = computeTrend([
        w(DateTime(2026, 11, 1, 7), 90),
      ], until: DateTime(2026, 11, 3, 12));
      expect(trend, hasLength(3));
      expect(trend.last.day, DateTime(2026, 11, 3));
      expect(trend.last.trendKg, 90);
    });

    test('an [until] before the last reading is ignored', () {
      final trend = computeTrend([
        w(DateTime(2026, 11, 1, 7), 90),
        w(DateTime(2026, 11, 5, 7), 89),
      ], until: DateTime(2026, 11, 2));
      expect(trend.last.day, DateTime(2026, 11, 5));
    });

    test('alpha of 1 follows the raw readings exactly', () {
      final trend = computeTrend([
        w(DateTime(2026, 11, 1, 7), 90),
        w(DateTime(2026, 11, 2, 7), 85),
      ], alpha: 1);
      expect(trend.last.trendKg, 85);
    });

    test('one-off spikes are heavily damped', () {
      final trend = computeTrend([
        for (var d = 1; d <= 10; d++) w(DateTime(2026, 11, d, 7), 90),
        w(DateTime(2026, 11, 11, 7), 93), // e.g. a salty meal the night before
      ]);
      expect(trend.last.trendKg, closeTo(90.3, 1e-9));
    });

    test('produces one point per day across a clock change', () {
      // UK clocks go back on 25 October 2026.
      final trend = computeTrend([
        w(DateTime(2026, 10, 24, 7), 90),
        w(DateTime(2026, 10, 27, 7), 89),
      ]);
      expect(trend.map((p) => p.day), [
        DateTime(2026, 10, 24),
        DateTime(2026, 10, 25),
        DateTime(2026, 10, 26),
        DateTime(2026, 10, 27),
      ]);
    });

    test('handles extreme but valid weights', () {
      final trend = computeTrend([
        w(DateTime(2026, 11, 1, 7), WeighIn.maxWeightKg),
        w(DateTime(2026, 11, 2, 7), WeighIn.minWeightKg),
      ]);
      expect(trend.last.trendKg, closeTo(362.5, 1e-9));
    });
  });

  group('weeklyTrendChangeKg', () {
    test('is null with less than 8 days of trend', () {
      final trend = computeTrend([
        for (var d = 1; d <= 7; d++) w(DateTime(2026, 11, d, 7), 90 - d * 0.1),
      ]);
      expect(weeklyTrendChangeKg(trend), isNull);
    });

    test('is the trend change over the last 7 days', () {
      final trend = computeTrend([
        for (var d = 1; d <= 8; d++) w(DateTime(2026, 11, d, 7), 90),
      ]);
      expect(weeklyTrendChangeKg(trend), 0);

      final losing = [
        for (var d = 0; d < 8; d++)
          TrendPoint(day: DateTime(2026, 11, d + 1), trendKg: 90 - d * 0.1),
      ];
      expect(weeklyTrendChangeKg(losing), closeTo(-0.7, 1e-9));
    });
  });
}
