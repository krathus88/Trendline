import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';

/// A product from Open Food Facts, already checked for sane values.
class OffProduct {
  const new({
    required this.barcode,
    required this.name,
    required this.per100g,
    this.brand,
    this.sugarG,
    this.saltG,
    this.servingG,
  });

  final String barcode;
  final String name;
  final String? brand;
  final Nutrition per100g;
  final double? sugarG;
  final double? saltG;
  final double? servingG;

  FoodDraft toDraft() => FoodDraft(
    name: name,
    brand: brand,
    barcode: barcode,
    per100g: per100g,
    sugarG: sugarG,
    saltG: saltG,
    servingG: servingG,
    source: FoodSource.openFoodFacts,
  );
}

const int _maxTextLength = 200;
const double _kjPerKcal = 4.184;

/// Parses one Open Food Facts product. Their data is crowd-sourced and
/// untrusted: anything missing, malformed or physically impossible makes the
/// product unusable (returns null) rather than letting bad numbers into
/// someone's food log.
OffProduct? parseOffProduct(Object? json) {
  if (json is! Map<String, dynamic>) return null;

  final barcode = _barcode(json['code']);
  final name = _text(json['product_name_en']) ?? _text(json['product_name']);
  if (barcode == null || name == null) return null;

  final nutriments = json['nutriments'];
  if (nutriments is! Map<String, dynamic>) return null;

  final kcal =
      _number(nutriments['energy-kcal_100g']) ??
      _kjToKcal(_number(nutriments['energy-kj_100g'])) ??
      // Plain `energy` is always kJ.
      _kjToKcal(_number(nutriments['energy_100g']));
  final protein = _number(nutriments['proteins_100g']);
  final carbs = _number(nutriments['carbohydrates_100g']);
  final fat = _number(nutriments['fat_100g']);
  if (kcal == null || protein == null || carbs == null || fat == null) {
    return null;
  }

  final per100g = Nutrition(
    kcal: _round1(kcal),
    proteinG: _round1(protein),
    carbsG: _round1(carbs),
    fatG: _round1(fat),
    // Fibre is optional on UK labels: missing means unknown, not none.
    fibreG: _round1(_number(nutriments['fiber_100g']) ?? 0),
    fibreUnknown: _number(nutriments['fiber_100g']) == null,
  );
  if (validatePer100g(per100g) != null) return null;

  final sugar = _number(nutriments['sugars_100g']);
  final salt = _number(nutriments['salt_100g']);
  final serving = _number(json['serving_quantity']);

  return OffProduct(
    barcode: barcode,
    name: name,
    brand: _brand(json['brands']),
    per100g: per100g,
    // Drop optional values that can't be right instead of rejecting the
    // whole product.
    sugarG: sugar != null && sugar <= per100g.carbsG + 0.5
        ? _round1(sugar)
        : null,
    saltG: salt != null && salt <= 100 ? _round1(salt) : null,
    servingG: serving != null && serving > 0 && serving <= 5000
        ? _round1(serving)
        : null,
  );
}

String? _barcode(Object? value) {
  final s = value?.toString().trim();
  if (s == null || !RegExp(r'^[0-9]{6,14}$').hasMatch(s)) return null;
  return s;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length > _maxTextLength
      ? cleaned.substring(0, _maxTextLength).trim()
      : cleaned;
}

/// `brands` is a comma-separated string on product pages and a list in
/// search results. The first brand is the main one.
String? _brand(Object? value) {
  final first = switch (value) {
    final String s => s.split(',').first,
    final List<dynamic> l when l.isNotEmpty => l.first,
    _ => null,
  };
  return _text(first);
}

double? _number(Object? value) {
  final parsed = switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s.trim()),
    _ => null,
  };
  if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
    return null;
  }
  return parsed;
}

double? _kjToKcal(double? kj) => kj == null ? null : kj / _kjPerKcal;

double _round1(double v) => (v * 10).round() / 10;
