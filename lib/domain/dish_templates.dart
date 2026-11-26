import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';

/// The herbs and spices (and aromatics) that give a dish its cuisine, in
/// grams per portion.
@immutable
class FlavourProfile {
  const new({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.ingredients,
    this.base,
    this.finish,
  });

  final String id;

  /// Shown in dish names: "Indian chicken rice bowl".
  final String name;
  final Cuisine cuisine;

  /// Grams per portion.
  final List<LibraryIngredient> ingredients;

  /// How a pan dish starts with this flavour (the onion, garlic and
  /// spices), for a template method's {flavour_base}.
  final String? base;

  /// How a dish is finished with it (lemon juice, fresh herbs), for
  /// {flavour_finish}.
  final String? finish;
}

/// One choice for a template slot: a basic food, raw, with the cooked form
/// CoFID has for it (used to estimate the cooked weight).
@immutable
class TemplateOption {
  const new({
    required this.label,
    required this.raw,
    this.cooked,
    this.noun,
    this.prep,
    this.done,
  });

  /// Shown in dish names: "chicken", "brown rice".
  final String label;
  final FoodKey raw;
  final FoodKey? cooked;

  /// How a method names it, when that differs from [label] ("chickpeas"
  /// for "chickpea").
  final String? noun;

  /// Getting it ready, as a sentence ("Drain and rinse the chickpeas."),
  /// for a method's {prep}.
  final String? prep;

  /// How to tell it's cooked ("the chicken has no pink left"), for a
  /// method's {done}.
  final String? done;

  String get methodNoun => noun ?? label;
}

/// One ingredient role in a dish shape, with its amount per portion and the
/// range the planner may scale it within.
@immutable
class TemplateSlot {
  const new({
    required this.role,
    required this.grams,
    required this.min,
    required this.max,
    required this.options,
    this.optional = false,
  });

  final IngredientRole role;
  final double grams;
  final double min;
  final double max;
  final List<TemplateOption> options;
  final bool optional;
}

/// A dish shape: slots to fill, and the flavour profiles that suit it.
@immutable
class DishTemplate {
  const new({
    required this.id,
    required this.version,
    required this.name,
    required this.meals,
    required this.portions,
    required this.fridgeDays,
    required this.freezable,
    required this.flavourIds,
    required this.slots,
    this.noCook = false,
    this.label,
    this.method = const [],
  });

  final String id;
  final int version;

  /// How to make it, step by step, with placeholders (see [dishMethod]).
  /// Empty when there are no instructions yet.
  final List<MethodStep> method;

  /// The dish shape's name for pickers ("Yogurt bowl"), when its [name]
  /// pattern says too little once the placeholders are taken out.
  final String? label;

  /// With placeholders: {flavour}, and any ingredient role ({protein},
  /// {carb}, {veg}, {fruit}...) for the option picked for it.
  final String name;
  final Set<MealSlot> meals;
  final int portions;
  final int fridgeDays;
  final bool freezable;

  /// Empty only for [noCook] templates, which have no flavour profile.
  final List<String> flavourIds;
  final List<TemplateSlot> slots;

  /// Put together, not cooked (a snack like yogurt with berries): never
  /// batch-cooked or prepped, and nothing cooks off, so a portion weighs
  /// what goes in.
  final bool noCook;
}

/// One step of a template's method. [text] may hold placeholders (see
/// [dishMethod]). With [onlyIf], the step is used only when the dish has
/// that role filled or that option picked (by label); with [unless], only
/// when it hasn't.
@immutable
class MethodStep {
  const new(this.text, {this.onlyIf, this.unless});

  final String text;
  final String? onlyIf;
  final String? unless;
}

/// The placeholders a method step may use besides the ingredient roles.
const Set<String> methodPlaceholders = {
  'prep',
  'done',
  'flavour_base',
  'flavour_finish',
  'fridge_days',
};

@immutable
class DishTemplates {
  const new({required this.templates, required this.flavours});

  final List<DishTemplate> templates;
  final Map<String, FlavourProfile> flavours;

