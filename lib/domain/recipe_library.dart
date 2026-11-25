import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

/// What an ingredient does in a dish. The planner uses it when scaling a
/// dish to a day's targets (more protein, less carb).
enum IngredientRole {
  protein,
  carb,
  veg,
  fruit,
  dairy,
  fat,
  sauce,
  liquid,
  flavour,
}

enum Cuisine { british, indian, italian, mexican, chinese, mediterranean }

/// One ingredient of a library recipe: a basic food, by CoFID code and name
/// (codes alone aren't unique), in raw grams.
@immutable
class LibraryIngredient {
  const new({
    required this.cofidCode,
    required this.cofidName,
    required this.rawGrams,
    required this.role,
  });

  final String cofidCode;
  final String cofidName;
  final double rawGrams;
  final IngredientRole role;

  ({String code, String name}) get key => (code: cofidCode, name: cofidName);
}

/// A recipe from the built-in library. It ships with the app; using it
/// copies it into the user's own recipes.
@immutable
class LibraryRecipe {
  const new({
    required this.id,
    required this.version,
    required this.name,
    required this.meals,
    required this.cuisine,
    required this.portions,
    required this.fridgeDays,
    required this.freezable,
    required this.ingredients,
    this.method,
  });

  /// Stable for the life of the recipe; [version] goes up when it changes.
  final String id;
  final int version;
  final String name;
  final Set<MealSlot> meals;

  /// Every library recipe has one; a no-cook snack made from a template
  /// (yogurt with berries) has none.
  final Cuisine? cuisine;
  final int portions;
  final int fridgeDays;
  final bool freezable;
  final List<LibraryIngredient> ingredients;

  /// Cooking steps. Optional: added to library recipes over time.
  final String? method;
}

/// The library file's format version this app reads.
const int libraryFormat = 1;

/// Parses the recipe library file. Throws [FormatException] on anything
/// unexpected: the file ships with the app, so a mistake should fail its
/// tests, not show a broken recipe.
List<LibraryRecipe> parseRecipeLibrary(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, dynamic> || root['format'] != libraryFormat) {
    throw const FormatException('Unknown recipe library format');
  }
  final recipes = root['recipes'];
  if (recipes is! List) throw const FormatException('No recipes list');
  final parsed = [for (final r in recipes) _recipe(r)];
  final ids = <String>{};
  for (final r in parsed) {
    if (!ids.add(r.id)) throw FormatException('Duplicate recipe id ${r.id}');
  }
  return parsed;
}

final _id = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _code = RegExp(r'^[0-9]{2}-[0-9]{3,4}$');

LibraryRecipe _recipe(Object? json) {
  if (json is! Map<String, dynamic>) {
    throw const FormatException('A recipe must be an object');
  }
  final id = _string(json, 'id');
  if (!_id.hasMatch(id) || id.length > 80) {
    throw FormatException('Bad recipe id "$id"');
  }
  String where(String field) => '$id: $field';

  final version = _int(json, 'version', where);
  final portions = _int(json, 'portions', where);
  final fridgeDays = _int(json, 'fridge_days', where);
  final name = _string(json, 'name').trim();
  if (version < 1 ||
      portions < 1 ||
      portions > 50 ||
      fridgeDays < 0 ||
      fridgeDays > 7 ||
      name.isEmpty ||
      name.length > 200) {
    throw FormatException('${where('values')} out of range');
  }
  final meals = json['meals'];
  if (meals is! List || meals.isEmpty) {
    throw FormatException(where('meals'));
  }
  final ingredients = json['ingredients'];
  if (ingredients is! List || ingredients.isEmpty || ingredients.length > 200) {
    throw FormatException(where('ingredients'));
  }
  final freezable = json['freezable'];
  if (freezable is! bool) throw FormatException(where('freezable'));
  final method = json['method'];
  if (method != null && (method is! String || method.length > 10000)) {
    throw FormatException(where('method'));
  }

  return LibraryRecipe(
    id: id,
    version: version,
    name: name,
    meals: {for (final m in meals) _enum(MealSlot.values, m, where('meals'))},
    cuisine: _enum(Cuisine.values, json['cuisine'], where('cuisine')),
    portions: portions,
    fridgeDays: fridgeDays,
    freezable: freezable,
    method: method as String?,
    ingredients: [
      for (final i in ingredients) _ingredient(i, where('ingredients')),
    ],
  );
}

LibraryIngredient _ingredient(Object? json, String where) {
  if (json is! Map<String, dynamic>) throw FormatException(where);
  final code = _string(json, 'cofid');
  final name = _string(json, 'name');
  final grams = json['grams'];
  if (!_code.hasMatch(code) || name.isEmpty) {
    throw FormatException('$where: bad CoFID reference "$code"');
  }
  if (grams is! num || grams <= 0 || grams >= 5000) {
    throw FormatException('$where: bad amount for $name');
  }
  return LibraryIngredient(
    cofidCode: code,
    cofidName: name,
    rawGrams: grams.toDouble(),
    role: _enum(IngredientRole.values, json['role'], '$where: $name role'),
  );
}

String _string(Map<String, dynamic> json, String field) {
  final v = json[field];
  if (v is! String) throw FormatException('Missing "$field"');
  return v;
}

int _int(
  Map<String, dynamic> json,
  String field,
  String Function(String) where,
) {
  final v = json[field];
  if (v is! int) throw FormatException(where(field));
  return v;
}

T _enum<T extends Enum>(List<T> values, Object? name, String where) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('$where: unknown "$name"');
}

/// A library recipe's nutrition from its basic foods' values per 100 g, or
/// null if any of them is missing.
RecipeNutrition? libraryRecipeNutrition(
  LibraryRecipe recipe,
  Map<({String code, String name}), Nutrition> per100g,
) {
  var batch = Nutrition.zero;
  for (final i in recipe.ingredients) {
    final n = per100g[i.key];
    if (n == null) return null;
    batch += n.forGrams(i.rawGrams);
  }
  return recipeNutrition(
    Recipe(
      id: recipe.id,
      name: recipe.name,
      portions: recipe.portions,
      ingredients: [RecipeIngredient(foodId: recipe.id, rawGrams: 100)],
    ),
    {
      recipe.id: Food(
        id: recipe.id,
        name: recipe.name,
        per100g: batch,
        source: FoodSource.manual,
      ),
    },
  );
}
