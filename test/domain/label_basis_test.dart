import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/label_basis.dart';
import 'package:trendline/domain/nutrition.dart';

void main() {
  group('labelFactor', () {
    test('per 100 g needs nothing else', () {
      expect(labelFactor(LabelBasis.per100g), 1);
    });

    test('per serving scales by the serving weight', () {
      expect(labelFactor(LabelBasis.perServing, servingG: 25), 4);
      expect(labelFactor(LabelBasis.perServing, servingG: 15.5), 100 / 15.5);
    });

    test('per 100 ml made up uses the volume one serving makes', () {
      // A 15.5 g sachet made up to 220 ml.
      expect(
        labelFactor(LabelBasis.per100mlMadeUp, servingG: 15.5, makesMl: 220),
        closeTo(14.194, 0.001),
      );
    });

    test('missing, zero, negative or non-finite amounts give null', () {
      expect(labelFactor(LabelBasis.perServing), isNull);
      expect(labelFactor(LabelBasis.perServing, servingG: 0), isNull);
      expect(labelFactor(LabelBasis.perServing, servingG: -5), isNull);
      expect(
        labelFactor(LabelBasis.perServing, servingG: double.infinity),
        isNull,
      );
      expect(
        labelFactor(LabelBasis.per100mlMadeUp, servingG: 15.5),
        isNull,
        reason: 'needs how much it makes',
      );
      expect(
        labelFactor(LabelBasis.per100mlMadeUp, servingG: 15.5, makesMl: 0),
        isNull,
      );
      expect(labelFactor(LabelBasis.per100mlMadeUp, makesMl: 220), isNull);
    });
  });

  group('labelToPer100g', () {
    // Nescafé cappuccino sachet, 15.5 g, made up with 200 ml water to 220 ml.
    const perMug = Nutrition(
      kcal: 60,
      proteinG: 1.3,
      carbsG: 10.4,
      fatG: 1.3,
      fibreG: 0.7,
    );
    const per100ml = Nutrition(
      kcal: 27,
      proteinG: 0.6,
      carbsG: 4.7,
      fatG: 0.6,
      fibreG: 0.3,
    );

    test('both columns of one label agree, within label rounding', () {
      final fromServing = labelToPer100g(
        perMug,
        labelFactor(LabelBasis.perServing, servingG: 15.5)!,
      );
      final fromMadeUp = labelToPer100g(
        per100ml,
        labelFactor(LabelBasis.per100mlMadeUp, servingG: 15.5, makesMl: 220)!,
      );
      expect(fromServing.kcal, closeTo(387.1, 0.1));
      expect(fromMadeUp.kcal, closeTo(383.2, 0.1));
      // Labels round each column, so a few percent apart is expected.
      expect(fromMadeUp.kcal / fromServing.kcal, closeTo(1, 0.03));
      expect(fromMadeUp.carbsG, closeTo(66.7, 0.1));
      // One sachet's worth gets back the per-mug figure.
      expect(fromServing.forGrams(15.5).kcal, closeTo(60, 0.1));
    });

    test('unknown fibre stays unknown', () {
      const label = Nutrition(
        kcal: 50,
        proteinG: 1,
        carbsG: 5,
        fatG: 1,
        fibreUnknown: true,
      );
      expect(labelToPer100g(label, 4).fibreUnknown, isTrue);
    });
  });
}
