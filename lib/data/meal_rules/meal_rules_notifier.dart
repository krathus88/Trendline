import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/meal_rules.dart';

/// The user's meal rules, oldest first, cached in memory.
final mealRulesProvider =
    AsyncNotifierProvider<MealRulesNotifier, List<MealRule>>(
      MealRulesNotifier.new,
    );

class MealRulesNotifier extends AsyncNotifier<List<MealRule>> {
  @override
  Future<List<MealRule>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    return await ref.watch(mealRuleRepositoryProvider).fetchAll();
  }

  /// Creates or updates [rule] (an empty ID creates it).
  Future<MealRule> save(MealRule rule) async {
    final saved = await ref.read(mealRuleRepositoryProvider).save(rule);
    final current = state.value ?? const <MealRule>[];
    final exists = current.any((r) => r.id == saved.id);
    state = AsyncData([
      for (final r in current)
        if (r.id == saved.id) saved else r,
      if (!exists) saved,
    ]);
    return saved;
  }

  /// Removes the rule straight away; puts it back if the delete fails.
  Future<void> delete(String id) async {
    final before = state.value ?? const <MealRule>[];
    state = AsyncData([
      for (final r in before)
        if (r.id != id) r,
    ]);
    try {
      await ref.read(mealRuleRepositoryProvider).delete(id);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}
