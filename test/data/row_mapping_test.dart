import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/app_info.dart';
import 'package:trendline/data/food_logs/food_log_repository.dart';
import 'package:trendline/data/foods/food_repository.dart';
import 'package:trendline/data/profile/profile_repository.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/data/weigh_ins/weigh_in_repository.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/domain/weigh_in.dart';

void main() {
  group('row parsing', () {
    test('numbers arrive as numbers or strings', () {
      expect(readDouble(82), 82.0);
      expect(readDouble('82.40'), 82.4);
      expect(readDoubleOrNull(null), isNull);
      expect(readDoubleOrNull('NaN'), isNull);
      expect(() => readDouble('x'), throwsFormatException);
    });

    test('dates round-trip as local calendar days', () {
      expect(writeDate(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
      expect(readDate('2026-03-07'), DateTime(2026, 3, 7));
    });
  });

  test('profile round-trips, including the stones unit', () {
    final profile = Profile(
      sex: Sex.female,
      birthYear: 1985,
      heightCm: 165.5,
      activityLevel: ActivityLevel.moderate,
      weightUnit: WeightUnit.stLb,
      disclaimerAcceptedAt: DateTime.utc(2026, 11, 24, 9),
    );
    final row = profileToRow(profile);
    expect(row['weight_unit'], 'st_lb');

    final back = profileFromRow({
      ...row,
      'height_cm': '165.5',
      'disclaimer_accepted_at': '2026-11-24T09:00:00+00:00',
    });
    expect(back.sex, Sex.female);
    expect(back.heightCm, 165.5);
    expect(back.weightUnit, WeightUnit.stLb);
    expect(
      back.disclaimerAcceptedAt.isAtSameMomentAs(profile.disclaimerAcceptedAt),
      isTrue,
    );
  });

  test('weigh-in rows map sources and optional values', () {
    final w = weighInFromRow({
      'id': 'x',
      'measured_at': '2026-11-24T07:30:00+00:00',
      'weight_kg': 82.4,
      'body_fat_pct': null,
      'lean_mass_kg': null,
      'source': 'health_connect',
    });
    expect(w.weightKg, 82.4);
    expect(w.bodyFatPct, isNull);
    expect(w.source, WeighInSource.healthConnect);
  });

  test('food drafts are trimmed, rounded and tagged with their source', () {
    final row = foodDraftToRow(
      const FoodDraft(
        name: '  Oats ',
        brand: '  ',
        per100g: Nutrition(kcal: 379.04, proteinG: 13.16, carbsG: 60, fatG: 7),
        source: FoodSource.openFoodFacts,
      ),
    );
    expect(row['name'], 'Oats');
    expect(row['brand'], isNull);
    expect(row['kcal_100g'], 379.0);
    expect(row['protein_100g'], 13.2);
    expect(row['source'], 'off');
  });

  test('a food log row snapshots the food at logging time', () {
    const food = Food(
      id: 'f1',
      name: 'Oats',
      brand: 'Lidl',
      per100g: Nutrition(kcal: 379, proteinG: 13, carbsG: 60, fatG: 7),
      source: FoodSource.manual,
    );
    final row = foodLogToRow(
      day: DateTime(2026, 11, 24),
      eatenAt: DateTime.utc(2026, 11, 24, 8),
      slot: MealSlot.breakfast,
      food: food,
      grams: 50,
    );
    expect(row['eaten_on'], '2026-11-24');
    expect(row['slot'], 'breakfast');
    expect(row['food_name'], 'Oats');
    expect(row['food_brand'], 'Lidl');
    expect(row['kcal'], 189.5);
    expect(row['protein_g'], 6.5);
  });

  test('rescaling a portion keeps it consistent with its snapshot', () {
    const n = Nutrition(kcal: 189.5, proteinG: 6.5, carbsG: 30, fatG: 3.5);
    expect(rescale(n, from: 50, to: 100).kcal, 379);
    expect(rescale(n, from: 50, to: 25).proteinG, 3.3);
    expect(rescale(n, from: 0, to: 25), Nutrition.zero);
  });

  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([\d.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
