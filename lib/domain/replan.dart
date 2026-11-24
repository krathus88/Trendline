import 'dart:math';

import 'package:meta/meta.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';

/// How far the re-planned day may land from its calories before saying so:
/// 5% of the target, or 100 kcal if that's more.
double replanTolerance(double targetKcal) => max(100, targetKcal * 0.05);

/// The rest of a day, re-planned.
@immutable
class DayReplan {
  const new({required this.items, required this.dayKcal, this.note});

  /// The remaining items with their new amounts, in the order given.
  final List<PlannedItem> items;

  /// What the day adds up to with them: eaten + still to eat.
  final double dayKcal;

  /// Said when the day can't land near its target, never silently.
  final String? note;

  /// Items whose amount changed, from [before].
  List<PlannedItem> changedFrom(List<PlannedItem> before) => [
    for (final (n, i) in items.indexed)
      if (i.amount != before[n].amount) i,
  ];
}

/// A day's planned items not yet eaten: each logged entry in a meal uses
/// up one planned item of the same food or recipe in that meal.
List<PlannedItem> remainingItems(
  List<PlannedItem> planned,
  List<FoodLogEntry> eaten,
) {
  final unmatched = List.of(eaten);
  final remaining = <PlannedItem>[];
  for (final i in planned) {
    final n = unmatched.indexWhere(
      (e) =>
          e.slot == i.slot &&
          (i.key == 'food:${e.foodId}' || i.key == 'recipe:${e.recipeId}'),
    );
    if (n >= 0) {
      unmatched.removeAt(n);
    } else {
      remaining.add(i);
    }
  }
  return remaining;
}

/// Refits [remaining] (the day's planned items not yet eaten) so that
/// [eaten] plus them lands on [targetKcal], within each item's range.
/// Locked items and any [fixed] (for example portions already cooked and
/// boxed) keep their amounts and the rest work around them.
DayReplan replanRestOfDay({
  required List<PlannedItem> remaining,
  required Nutrition eaten,
  required double targetKcal,
  bool Function(PlannedItem item)? fixed,
}) {
  final left = targetKcal - eaten.kcal;
  final items = fitToKcal(remaining, max(0, left), fixed: fixed);
  final planned = items.fold<double>(0, (s, i) => s + i.nutrition.kcal);
  final day = eaten.kcal + planned;
  final off = day - targetKcal;
  String? note;
  if (off.abs() > replanTolerance(targetKcal)) {
    final n = off.abs().round();
    if (remaining.isEmpty) {
      note = off > 0
          ? 'Nothing’s left to plan today, and you’re about $n kcal over. '
                'That’s fine now and then: the weekly trend is what counts.'
          : 'Nothing’s left to plan today, about $n kcal short of your '
                'target.';
    } else {
      note = off > 0
          ? 'Even the smallest portions leave today about $n kcal over. '
                'That’s fine now and then: the weekly trend is what counts.'
          : 'Even the largest portions leave today about $n kcal short. '
                'Add something to make it up.';
    }
  }
  return DayReplan(items: items, dayKcal: day, note: note);
}
