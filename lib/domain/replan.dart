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
/// [eaten] plus them lands on [target]'s calories, within each item's
/// range, then nudges them towards its protein, fat, carbs and fibre (see
/// [fitRestToTargets]). Locked items and any [fixed] (for example portions
/// already cooked and boxed) keep their amounts and the rest work around
/// them.
DayReplan replanRestOfDay({
  required List<PlannedItem> remaining,
  required Nutrition eaten,
  required PlanTargets target,
  bool Function(PlannedItem item)? fixed,
}) {
  final targetKcal = target.kcal;
  final items = fitRestToTargets(
    remaining,
    eaten: eaten,
    target: target,
    fixed: fixed,
  );
  final rest = Nutrition.sum(items.map((i) => i.nutrition));
  final day = eaten.kcal + rest.kcal;
  final off = day - targetKcal;
  final notes = <String>[];
  if (off.abs() > replanTolerance(targetKcal)) {
    final n = off.abs().round();
    if (remaining.isEmpty) {
      notes.add(
        off > 0
            ? 'Nothing’s left to plan today, and you’re about $n kcal over. '
                  'That’s fine now and then: the weekly trend is what counts.'
            : 'Nothing’s left to plan today, about $n kcal short of your '
                  'target.',
      );
    } else {
      notes.add(
        off > 0
            ? 'Even the smallest portions leave today about $n kcal over. '
                  'That’s fine now and then: the weekly trend is what counts.'
            : 'Even the largest portions leave today about $n kcal short. '
                  'Add something to make it up.',
      );
    }
  }
  final proteinShort = target.proteinG - eaten.proteinG - rest.proteinG;
  if (remaining.isNotEmpty &&
      proteinShort > max(proteinNoteGrams, target.proteinG * 0.1)) {
    notes.add(
      'Protein ends up about ${proteinShort.round()} g short today. '
      'Something high in protein would help.',
    );
  }
  return DayReplan(
    items: items,
    dayKcal: day,
    note: notes.isEmpty ? null : notes.join(' '),
  );
}

/// Protein shortfalls smaller than this (or 10% of the target, if more)
/// aren't mentioned after re-planning.
const double proteinNoteGrams = 10;

/// Fits [items] (the rest of a day, after [eaten]) to [target].
///
/// First the calories, as the week planner does ([fitToKcal]). Then each
/// flexible item is moved a step at a time (a quarter portion or 25 g,
/// then 0.05 portions or 5 g), keeping a move only if it brings the whole
/// day closer to its targets as the planner scores them
/// ([dayNutritionScore]: more protein when it's short, fat and carbs
/// nearer their targets) and the day's calories stay within 25 kcal of the
/// target, or no further off than the calorie fit left them. So protein is
/// traded for, but never at the cost of the calories. Locked items, items
/// with no range and any [fixed] keep their amounts.
List<PlannedItem> fitRestToTargets(
  List<PlannedItem> items, {
  required Nutrition eaten,
  required PlanTargets target,
  bool Function(PlannedItem item)? fixed,
}) {
  var out = fitToKcal(items, max(0, target.kcal - eaten.kcal), fixed: fixed);
  bool flexible(PlannedItem i) =>
      !i.locked &&
      !(fixed?.call(i) ?? false) &&
      i.minAmount != null &&
      i.maxAmount != null &&
      i.minAmount! < i.maxAmount!;
  if (!out.any(flexible)) return out;

  Nutrition dayOf(List<PlannedItem> rest) =>
      Nutrition.sum([eaten, for (final i in rest) i.nutrition]);
  final band = max(25, (dayOf(out).kcal - target.kcal).abs());
  var score = dayNutritionScore(dayOf(out), target);

  for (final fine in [false, true]) {
    // Each pass ends when no single step helps; the cap is only a guard.
    for (var round = 0; round < 200; round++) {
      List<PlannedItem>? best;
      var bestScore = score;
      for (final (n, i) in out.indexed) {
        if (!flexible(i)) continue;
        final step = i.isPortions ? (fine ? 0.05 : 0.25) : (fine ? 5.0 : 25.0);
        for (final sign in const [1, -1]) {
          final amount = (i.amount + sign * step).clamp(
            i.minAmount!,
            i.maxAmount!,
          );
          if (amount == i.amount) continue;
          final next = [...out]..[n] = i.copyWith(amount: amount);
          final day = dayOf(next);
          if ((day.kcal - target.kcal).abs() > band) continue;
          final s = dayNutritionScore(day, target);
          if (s < bestScore - 1e-9) {
            best = next;
            bestScore = s;
          }
        }
      }
      if (best == null) break;
      out = best;
      score = bestScore;
    }
  }
  return out;
}
