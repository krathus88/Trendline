import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';

/// Basic foods (fruit, veg, meat, rice…) from CoFID, the UK government's
/// food composition data, held in a shared read-only table.
abstract interface class ReferenceFoodRepository {
  /// Basic foods matching [query], best first. Results are drafts: choosing
  /// one copies it into the user's own foods.
  Future<List<FoodDraft>> search(String query);
}

class SupabaseReferenceFoodRepository implements ReferenceFoodRepository {
  new(this._db);

  final SupabaseClient _db;

  /// Results per query, kept for the session: the data only changes with a
  /// new CoFID edition.
  final _cache = <String, List<FoodDraft>>{};

  static const _columns =
      'cofid_code, display_name, kcal_100g, protein_100g, carbs_100g, '
      'fat_100g, fibre_100g, sugar_100g, salt_100g';

  @override
  Future<List<FoodDraft>> search(String query) async {
    final cleaned = cleanReferenceQuery(query);
    if (cleaned.length < 2) return const [];
    final cached = _cache[cleaned];
    if (cached != null) return cached;

    final rows = await _db
        .rpc<List<Map<String, dynamic>>>(
          'search_reference_foods',
          params: {'query': cleaned},
        )
        .select(_columns);
    return _cache[cleaned] = [
      for (final row in rows) ?referenceFoodFromRow(row),
    ];
  }
}

/// Lower-cased, single-spaced and at most 100 characters (the database
/// truncates there too).
String cleanReferenceQuery(String query) {
  final cleaned = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
}

/// A reference food row as a draft, or null if the row is malformed.
FoodDraft? referenceFoodFromRow(Map<String, dynamic> row) {
  final code = row['cofid_code'];
  final name = row['display_name'];
  final kcal = readDoubleOrNull(row['kcal_100g']);
  final protein = readDoubleOrNull(row['protein_100g']);
  final carbs = readDoubleOrNull(row['carbs_100g']);
  final fat = readDoubleOrNull(row['fat_100g']);
  if (code is! String ||
      name is! String ||
      name.trim().isEmpty ||
      kcal == null ||
      protein == null ||
      carbs == null ||
      fat == null) {
    return null;
  }
  return FoodDraft(
    name: name,
    per100g: Nutrition(
      kcal: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      // Some foods have no fibre figure in any source.
      fibreG: readDoubleOrNull(row['fibre_100g']) ?? 0,
      fibreUnknown: readDoubleOrNull(row['fibre_100g']) == null,
    ),
    sugarG: readDoubleOrNull(row['sugar_100g']),
    saltG: readDoubleOrNull(row['salt_100g']),
    source: FoodSource.cofid,
    referenceCode: code,
  );
}
