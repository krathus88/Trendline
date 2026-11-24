import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/ui/common/format.dart';

void main() {
  final now = DateTime(2026, 11, 24, 15);

  test('day labels', () {
    expect(formatDayLabel(DateTime(2026, 11, 24), now: now), 'Today');
    expect(formatDayLabel(DateTime(2026, 11, 23), now: now), 'Yesterday');
    expect(formatDayLabel(DateTime(2026, 11, 20), now: now), 'Fri 20 Nov');
    expect(formatDayLabel(DateTime(2025, 11, 20), now: now), 'Thu 20 Nov 2025');
  });

  test('numbers', () {
    expect(formatKcal(1240.4), '1,240');
    expect(formatGrams(12.5), '12.5 g');
    expect(formatGrams(120), '120 g');
  });

  test('parseDecimal accepts a comma and rejects junk', () {
    expect(parseDecimal('82,4'), 82.4);
    expect(parseDecimal(' 82.4 '), 82.4);
    expect(parseDecimal('abc'), isNull);
    expect(parseDecimal('Infinity'), isNull);
  });
}
