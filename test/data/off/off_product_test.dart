import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/off/off_product.dart';
import 'package:trendline/domain/food.dart';

Map<String, dynamic> product({
  Object? code = '01219494',
  Object? name = 'Semi skimmed milk',
  Object? nameEn,
  Object? brands = "Sainsbury's",
  Object? serving = 200,
  Map<String, dynamic>? nutriments,
}) => {
  'code': code,
  'product_name': name,
  'product_name_en': ?nameEn,
  'brands': brands,
  'serving_quantity': serving,
  'nutriments':
      nutriments ??
      {
        'energy-kcal_100g': 50,
        'proteins_100g': 3.6,
        'carbohydrates_100g': 4.8,
        'fat_100g': 1.8,
        'fiber_100g': 0,
        'sugars_100g': 4.8,
        'salt_100g': 0.1,
      },
};

void main() {
  group('parseOffProduct', () {
    test('parses a complete product', () {
      final p = parseOffProduct(product())!;
      expect(p.barcode, '01219494');
      expect(p.name, 'Semi skimmed milk');
      expect(p.brand, "Sainsbury's");
      expect(p.per100g.kcal, 50);
      expect(p.per100g.proteinG, 3.6);
      expect(p.sugarG, 4.8);
      expect(p.servingG, 200);
    });

    test('prefers the English name', () {
      final p = parseOffProduct(product(name: 'Lait', nameEn: 'Milk'))!;
      expect(p.name, 'Milk');
    });

    test('takes the first brand from a string or a list', () {
      expect(parseOffProduct(product(brands: 'Aldi, Cowbelle'))!.brand, 'Aldi');
      expect(
        parseOffProduct(product(brands: ['Nescafé', 'Nestlé']))!.brand,
        'Nescafé',
      );
      expect(parseOffProduct(product(brands: null))!.brand, isNull);
    });

    test('reads numbers sent as strings and rounds float noise', () {
      final p = parseOffProduct(
        product(
          nutriments: {
            'energy-kcal_100g': '57',
            'proteins_100g': 2.90000009536743,
            'carbohydrates_100g': '9.3',
            'fat_100g': '1.2',
          },
        ),
      )!;
      expect(p.per100g.kcal, 57);
      expect(p.per100g.proteinG, 2.9);
      expect(p.per100g.carbsG, 9.3);
      expect(p.per100g.fibreG, 0, reason: 'missing fibre counts as zero');
    });

    test('falls back to kJ when kcal is missing', () {
      final p = parseOffProduct(
        product(
          nutriments: {
            'energy-kj_100g': 418.4,
            'proteins_100g': 1,
            'carbohydrates_100g': 20,
            'fat_100g': 1,
          },
        ),
      )!;
      expect(p.per100g.kcal, 100);
    });

    test('rejects products missing a core nutrient', () {
      expect(
        parseOffProduct(
          product(
            nutriments: {
              'energy-kcal_100g': 50,
              'proteins_100g': 3.6,
              'carbohydrates_100g': 4.8,
            },
          ),
        ),
        isNull,
      );
    });

    test('rejects physically impossible values', () {
      expect(
        parseOffProduct(
          product(
            nutriments: {
              'energy-kcal_100g': 5000,
              'proteins_100g': 3.6,
              'carbohydrates_100g': 4.8,
              'fat_100g': 1.8,
            },
          ),
        ),
        isNull,
      );
      expect(
        parseOffProduct(
          product(
            nutriments: {
              'energy-kcal_100g': 400,
              'proteins_100g': 80,
              'carbohydrates_100g': 80,
              'fat_100g': 1,
            },
          ),
        ),
        isNull,
      );
      expect(
        parseOffProduct(
          product(
            nutriments: {
              'energy-kcal_100g': 50,
              'proteins_100g': -3,
              'carbohydrates_100g': 4.8,
              'fat_100g': 1.8,
            },
          ),
        ),
        isNull,
      );
    });

    test('drops implausible optional values instead of the product', () {
      final p = parseOffProduct(
        product(
          serving: 90000,
          nutriments: {
            'energy-kcal_100g': 50,
            'proteins_100g': 3.6,
            'carbohydrates_100g': 4.8,
            'fat_100g': 1.8,
            'sugars_100g': 40,
          },
        ),
      )!;
      expect(p.sugarG, isNull, reason: 'more sugar than carbs');
      expect(p.servingG, isNull);
    });

    test('rejects bad barcodes and missing names', () {
      expect(parseOffProduct(product(code: 'abc')), isNull);
      expect(parseOffProduct(product(code: '123')), isNull);
      expect(parseOffProduct(product(name: '   ')), isNull);
      expect(parseOffProduct(product(name: null)), isNull);
    });

    test('tidies whitespace and caps long names', () {
      final p = parseOffProduct(product(name: '  Oat \n  drink  '))!;
      expect(p.name, 'Oat drink');
      final long = parseOffProduct(product(name: 'x' * 500))!;
      expect(long.name.length, 200);
    });

    test('rejects input that is not a product', () {
      expect(parseOffProduct(null), isNull);
      expect(parseOffProduct('nope'), isNull);
      expect(parseOffProduct(product()..['nutriments'] = 'bad'), isNull);
    });

    test('converts to an Open Food Facts food draft', () {
      final draft = parseOffProduct(product())!.toDraft();
      expect(draft.source, FoodSource.openFoodFacts);
      expect(draft.barcode, '01219494');
    });
  });
}