  /// Every basic food the templates use, raw and cooked.
  Set<FoodKey> get foodKeys => {
    for (final f in flavours.values)
      for (final i in f.ingredients) i.key,
    for (final t in templates)
      for (final s in t.slots)
        for (final o in s.options) ...[o.raw, ?o.cooked],
  };
}

/// The template file's format version this app reads.
const int templatesFormat = 1;

/// Parses the dish template file. Throws [FormatException] on anything
/// unexpected (the file ships with the app; its tests must catch mistakes).
DishTemplates parseDishTemplates(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, dynamic> || root['format'] != templatesFormat) {
    throw const FormatException('Unknown dish template format');
  }
  final flavours = <String, FlavourProfile>{};
  for (final f in _list(root['flavours'], 'flavours')) {
    final profile = _flavour(f);
    if (flavours.containsKey(profile.id)) {
      throw FormatException('Duplicate flavour ${profile.id}');
    }
    flavours[profile.id] = profile;
  }
  final shared = <String, List<TemplateOption>>{};
  final options = root['options'];
  if (options is! Map<String, dynamic>) {
    throw const FormatException('No options');
  }
  for (final MapEntry(:key, :value) in options.entries) {
    shared[key] = _options(value, 'options.$key');
  }
  final templates = [
    for (final t in _list(root['templates'], 'templates'))
      _template(t, flavours, shared),
  ];
  final ids = <String>{};
  for (final t in templates) {
    if (!ids.add(t.id)) throw FormatException('Duplicate template ${t.id}');
  }
  return DishTemplates(templates: templates, flavours: flavours);
}

final _id = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _code = RegExp(r'^[0-9]{2}-[0-9]{3,4}$');

List<Object?> _list(Object? v, String where) {
  if (v is! List || v.isEmpty) throw FormatException('$where: empty');
  return v;
}

Map<String, dynamic> _map(Object? v, String where) {
  if (v is! Map<String, dynamic>) {
    throw FormatException('$where: not an object');
  }
  return v;
}

String _string(Map<String, dynamic> json, String field, String where) {
  final v = json[field];
  if (v is! String || v.trim().isEmpty) {
    throw FormatException('$where: missing $field');
  }
  return v;
}

String? _optionalString(
  Map<String, dynamic> json,
  String field,
  String where,
) => json[field] == null ? null : _string(json, field, where);

String _checkedId(Map<String, dynamic> json, String where) {
  final id = _string(json, 'id', where);
  if (!_id.hasMatch(id) || id.length > 80) {
    throw FormatException('$where: bad id "$id"');
  }
  return id;
}

double _grams(Object? v, String where, {double min = 0}) {
  if (v is! num || v < min || v >= 5000) {
    throw FormatException('$where: bad grams');
  }
  return v.toDouble();
}

FoodKey _key(Map<String, dynamic> json, String where) {
  final code = _string(json, 'cofid', where);
  if (!_code.hasMatch(code)) throw FormatException('$where: bad code $code');
  return (code: code, name: _string(json, 'name', where));
}

T _enum<T extends Enum>(List<T> values, Object? name, String where) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('$where: unknown "$name"');
}

FlavourProfile _flavour(Object? json) {
  final m = _map(json, 'flavour');
  final id = _checkedId(m, 'flavour');
  return FlavourProfile(
    id: id,
    name: _string(m, 'name', id),
    cuisine: _enum(Cuisine.values, m['cuisine'], '$id cuisine'),
    base: _optionalString(m, 'base', id),
    finish: _optionalString(m, 'finish', id),
    ingredients: [
      for (final i in _list(m['ingredients'], id))
        () {
          final im = _map(i, id);
          final key = _key(im, id);
          return LibraryIngredient(
            cofidCode: key.code,
            cofidName: key.name,
            rawGrams: _grams(im['grams'], '$id ${key.name}', min: 0.01),
            role: _enum(IngredientRole.values, im['role'], '$id role'),
          );
        }(),
    ],
  );
}

