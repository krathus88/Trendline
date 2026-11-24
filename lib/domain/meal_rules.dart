import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';

enum RuleFrequency {
  /// Every day (in [MealRule.slot], or in any meal).
  daily,

  /// At least [MealRule.timesPerWeek] times a week.
  minPerWeek,

  /// At most [MealRule.timesPerWeek] times a week.
  maxPerWeek,
}

/// A mandatory or recurring item the planner must respect, for example
/// "cappuccino, every day, at breakfast, 250 g" or "salmon at least twice a
/// week".
@immutable
class MealRule {
  const new({
    required this.id,
    required this.frequency,
    required this.amountMin,
    required this.amountMax,
    this.foodId,
    this.recipeId,
    this.slot,
    this.timesPerWeek,
  });

  /// Grams of a food at a time.
  static const double maxGrams = 4999;

  /// Portions of a recipe at a time.
  static const double maxPortions = 10;

  /// Empty for a rule not saved yet.
  final String id;

  /// Exactly one of [foodId] and [recipeId] is set.
  final String? foodId;
  final String? recipeId;

  /// Null: any meal.
  final MealSlot? slot;
  final RuleFrequency frequency;

  /// Times a week, for the weekly frequencies.
  final int? timesPerWeek;

  /// Grams of a food, or portions of a recipe, each time. Equal for a fixed
  /// amount.
  final double amountMin;
  final double amountMax;

  bool get isRecipe => recipeId != null;

  /// The food or recipe it's about.
  String get target => (foodId ?? recipeId)!;

  /// The fewest times a week it can happen while keeping this rule.
  int get weeklyMin => switch (frequency) {
    RuleFrequency.daily => 7,
    RuleFrequency.minPerWeek => timesPerWeek!,
    RuleFrequency.maxPerWeek => 0,
  };

  /// The most times a week, or null for no limit.
  int? get weeklyMax => switch (frequency) {
    RuleFrequency.maxPerWeek => timesPerWeek,
    _ => null,
  };
}

/// The most times something can be eaten in a week: once per meal.
int weeklyCapacity(MealSlot? slot) => slot == null ? 28 : 7;

/// A problem with [rule], or null if it's fine. Matches the database
/// checks.
String? validateRule(MealRule rule) {
  if ((rule.foodId == null) == (rule.recipeId == null)) {
    return 'Choose a food or a recipe.';
  }
  final most = rule.isRecipe ? MealRule.maxPortions : MealRule.maxGrams;
  for (final v in [rule.amountMin, rule.amountMax]) {
    if (v.isNaN || v <= 0 || v > most) {
      return rule.isRecipe
          ? 'Portions must be more than 0 and at most 10.'
          : 'Amounts must be more than 0 g and under 5000 g.';
    }
  }
  if (rule.amountMin > rule.amountMax) {
    return 'The smallest amount can’t be more than the largest.';
  }
  if (rule.frequency == RuleFrequency.daily) {
    if (rule.timesPerWeek != null) return 'Every day needs no count.';
  } else {
    final times = rule.timesPerWeek;
    final cap = weeklyCapacity(rule.slot);
    if (times == null || times < 1 || times > cap) {
      return 'Times a week must be between 1 and $cap.';
    }
  }
  return null;
}

/// Rules that can't all be kept together, as messages to show. [nameOf]
/// gives a rule's food or recipe name.
///
/// Checks, per food or recipe: an "at least" (or daily) count above an "at
/// most" count, and fixed daily amounts in the same meal that disagree.
List<String> ruleConflicts(
  List<MealRule> rules,
  String Function(MealRule) nameOf,
) {
  final problems = <String>[];
  final byTarget = <String, List<MealRule>>{};
  for (final r in rules) {
    (byTarget[r.target] ??= []).add(r);
  }
  for (final group in byTarget.values) {
    final name = nameOf(group.first);
    final atLeast = group
        .map((r) => r.weeklyMin)
        .reduce((a, b) => a > b ? a : b);
    final limits = [for (final r in group) ?r.weeklyMax];
    if (limits.isNotEmpty) {
      final atMost = limits.reduce((a, b) => a < b ? a : b);
      if (atLeast > atMost) {
        problems.add(
          '$name: at least $atLeast but at most $atMost times a week.',
        );
      }
    }
    final daily = [
      for (final r in group)
        if (r.frequency == RuleFrequency.daily) r,
    ];
    for (final (i, a) in daily.indexed) {
      for (final b in daily.skip(i + 1)) {
        final sameMeal = a.slot == b.slot;
        final overlap =
            a.amountMin <= b.amountMax && b.amountMin <= a.amountMax;
        if (sameMeal && !overlap) {
          problems.add('$name: two daily amounts that don’t overlap.');
        }
      }
    }
  }
  return problems;
}
