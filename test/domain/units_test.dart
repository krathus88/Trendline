import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/units.dart';

void main() {
  group('conversions', () {
    test('kg and lb round-trip', () {
      expect(lbToKg(kgToLb(82.4)), closeTo(82.4, 1e-9));
      expect(kgToLb(1), closeTo(2.20462, 1e-5));
    });

    test('stones and pounds to kg', () {
      expect(stLbToKg(12, 0), closeTo(76.2035, 1e-4));
      expect(stLbToKg(0, 14), closeTo(stLbToKg(1, 0), 1e-9));
    });

    test('kg to stones and pounds', () {
      final (:stones, :pounds) = kgToStLb(stLbToKg(12, 13.7));
      expect(stones, 12);
      expect(pounds, closeTo(13.7, 1e-9));
    });

    test('pounds that round up to 14 carry into the next stone', () {
      // 13.96 lb would display as "13 st 14.0 lb" without the carry.
      final (:stones, :pounds) = kgToStLb(stLbToKg(12, 13.96));
      expect(stones, 13);
      expect(pounds, 0);
    });
  });

  group('formatWeight', () {
    test('formats each unit', () {
      expect(formatWeight(82.4, WeightUnit.kg), '82.4 kg');
      expect(formatWeight(lbToKg(181.7), WeightUnit.lb), '181.7 lb');
      expect(
        formatWeight(stLbToKg(12, 13.7), WeightUnit.stLb),
        '12 st 13.7 lb',
      );
    });

    test('rounds to one decimal', () {
      expect(formatWeight(82.449, WeightUnit.kg), '82.4 kg');
      expect(formatWeight(82.46, WeightUnit.kg), '82.5 kg');
    });
  });

  group('formatWeightChange', () {
    test('shows a sign and uses a true minus', () {
      expect(formatWeightChange(-0.62, WeightUnit.kg), '−0.6 kg');
      expect(formatWeightChange(0.5, WeightUnit.kg), '+0.5 kg');
    });

    test('shows pounds for lb and stones users', () {
      expect(formatWeightChange(lbToKg(-1.2), WeightUnit.lb), '−1.2 lb');
      expect(formatWeightChange(lbToKg(-1.2), WeightUnit.stLb), '−1.2 lb');
    });

    test('tiny changes read as zero, not "-0.0"', () {
      expect(formatWeightChange(-0.01, WeightUnit.kg), '0.0 kg');
    });
  });
}