List<TemplateOption> _options(Object? json, String where) => [
  for (final o in _list(json, where))
    () {
      final m = _map(o, where);
      final cooked = m['cooked'];
      return TemplateOption(
        label: _string(m, 'label', where),
        raw: _key(m, where),
        cooked: cooked == null ? null : _key(_map(cooked, where), where),
        noun: _optionalString(m, 'noun', where),
        prep: _optionalString(m, 'prep', where),
        done: _optionalString(m, 'done', where),
      );
    }(),
];

DishTemplate _template(
  Object? json,
  Map<String, FlavourProfile> flavours,
  Map<String, List<TemplateOption>> shared,
) {
  final m = _map(json, 'template');
  final id = _checkedId(m, 'template');
  final version = m['version'];
  final portions = m['portions'];
  final fridgeDays = m['fridge_days'];
  final freezable = m['freezable'];
  final noCook = m['no_cook'] ?? false;
  if (noCook is! bool) throw FormatException('$id: bad no_cook');
  if (version is! int ||
      version < 1 ||
      portions is! int ||
      portions < 1 ||
      portions > 50 ||
      fridgeDays is! int ||
      fridgeDays < 0 ||
      fridgeDays > 7 ||
      freezable is! bool) {
    throw FormatException('$id: values out of range');
  }
  // A cooked dish needs a flavour profile; a no-cook one may go without.
  final flavourList = noCook && (m['flavours'] == null)
      ? const <Object?>[]
      : _list(m['flavours'], '$id flavours');
  final flavourIds = [
    for (final f in flavourList)
      if (f is String && flavours.containsKey(f))
        f
      else
        throw FormatException('$id: unknown flavour $f'),
  ];
  if (noCook && (fridgeDays != 0 || freezable)) {
    throw FormatException('$id: a no-cook dish is made fresh');
  }
  final slots = [
    for (final s in _list(m['slots'], '$id slots'))
      () {
        final sm = _map(s, id);
        final options = sm['options'];
        final grams = _grams(sm['grams'], '$id grams');
        final min = _grams(sm['min'], '$id min');
        final max = _grams(sm['max'], '$id max');
        if (min > grams || grams > max) {
          throw FormatException('$id: grams outside min-max');
        }
        return TemplateSlot(
          role: _enum(IngredientRole.values, sm['role'], '$id role'),
          grams: grams,
          min: min,
          max: max,
          optional: sm['optional'] == true,
          options: options is String
              ? (shared[options] ??
                    (throw FormatException('$id: unknown options $options')))
              : _options(options, id),
        );
      }(),
  ];
  if (!slots.any((s) => s.role == IngredientRole.protein && !s.optional)) {
    throw FormatException('$id: needs a protein');
  }
  final method = _method(m['method'], id, slots);
  return DishTemplate(
    id: id,
    version: version,
    name: _string(m, 'name', id),
    meals: {
      for (final meal in _list(m['meals'], '$id meals'))
        _enum(MealSlot.values, meal, '$id meals'),
    },
    portions: portions,
    fridgeDays: fridgeDays,
    freezable: freezable,
    flavourIds: flavourIds,
    slots: slots,
    noCook: noCook,
    label: m['label'] == null ? null : _string(m, 'label', id),
    method: method,
  );
}

final _placeholder = RegExp(r'\{([a-z_]+)\}');

/// A template's method: optional, but every placeholder and condition in
/// it must make sense for this template.
List<MethodStep> _method(
  Object? json,
  String id,
  List<TemplateSlot> slots,
) {
  if (json == null) return const [];
  final roles = {for (final s in slots) s.role.name};
  final labels = {
    for (final s in slots)
      for (final o in s.options) o.label,
  };
  final steps = <MethodStep>[];
  for (final step in _list(json, '$id method')) {
    final MethodStep parsed;
    if (step is String) {
      parsed = MethodStep(step);
    } else {
      final sm = _map(step, '$id method');
      parsed = MethodStep(
        _string(sm, 'text', '$id method'),
        onlyIf: _optionalString(sm, 'if', '$id method'),
        unless: _optionalString(sm, 'unless', '$id method'),
      );
    }
    for (final match in _placeholder.allMatches(parsed.text)) {
      final name = match.group(1)!;
      if (!roles.contains(name) && !methodPlaceholders.contains(name)) {
        throw FormatException('$id method: unknown {$name}');
      }
    }
    for (final condition in [?parsed.onlyIf, ?parsed.unless]) {
      if (!roles.contains(condition) && !labels.contains(condition)) {
        throw FormatException('$id method: unknown condition $condition');
      }
    }
    steps.add(parsed);
  }
  return steps;
}

