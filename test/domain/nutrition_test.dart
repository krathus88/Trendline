import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/nutrition.dart';

void main() {
  const oats = Nutrition(
    kcal: 379,
    proteinG: 13.2,
    carbsG: 60,
    fatG: 7,
    fibreG: 10,
  );

  group('forGrams', () {
    test('scales per-100 g values to a portion', () {
      expect(
        oats.forGrams(50),
        const Nutrition(
          kcal: 189.5,
          proteinG: 6.6,
          carbsG: 30,
          fatG: 3.5,
          fibreG: 5,
        ),
      );
    });

    test('rounds to one decimal', () {
      expect(oats.forGrams(33).kcal, 125.1); // 125.07
    });

    test('zero grams is zero nutrition', () {
      expect(oats.forGrams(0), Nutrition.zero);
    });
  });

  group('sum', () {
    test('adds every nutrient', () {
      final total = Nutrition.sum([oats.forGrams(50), oats.forGrams(50)]);
      expect(total.kcal, 379);
      expect(total.proteinG, closeTo(13.2, 1e-9));
    });

    test('an empty day is zero', () {
      expect(Nutrition.sum(const []), Nutrition.zero);
    });
  });

  group('unknown fibre', () {
    const banana = Nutrition(
      kcal: 81,
      proteinG: 1.2,
      carbsG: 19.9,
      fatG: 0.1,
      fibreUnknown: true,
    );

    test('a portion of a food with unknown fibre is unknown too', () {
      expect(banana.forGrams(120).fibreUnknown, isTrue);
      expect(oats.forGrams(50).fibreUnknown, isFalse);
    });

    test('a total with any unknown fibre keeps the known part', () {
      final total = Nutrition.sum([oats.forGrams(50), banana.forGrams(120)]);
      expect(total.fibreG, 5);
      expect(total.fibreUnknown, isTrue);
    });

    test('unknown and zero fibre are different', () {
      expect(banana == banana.forGrams(100), isTrue);
      expect(
        banana ==
            const Nutrition(kcal: 81, proteinG: 1.2, carbsG: 19.9, fatG: 0.1),
        isFalse,
      );
    });
  });

  group('validatePer100g', () {
    test('accepts real foods', () {
      expect(validatePer100g(oats), isNull);
      expect(
        validatePer100g(
          const Nutrition(kcal: 884, proteinG: 0, carbsG: 0, fatG: 100),
        ),
        isNull,
        reason: 'pure oil',
      );
    });

    test('rejects negative or non-finite values', () {
      expect(
        validatePer100g(
          const Nutrition(kcal: 100, proteinG: -1, carbsG: 0, fatG: 0),
        ),
        isNotNull,
      );
      expect(
        validatePer100g(
          const Nutrition(kcal: double.nan, proteinG: 0, carbsG: 0, fatG: 0),
        ),
        isNotNull,
      );
    });

    test('rejects impossible energy and macros', () {
      expect(
        validatePer100g(
          const Nutrition(kcal: 1000, proteinG: 0, carbsG: 0, fatG: 0),
        ),
        isNotNull,
      );
      expect(
        validatePer100g(
          const Nutrition(kcal: 400, proteinG: 60, carbsG: 50, fatG: 0),
        ),
        isNotNull,
      );
    });
  });
}
