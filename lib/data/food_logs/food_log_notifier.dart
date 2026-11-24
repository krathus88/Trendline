import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncNotifierProviderFamily;
import 'package:trendline/data/food_logs/food_log_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

/// One local calendar day's food log, cached in memory per day. Pass a day
/// from `dayOf(...)` so equal days share one cache entry.
final AsyncNotifierProviderFamily<FoodLogNotifier, List<FoodLogEntry>, DateTime>
foodLogProvider =
    AsyncNotifierProvider.family<FoodLogNotifier, List<FoodLogEntry>, DateTime>(
      FoodLogNotifier.new,
    );

class FoodLogNotifier extends AsyncNotifier<List<FoodLogEntry>> {
  new(this.day);

  final DateTime day;

  @override
  Future<List<FoodLogEntry>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    return await ref.watch(foodLogRepositoryProvider).fetchDay(day);
  }

  Future<void> add({
    required MealSlot slot,
    required Food food,
    required double grams,
  }) async {
    final entry = await ref
        .read(foodLogRepositoryProvider)
        .add(day: day, slot: slot, food: food, grams: grams);
    state = AsyncData([...state.value ?? const <FoodLogEntry>[], entry]);
  }

  /// Logs [grams] (cooked) of [recipe], whose nutrition per 100 g cooked is
  /// [per100gCooked], and returns the entry.
  Future<FoodLogEntry> addRecipe({
    required MealSlot slot,
    required Recipe recipe,
    required Nutrition per100gCooked,
    required double grams,
  }) async {
    final entry = await ref
        .read(foodLogRepositoryProvider)
        .addRecipe(
          day: day,
          slot: slot,
          recipe: recipe,
          per100gCooked: per100gCooked,
          grams: grams,
        );
    state = AsyncData([...state.value ?? const <FoodLogEntry>[], entry]);
    return entry;
  }

  /// Shows the new portion straight away; reverts if saving fails.
  Future<void> updateGrams(FoodLogEntry entry, double grams) async {
    final before = state.value ?? const <FoodLogEntry>[];
    final preview = FoodLogEntry(
      id: entry.id,
      eatenOn: entry.eatenOn,
      eatenAt: entry.eatenAt,
      slot: entry.slot,
      foodId: entry.foodId,
      recipeId: entry.recipeId,
      foodName: entry.foodName,
      foodBrand: entry.foodBrand,
      grams: grams,
      nutrition: rescale(entry.nutrition, from: entry.grams, to: grams),
    );
    state = AsyncData(_replace(before, preview));
    try {
      final saved = await ref
          .read(foodLogRepositoryProvider)
          .updateGrams(entry, grams);
      state = AsyncData(_replace(state.value ?? before, saved));
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Removes the entry straight away; puts it back if the delete fails.
  Future<void> delete(String id) async {
    final before = state.value ?? const <FoodLogEntry>[];
    state = AsyncData([
      for (final e in before)
        if (e.id != id) e,
    ]);
    try {
      await ref.read(foodLogRepositoryProvider).delete(id);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }

  static List<FoodLogEntry> _replace(
    List<FoodLogEntry> list,
    FoodLogEntry updated,
  ) => [
    for (final e in list)
      if (e.id == updated.id) updated else e,
  ];
}