// ---------------------------------------------------------------------------
// Making a dish
// ---------------------------------------------------------------------------

/// A dish made from a template: a flavour, an option for each slot, and the
/// full ingredient list for the batch.
@immutable
class GeneratedDish {
  const new({
    required this.template,
    required this.flavour,
    required this.picks,
    required this.name,
  });

  final DishTemplate template;

  /// Null for a no-cook template without flavour profiles.
  final FlavourProfile? flavour;

  /// The option chosen for each slot, by slot index; null for a skipped
  /// optional slot.
  final List<TemplateOption?> picks;
  final String name;

  /// Every ingredient for the whole batch, in raw grams. The same food from
  /// two places (onion in the flavour and a slot) is listed once.
  List<LibraryIngredient> get ingredients {
    final grams = <FoodKey, double>{};
    final roles = <FoodKey, IngredientRole>{};
    for (final (i, slot) in template.slots.indexed) {
      final pick = picks[i];
      if (pick == null) continue;
      grams.update(
        pick.raw,
        (g) => g + slot.grams * template.portions,
        ifAbsent: () => slot.grams * template.portions,
      );
      roles.putIfAbsent(pick.raw, () => slot.role);
    }
    for (final f in flavour?.ingredients ?? const <LibraryIngredient>[]) {
      final batch = f.rawGrams * template.portions;
      grams.update(f.key, (g) => g + batch, ifAbsent: () => batch);
      roles.putIfAbsent(f.key, () => f.role);
    }
    return [
      for (final MapEntry(:key, :value) in grams.entries)
        LibraryIngredient(
          cofidCode: key.code,
          cofidName: key.name,
          rawGrams: (value * 10).round() / 10,
          role: roles[key]!,
        ),
    ];
  }

  /// As a library-style recipe, ready to copy into the user's recipes.
  LibraryRecipe toRecipe() => LibraryRecipe(
    id: template.id,
    version: template.version,
    name: name,
    meals: template.meals,
    cuisine: flavour?.cuisine,
    portions: template.portions,
    fridgeDays: template.fridgeDays,
    freezable: template.freezable,
    method: method,
    ingredients: ingredients,
  );

  /// The template's method for this dish, or null when it has none.
  String? get method => dishMethod(template, flavour, picks);

  /// The batch's expected weight after cooking, from CoFID's raw and cooked
  /// forms: only water changes, so cooked grams = raw grams x raw kcal /
  /// cooked kcal. Ingredients without a cooked form count as unchanged
  /// (vegetables, oil, spices: CoFID's raw and cooked vegetable samples
  /// differ too much to say more). Null if [kcalPer100g] lacks a value.
  double? expectedCookedWeightG(Map<FoodKey, double> kcalPer100g) {
    var total = 0.0;
    for (final (i, slot) in template.slots.indexed) {
      final pick = picks[i];
      if (pick == null) continue;
      final raw = slot.grams * template.portions;
      final cooked = pick.cooked;
      if (cooked == null) {
        total += raw;
        continue;
      }
      final rawKcal = kcalPer100g[pick.raw];
      final cookedKcal = kcalPer100g[cooked];
      if (rawKcal == null || cookedKcal == null || cookedKcal <= 0) {
        return null;
      }
      total += raw * rawKcal / cookedKcal;
    }
    for (final f in flavour?.ingredients ?? const <LibraryIngredient>[]) {
      total += f.rawGrams * template.portions;
    }
    return (total / 10).round() * 10;
  }

  /// What the whole batch weighs as made, for a no-cook dish: nothing cooks
  /// off, so it's the ingredients' total. Null for a cooked dish, which is
  /// weighed after cooking.
  double? get madeWeightG => template.noCook
      ? ingredients.fold<double>(0, (s, i) => s + i.rawGrams)
      : null;
}

