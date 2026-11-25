import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/households/household_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/domain/recipe.dart';

/// The user's household, or null when they aren't in one.
final householdProvider = AsyncNotifierProvider<HouseholdNotifier, Household?>(
  HouseholdNotifier.new,
);

class HouseholdNotifier extends AsyncNotifier<Household?> {
  @override
  Future<Household?> build() async {
    if (ref.watch(currentUserIdProvider) == null) return null;
    return await ref.watch(householdRepositoryProvider).fetch();
  }

  Future<void> create({
    required String name,
    required String displayName,
  }) async {
    final repo = ref.read(householdRepositoryProvider);
    await repo.create(name: name, displayName: displayName);
    state = AsyncData(await repo.fetch());
  }

  /// Joins with an invite code as typed. Throws [HouseholdError] when the
  /// code can't work.
  Future<void> join({required String code, required String displayName}) async {
    final normalised = normaliseInviteCode(code);
    if (normalised == null) throw HouseholdError.badInvite;
    final repo = ref.read(householdRepositoryProvider);
    await repo.join(code: normalised, displayName: displayName);
    state = AsyncData(await repo.fetch());
  }

  /// A new invite code (owner only).
  Future<HouseholdInvite> invite() async {
    final household = state.value;
    if (household == null) throw StateError('Not in a household');
    final repo = ref.read(householdRepositoryProvider);
    final invite = await repo.createInvite(household.id);
    state = AsyncData(await repo.fetch());
    return invite;
  }

  Future<void> withdrawInvite(String code) async {
    final repo = ref.read(householdRepositoryProvider);
    await repo.withdrawInvite(code);
    state = AsyncData(await repo.fetch());
  }

  /// Leaves the household. Access to what's shared ends at once; what the
  /// user shared stays with the others.
  Future<void> leave() async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    await ref.read(householdRepositoryProvider).removeMember(me);
    state = const AsyncData(null);
  }

  /// Removes another member (owner only).
  Future<void> remove(String userId) async {
    final repo = ref.read(householdRepositoryProvider);
    await repo.removeMember(userId);
    state = AsyncData(await repo.fetch());
  }
}

/// The household's ID, or null outside one (or while it loads).
final householdIdProvider = Provider<String?>(
  (ref) => ref.watch(householdProvider).value?.id,
);

/// The foods in the household's shared recipes, for their names and
/// nutrition.
final sharedFoodsProvider = FutureProvider<List<Food>>((ref) async {
  if (ref.watch(householdIdProvider) == null) return const [];
  return await ref.watch(foodRepositoryProvider).fetchShared();
});

/// Recipes shared with the household, by name.
final sharedRecipesProvider =
    AsyncNotifierProvider<SharedRecipesNotifier, List<Recipe>>(
      SharedRecipesNotifier.new,
    );

class SharedRecipesNotifier extends AsyncNotifier<List<Recipe>> {
  @override
  Future<List<Recipe>> build() async {
    if (ref.watch(householdIdProvider) == null) return const [];
    return await ref.watch(recipeRepositoryProvider).fetchShared();
  }

  /// Saves a change to a shared recipe. Foods added from the user's own are
  /// copied into the household by the database.
  Future<Recipe> save(Recipe recipe) async {
    final saved = await ref.read(recipeRepositoryProvider).save(recipe);
    _put(saved);
    ref.invalidate(sharedFoodsProvider);
    return saved;
  }

  /// Shares a copy of one of the user's own recipes with the household. The
  /// user's recipe stays as it is.
  Future<Recipe> share(Recipe mine) async {
    final household = ref.read(householdIdProvider);
    if (household == null) throw StateError('Not in a household');
    return await save(mine.copyFor(household));
  }

  /// Copies a shared recipe into the user's own recipes (with their own
  /// copies of its foods), so it stays theirs if they leave.
  Future<Recipe> copyToMine(Recipe shared) async {
    final saved = await ref
        .read(recipesProvider.notifier)
        .save(shared.copyFor(null));
    ref.invalidate(foodsProvider);
    return saved;
  }

  /// Removes it for everyone in the household; puts it back if that fails.
  Future<void> delete(String id) async {
    final before = state.value ?? const <Recipe>[];
    state = AsyncData([
      for (final r in before)
        if (r.id != id) r,
    ]);
    try {
      await ref.read(recipeRepositoryProvider).delete(id);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }

  void _put(Recipe saved) {
    final list = [
      for (final r in state.value ?? const <Recipe>[])
        if (r.id != saved.id) r,
      saved,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = AsyncData(list);
  }
}
