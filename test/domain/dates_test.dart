import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/dates.dart';

void main() {
  test('dayOf drops the time of day', () {
    expect(dayOf(DateTime(2026, 11, 24, 23, 59)), DateTime(2026, 11, 24));
  });

  test('addDays lands on midnight across clock changes', () {
    // UK clocks go forward on 29 March 2026 and back on 25 October 2026.
    expect(addDays(DateTime(2026, 3, 28), 2), DateTime(2026, 3, 30));
    expect(addDays(DateTime(2026, 10, 24), 2), DateTime(2026, 10, 26));
    expect(addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2));
    expect(addDays(DateTime(2026, 11, 24), -1), DateTime(2026, 11, 23));
  });

  test('daysBetween counts calendar days across clock changes', () {
    expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
    expect(daysBetween(DateTime(2026, 10, 30), DateTime(2026, 10, 24)), -6);
  });
}