/// Why a template couldn't make a dish.
@immutable
class NoDish {
  const new(this.reason);

  final String reason;
}

/// Makes a dish from [template], honouring [prefs]: "never" foods and
/// cuisines are left out, liked ones are 3x as likely, disliked ones a
/// quarter as likely. [random] picks among what's left, so the same seed
/// gives the same dish. [flavourId] and [chosen] (slot index -> option, or
/// null to skip an optional slot) fix choices the user made.
Object generateDish(
  DishTemplate template,
  Map<String, FlavourProfile> flavours,
  FoodPreferences prefs,
  Random random, {
  String? flavourId,
  Map<int, TemplateOption?> chosen = const {},
}) {
  double flavourWeight(FlavourProfile f) {
    if (f.ingredients.any((i) => prefs.isNever(i.key))) return 0;
    return prefs.cuisineWeight(f.cuisine);
  }

  final candidates = [
    for (final id in template.flavourIds)
      if (flavourId == null || id == flavourId) flavours[id]!,
  ];
  // A no-cook template may have no flavour profiles at all.
  final flavour = template.flavourIds.isEmpty
      ? null
      : _weightedPick(candidates, flavourWeight, random);
  if (flavour == null && template.flavourIds.isNotEmpty) {
    return const NoDish(
      'Every flavour for this dish uses a cuisine or ingredient you never '
      'want.',
    );
  }

  final picks = <TemplateOption?>[];
  for (final (i, slot) in template.slots.indexed) {
    if (chosen.containsKey(i)) {
      final choice = chosen[i];
      if (choice == null && !slot.optional) {
        return NoDish('This dish needs a ${slot.role.name}.');
      }
      if (choice != null && prefs.isNever(choice.raw)) {
        return NoDish('You never want ${choice.label}.');
      }
      picks.add(choice);
      continue;
    }
    // Two slots of the same role shouldn't pick the same food.
    final used = {for (final p in picks) ?p?.raw};
    final pick = _weightedPick(
      [
        for (final o in slot.options)
          if (!used.contains(o.raw)) o,
      ],
      (o) => prefs.ingredientWeight(o.raw),
      random,
    );
    if (pick == null && !slot.optional) {
      return NoDish(
        'No ${slot.role.name} is left for this dish after your preferences.',
      );
    }
    picks.add(pick);
  }

  return GeneratedDish(
    template: template,
    flavour: flavour,
    picks: picks,
    name: dishName(template, flavour, picks),
  );
}

/// The template's name with its placeholders filled in.
String dishName(
  DishTemplate template,
  FlavourProfile? flavour,
  List<TemplateOption?> picks,
) {
  String labelFor(IngredientRole role) {
    for (final (i, slot) in template.slots.indexed) {
      if (slot.role == role && picks[i] != null) return picks[i]!.label;
    }
    return '';
  }

  var name = template.name.replaceAll('{flavour}', flavour?.name ?? '');
  for (final role in IngredientRole.values) {
    name = name.replaceAll('{${role.name}}', labelFor(role));
  }
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
}

