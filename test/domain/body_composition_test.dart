import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/body_composition.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/weigh_in.dart';

void main() {
  final today = DateTime(2026, 11, 28);

  WeighIn w(int daysAgo, double kg, {double? fat, double? lean}) => WeighIn(
    id: '$daysAgo',
    measuredAt: addDays(today, -daysAgo).add(const Duration(hours: 7)),
    weightKg: kg,
    bodyFatPct: fat,
    leanMassKg: lean,
  );

  test('nothing without body composition readings', () {
    expect(recentLeanMassKg([w(1, 90)], today: today), isNull);
  });

  test('uses lean mass when the scale recorded it', () {
    expect(recentLeanMassKg([w(1, 90, lean: 70)], today: today), 70);
  });

  test('works lean mass out from body fat', () {
    // 90 kg at 20% fat = 72 kg lean.
    expect(recentLeanMassKg([w(1, 90, fat: 20)], today: today), 72);
  });

  test('takes the median, so one odd reading does not move it', () {
    final lean = recentLeanMassKg([
      w(1, 90, lean: 70),
      w(2, 90, lean: 71),
      w(3, 90, lean: 55), // a wild reading
    ], today: today);
    expect(lean, 70);
  });

  test('ignores readings older than 30 days', () {
    expect(recentLeanMassKg([w(31, 90, lean: 70)], today: today), isNull);
  });

  test('ignores impossible readings', () {
    expect(recentLeanMassKg([w(1, 90, lean: 95)], today: today), isNull);
  });
}
