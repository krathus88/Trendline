import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';

/// The IDs of the recipes the user has starred, cached in memory.
final recipeFavouritesProvider =
    AsyncNotifierProvider<RecipeFavouritesNotifier, Set<String>>(
      RecipeFavouritesNotifier.new,
    );

class RecipeFavouritesNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const {};
    return await ref.watch(recipeFavouritesRepositoryProvider).fetchAll();
  }

  /// Stars [recipeId], or takes its star off. Shows the change straight
  /// away; reverts if saving fails.
  Future<void> toggle(String recipeId) async {
    final before = state.value ?? const <String>{};
    final starring = !before.contains(recipeId);
    state = AsyncData(
      starring ? {...before, recipeId} : ({...before}..remove(recipeId)),
    );
    try {
      final repository = ref.read(recipeFavouritesRepositoryProvider);
      if (starring) {
        await repository.add(recipeId);
      } else {
        await repository.remove(recipeId);
      }
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}