/// [template]'s method for a dish with [flavour] and [picks], as numbered
/// steps, one per line, or null when the template has no method.
///
/// Placeholders: an ingredient role ({protein}, {veg}...) becomes what was
/// picked for it ("broccoli and red pepper" for two veg slots); {prep} the
/// picks' preparation sentences; {done} how to tell they're cooked (a step
/// using it is left out if nothing picked says); {flavour_base} and
/// {flavour_finish} the
/// flavour's; {fridge_days} how long it keeps. A step is left out when its
/// condition isn't met, when it names a role nothing was picked for, or
/// when nothing is left of it once filled in.
String? dishMethod(
  DishTemplate template,
  FlavourProfile? flavour,
  List<TemplateOption?> picks,
) {
  if (template.method.isEmpty) return null;
  final byRole = <String, List<TemplateOption>>{};
  for (final (i, slot) in template.slots.indexed) {
    final pick = picks[i];
    if (pick == null) continue;
    final list = byRole.putIfAbsent(slot.role.name, () => []);
    if (!list.any((o) => o.raw == pick.raw)) list.add(pick);
  }
  final picked = [for (final list in byRole.values) ...list];
  bool holds(String condition) =>
      byRole.containsKey(condition) ||
      picked.any((o) => o.label == condition);

  final values = <String, String>{
    'prep': {for (final o in picked) ?o.prep}.join(' '),
    'flavour_base': flavour?.base ?? '',
    'flavour_finish': flavour?.finish ?? '',
    'fridge_days': '${template.fridgeDays}',
    if ({for (final o in picked) ?o.done} case final done when done.isNotEmpty)
      'done': done.join(' and '),
    for (final MapEntry(:key, :value) in byRole.entries)
      key: _joinNouns([for (final o in value) o.methodNoun]),
  };
  final steps = <String>[];
  for (final step in template.method) {
    if (step.onlyIf case final c? when !holds(c)) continue;
    if (step.unless case final c? when holds(c)) continue;
    String? missing;
    final text = step.text.replaceAllMapped(_placeholder, (m) {
      final name = m.group(1)!;
      final value = values[name];
      if (value == null) missing = name;
      return value ?? '';
    });
    if (missing != null) continue;
    final tidy = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!RegExp('[A-Za-z]').hasMatch(tidy)) continue;
    steps.add(tidy);
  }
  if (steps.isEmpty) return null;
  return [for (final (n, s) in steps.indexed) '${n + 1}. $s'].join('\n');
}

/// The method for a copy of a template dish saved before templates had
/// methods: its template's current one, for the options and flavour its
/// ingredients show it was made with. Null for any other recipe, or when
/// the template is gone or has no method.
String? templateCopyMethod(
  Recipe recipe,
  Map<String, Food> foods,
  DishTemplates templates,
) {
  if (recipe.origin != RecipeOrigin.template) return null;
  final template = templates.templates
      .where((t) => t.id == recipe.sourceId)
      .firstOrNull;
  if (template == null) return null;
  // Copies' foods keep the CoFID code they came from, in slot order. Each
  // fills one slot: two slots can share a list of options.
  final remaining = [
    for (final i in recipe.ingredients) ?foods[i.foodId]?.referenceCode,
  ];
  final codes = remaining.toSet();
  final picks = <TemplateOption?>[];
  for (final slot in template.slots) {
    TemplateOption? pick;
    for (final (n, code) in remaining.indexed) {
      pick = slot.options.where((o) => o.raw.code == code).firstOrNull;
      if (pick != null) {
        remaining.removeAt(n);
        break;
      }
    }
    picks.add(pick);
  }
  // The flavour named in the dish's name, else the one most of whose
  // ingredients it has.
  final name = recipe.name.toLowerCase();
  FlavourProfile? flavour;
  var best = 0.0;
  for (final id in template.flavourIds) {
    final f = templates.flavours[id];
    if (f == null) continue;
    final score =
        (name.contains(f.name.toLowerCase()) ? 100 : 0) +
        f.ingredients.where((i) => codes.contains(i.cofidCode)).length /
            max(1, f.ingredients.length);
    if (score > best) (best, flavour) = (score, f);
  }
  return dishMethod(template, flavour, picks);
}

/// "a", "a and b", "a, b and c".
String _joinNouns(List<String> nouns) => switch (nouns.length) {
  0 => '',
  1 => nouns.single,
  _ =>
    '${nouns.sublist(0, nouns.length - 1).join(', ')} and ${nouns.last}',
};

T? _weightedPick<T>(List<T> items, double Function(T) weight, Random random) {
  final weights = [for (final i in items) weight(i)];
  final total = weights.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return null;
  var r = random.nextDouble() * total;
  for (final (i, w) in weights.indexed) {
    if (w <= 0) continue;
    r -= w;
    if (r <= 0) return items[i];
  }
  // Floating-point leftovers: the last item that could be picked.
  return items[weights.lastIndexWhere((w) => w > 0)];
}
