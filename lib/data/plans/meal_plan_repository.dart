import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/households/household_repository.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/planner.dart';

/// One saved plan item: a food (grams) or a recipe (portions) of the
/// user's own.
@immutable
class SavedPlanItem {
  const new({
    required this.day,
    required this.slot,
    required this.amount,
    this.foodId,
    this.recipeId,
    this.amountMin,
    this.amountMax,
    this.locked = false,
    this.batch,
    this.mealRuleId,
    this.id,
    this.eaterId,
    this.estimated = false,
  });

  /// Null until saved.
  final String? id;

  /// Who eats it. The user, in their own plan; any member, in a household
  /// week. Null when not yet saved in the user's own plan.
  final String? eaterId;
  final DateTime day;
  final MealSlot slot;
  final String? foodId;
  final String? recipeId;
  final double amount;
  final double? amountMin;
  final double? amountMax;
  final bool locked;
  final int? batch;
  final String? mealRuleId;

  /// In a household week: an amount someone else's planning set, not yet
  /// fitted by its eater to their own day.
  final bool estimated;
}

/// A saved week's plan.
@immutable
class SavedPlan {
  const new({
    required this.weekStart,
    required this.targets,
    required this.notes,
    required this.items,
  });

  final DateTime weekStart;

  /// Each day's targets, Monday first (seven).
  final List<PlanTargets> targets;
  final List<String> notes;
  final List<SavedPlanItem> items;
}

/// A household's shared dishes for a week: a serving per eater, each with
/// that eater's amount and the range they may fit it within.
@immutable
class HouseholdWeek {
  const new({
    required this.weekStart,
    required this.items,
    this.notes = const [],
  });

  final DateTime weekStart;
  final List<SavedPlanItem> items;
  final List<String> notes;

  /// [userId]'s servings.
  List<SavedPlanItem> itemsFor(String userId) => [
    for (final i in items)
      if (i.eaterId == userId) i,
  ];
}

abstract interface class MealPlanRepository {
  /// The user's own plan for the week starting [weekStart] (a Monday), or
  /// null.
  Future<SavedPlan?> fetchWeek(DateTime weekStart);

  /// The household's week starting [weekStart], or null (none saved, or
  /// not in a household).
  Future<HouseholdWeek?> fetchHouseholdWeek(DateTime weekStart);

  /// Saves the household's week, replacing any already saved, and lays out
  /// its joint prep. Throws [HouseholdError] outside a household.
  Future<void> saveHouseholdWeek(HouseholdWeek week);

  /// Saves the week's plan, replacing any already saved for that week.
  Future<void> save(SavedPlan plan);

  /// Gives saved items new amounts (by item ID), each within its range:
  /// the user's own plan's, or their servings in the household week.
  /// Portions of batches not yet cooked follow; a cooked batch's portions
  /// can't change.
  Future<void> updateAmounts(Map<String, double> amounts);
}

class SupabaseMealPlanRepository implements MealPlanRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'week_start, kcal_target, protein_target_g, carbs_target_g, '
      'fat_target_g, fibre_target_g, day_targets, notes, '
      'plan_items(id, day, slot, food_id, recipe_id, amount, amount_min, '
      'amount_max, locked, batch, meal_rule_id)';

  // RLS shows the household's weeks too, so each query says which.
  @override
  Future<SavedPlan?> fetchWeek(DateTime weekStart) async {
    final row = await _db
        .from('meal_plans')
        .select(_columns)
        .eq('week_start', writeDate(weekStart))
        .isFilter('household_id', null)
        .maybeSingle();
    return row == null ? null : savedPlanFromRow(row);
  }

  @override
  Future<HouseholdWeek?> fetchHouseholdWeek(DateTime weekStart) async {
    final row = await _db
        .from('meal_plans')
        .select(
          'week_start, notes, plan_items(id, eater_id, day, slot, recipe_id, '
          'amount, amount_min, amount_max, batch, estimated)',
        )
        .eq('week_start', writeDate(weekStart))
        .not('household_id', 'is', null)
        .maybeSingle();
    return row == null ? null : householdWeekFromRow(row);
  }

  @override
  Future<void> saveHouseholdWeek(HouseholdWeek week) async {
    try {
      await _db.rpc<String>(
        'save_household_plan',
        params: saveHouseholdWeekParams(week),
      );
    } on PostgrestException catch (e) {
      if (e.code == 'TLH04') throw HouseholdError.notMember;
      rethrow;
    }
  }

  @override
  Future<void> save(SavedPlan plan) async {
    // One database function replaces the week's plan and its items in a
    // single transaction.
    await _db.rpc<String>('save_meal_plan', params: savePlanParams(plan));
  }

  @override
  Future<void> updateAmounts(Map<String, double> amounts) async {
    // One database function, so the items and their prep change together.
    await _db.rpc<void>(
      'replan_plan_items',
      params: {
        'amounts': [
          for (final MapEntry(key: id, value: amount) in amounts.entries)
            {'id': id, 'amount': (amount * 100).round() / 100},
        ],
      },
    );
  }
}

