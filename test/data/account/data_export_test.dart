import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/account/data_export.dart';

void main() {
  final export = <String, Object?>{
    'format': 1,
    'weigh_ins': [
      {
        'measured_at': '2026-11-20T07:30:00+00:00',
        'weight_kg': 82.4,
        'body_fat_pct': null,
        'lean_mass_kg': null,
        'source': 'manual',
        'user_id': 'u1',
      },
      {
        'measured_at': '2026-11-21T07:31:00+00:00',
        'weight_kg': 82.1,
        'body_fat_pct': 21.5,
        'lean_mass_kg': 64.4,
        'source': 'health_connect',
      },
    ],
    'food_logs': [
      {
        'eaten_on': '2026-11-21',
        'eaten_at': '2026-11-21T12:00:00+00:00',
        'slot': 'lunch',
        'food_name': 'Chicken, rice "bowl"',
        'food_brand': null,
        'grams': 350,
        'kcal': 520.5,
        'protein_g': 40,
        'carbs_g': 60,
        'fat_g': 12,
        'fibre_g': null,
      },
      {
        'eaten_on': '2026-11-21',
        'eaten_at': '2026-11-21T19:00:00+00:00',
        'slot': 'dinner',
        'food_name': '=HYPERLINK("http://example.com")',
        'food_brand': '+Brand',
        'grams': 100,
        'kcal': 100,
        'protein_g': 1,
        'carbs_g': 2,
        'fat_g': 3,
        'fibre_g': 0,
      },
    ],
  };

  test('everything is the export as indented JSON', () {
    final json = ExportFile.everything.build(export);
    expect(jsonDecode(json), export);
    expect(json, contains('\n  "format": 1'));
  });

  test('weigh-ins CSV has a header, one line per reading and blanks', () {
    expect(
      ExportFile.weighIns.build(export),
      'measured_at,weight_kg,body_fat_pct,lean_mass_kg,source\r\n'
      '2026-11-20T07:30:00+00:00,82.4,,,manual\r\n'
      '2026-11-21T07:31:00+00:00,82.1,21.5,64.4,health_connect\r\n',
    );
  });

  test('food log CSV quotes commas and quotes, and defuses formulas', () {
    final lines = ExportFile.foodLog.build(export).split('\r\n');
    expect(lines.first, startsWith('eaten_on,eaten_at,slot,food_name,'));
    expect(lines[1], contains(',"Chicken, rice ""bowl""",,350,520.5,'));
    expect(lines[1], endsWith(',40,60,12,'));
    expect(
      lines[2],
      contains(',"\'=HYPERLINK(""http://example.com"")",\'+Brand,'),
    );
  });

  test('numbers are never treated as formulas, even negative ones', () {
    expect(
      toCsv(['a', 'b'], [
        {'a': -1.5, 'b': '-1.5'},
      ]),
      "a,b\r\n-1.5,'-1.5\r\n",
    );
  });

  test('missing or malformed tables give just the header', () {
    expect(
      ExportFile.weighIns.build({'weigh_ins': 'oops'}),
      'measured_at,weight_kg,body_fat_pct,lean_mass_kg,source\r\n',
    );
    expect(ExportFile.foodLog.build(const {}), startsWith('eaten_on,'));
  });

  test('file names carry the day and the right type', () {
    final day = DateTime(2026, 3, 7, 23, 59);
    expect(
      ExportFile.everything.fileName(day),
      'trendline-data-2026-03-07.json',
    );
    expect(
      ExportFile.weighIns.fileName(day),
      'trendline-weigh-ins-2026-03-07.csv',
    );
    expect(
      ExportFile.foodLog.fileName(day),
      'trendline-food-log-2026-03-07.csv',
    );
    expect(ExportFile.everything.mimeType, 'application/json');
    expect(ExportFile.foodLog.mimeType, 'text/csv');
  });
}
