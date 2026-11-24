import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/prep.dart';
import 'package:trendline/domain/recipe.dart';

/// Raised when a portion is eaten before its batch has been weighed, so its
/// cooked grams aren't known.
class PrepNotWeighed implements Exception {
  const new();

  String get message =>
      'Weigh the batch after cooking first: portions are logged by their '
      'share of its cooked weight.';
}

/// Prep sessions from the last few months (long enough to cover frozen
/// portions), cached in memory.
final prepProvider = AsyncNotifierProvider<PrepNotifier, List<PrepSession>>(
  PrepNotifier.new,
);

class PrepNotifier extends AsyncNotifier<List<PrepSession>> {
  @override
  Future<List<PrepSession>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    final from = addDays(dayOf(DateTime.now()), -(freezerKeepsDays + 14));
    return await ref.watch(prepRepositoryProvider).fetchFrom(from);
  }

  /// Marks [session] cooked, with the batch's measured weight.
  Future<void> markCooked(PrepSession session, double cookedWeightG) async {
    final saved = await ref
        .read(prepRepositoryProvider)
        .markCooked(session.id, cookedWeightG);
    _replaceSession(saved);
  }

  /// Logs [portion] as eaten on [day] at [slot], by its share of the
  /// batch's cooked weight.
  Future<void> eat({
    required PrepSession session,
    required PrepPortion portion,
    required Recipe recipe,
    required Map<String, Food> foods,
    required DateTime day,
    required MealSlot slot,
  }) async {
    final per100g = sessionPer100gCooked(session, recipe, foods);
    final grams = session.gramsOf(portion);
    if (per100g == null || grams == null) throw const PrepNotWeighed();
    final log = ref.read(foodLogProvider(day).notifier);
    final entry = await log.addRecipe(
      slot: slot,
      recipe: recipe,
      per100gCooked: per100g,
      grams: (grams * 10).round() / 10,
    );
    try {
      await _savePortion(
        portion.copyWith(
          status: PortionStatus.eaten,
          foodLogId: () => entry.id,
        ),
      );
    } on Object {
      // Don't leave a logged meal the portion doesn't know about: logging it
      // again would count it twice.
      await log.delete(entry.id);
      rethrow;
    }
  }

  /// Moves [portion] to the freezer as a leftover for no meal in
  /// particular, best eaten within three months.
  Future<void> freeze(PrepPortion portion) => _savePortion(
    portion.copyWith(
      storage: PrepStorage.freezer,
      status: PortionStatus.leftover,
      day: () => null,
      slot: () => null,
      useBy: freezerUseBy(dayOf(DateTime.now())),
    ),
  );

  Future<void> discard(PrepPortion portion) =>
      _savePortion(portion.copyWith(status: PortionStatus.discarded));

  Future<void> _savePortion(PrepPortion portion) async {
    await ref.read(prepRepositoryProvider).updatePortion(portion);
    final sessions = state.value ?? const <PrepSession>[];
    for (final s in sessions) {
      if (s.id != portion.sessionId) continue;
      _replaceSession(
        s.copyWith(
          portions: [
            for (final p in s.portions)
              if (p.id == portion.id) portion else p,
          ],
        ),
      );
    }
  }

  void _replaceSession(PrepSession session) {
    final sessions = state.value ?? const <PrepSession>[];
    state = AsyncData([
      for (final s in sessions)
        if (s.id == session.id) session else s,
    ]);
  }
}