SavedPlan savedPlanFromRow(Map<String, dynamic> row) => SavedPlan(
  weekStart: readDate(row['week_start']),
  targets: _dayTargetsFromRow(row),
  notes: [
    for (final n in (row['notes'] as List? ?? const []))
      if (n is String) n,
  ],
  items: [
    for (final i in (row['plan_items'] as List? ?? const []))
      ?_itemFromRow(i as Map<String, dynamic>),
  ],
);

/// Each day's saved targets; a plan saved before day targets were kept
/// used the plan's own for every day.
List<PlanTargets> _dayTargetsFromRow(Map<String, dynamic> row) {
  final week = PlanTargets(
    kcal: readDouble(row['kcal_target']),
    proteinG: readDouble(row['protein_target_g']),
    carbsG: readDouble(row['carbs_target_g']),
    fatG: readDouble(row['fat_target_g']),
    fibreG: readDouble(row['fibre_target_g']),
  );
  final days = row['day_targets'];
  if (days is! List || days.length != 7) return List.filled(7, week);
  return [
    for (final d in days)
      if (d is Map<String, dynamic>)
        PlanTargets(
          kcal: readDoubleOrNull(d['kcal']) ?? week.kcal,
          proteinG: readDoubleOrNull(d['protein_g']) ?? week.proteinG,
          carbsG: readDoubleOrNull(d['carbs_g']) ?? week.carbsG,
          fatG: readDoubleOrNull(d['fat_g']) ?? week.fatG,
          fibreG: readDoubleOrNull(d['fibre_g']) ?? week.fibreG,
        )
      else
        week,
  ];
}

HouseholdWeek householdWeekFromRow(Map<String, dynamic> row) => HouseholdWeek(
  weekStart: readDate(row['week_start']),
  notes: [
    for (final n in (row['notes'] as List? ?? const []))
      if (n is String) n,
  ],
  items:
      [
        for (final i in (row['plan_items'] as List? ?? const []))
          ?_itemFromRow(i as Map<String, dynamic>),
      ]..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        return byDay != 0 ? byDay : a.slot.index.compareTo(b.slot.index);
      }),
);

Map<String, dynamic> saveHouseholdWeekParams(HouseholdWeek week) {
  double r2(double v) => (v * 100).round() / 100;
  return {
    'week_start': writeDate(week.weekStart),
    'notes': week.notes,
    'items': [
      for (final i in week.items)
        {
          'day': writeDate(i.day),
          'slot': i.slot.name,
          'recipe_id': i.recipeId,
          'eater_id': i.eaterId,
          'amount': r2(i.amount),
          'amount_min': i.amountMin == null ? null : r2(i.amountMin!),
          'amount_max': i.amountMax == null ? null : r2(i.amountMax!),
          'batch': i.batch,
        },
    ],
  };
}

SavedPlanItem? _itemFromRow(Map<String, dynamic> row) {
  final slot = MealSlot.values.asNameMap()[row['slot']];
  final amount = readDoubleOrNull(row['amount']);
  if (slot == null || amount == null) return null;
  return SavedPlanItem(
    id: row['id'] as String?,
    day: readDate(row['day']),
    slot: slot,
    foodId: row['food_id'] as String?,
    recipeId: row['recipe_id'] as String?,
    amount: amount,
    amountMin: readDoubleOrNull(row['amount_min']),
    amountMax: readDoubleOrNull(row['amount_max']),
    locked: row['locked'] as bool? ?? false,
    batch: row['batch'] as int?,
    mealRuleId: row['meal_rule_id'] as String?,
    eaterId: row['eater_id'] as String?,
    estimated: row['estimated'] as bool? ?? false,
  );
}

Map<String, dynamic> savePlanParams(SavedPlan plan) {
  double r1(double v) => (v * 10).round() / 10;
  double r2(double v) => (v * 100).round() / 100;
  // The plan's own columns hold Monday's (today's, in the current week).
  final first = plan.targets.first;
  return {
    'week_start': writeDate(plan.weekStart),
    'kcal_target': r1(first.kcal),
    'protein_target_g': r1(first.proteinG),
    'carbs_target_g': r1(first.carbsG),
    'fat_target_g': r1(first.fatG),
    'fibre_target_g': r1(first.fibreG),
    'day_targets': [
      for (final t in plan.targets)
        {
          'kcal': r1(t.kcal),
          'protein_g': r1(t.proteinG),
          'carbs_g': r1(t.carbsG),
          'fat_g': r1(t.fatG),
          'fibre_g': r1(t.fibreG),
        },
    ],
    'notes': plan.notes,
    'items': [
      for (final i in plan.items)
        {
          'day': writeDate(i.day),
          'slot': i.slot.name,
          'food_id': i.foodId,
          'recipe_id': i.recipeId,
          'amount': r2(i.amount),
          'amount_min': i.amountMin == null ? null : r2(i.amountMin!),
          'amount_max': i.amountMax == null ? null : r2(i.amountMax!),
          'locked': i.locked,
          'batch': i.batch,
          'meal_rule_id': i.mealRuleId,
        },
    ],
  };
}
