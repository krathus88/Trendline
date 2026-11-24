import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/recipe_library.dart';

/// Reads the library file that ships with the app. Overridden in tests.
final recipeLibrarySourceProvider = Provider<Future<String> Function()>(
  (ref) =>
      () => rootBundle.loadString('assets/recipe_library.json'),
);

/// The built-in recipe library.
final recipeLibraryProvider = FutureProvider<List<LibraryRecipe>>(
  (ref) async =>
      parseRecipeLibrary(await ref.watch(recipeLibrarySourceProvider)()),
);

/// The basic foods the library uses, by CoFID code and name, fetched once.
final libraryFoodsProvider =
    FutureProvider<Map<({String code, String name}), FoodDraft>>((ref) async {
      if (ref.watch(currentUserIdProvider) == null) return const {};
      final library = await ref.watch(recipeLibraryProvider.future);
      return await ref.watch(referenceFoodRepositoryProvider).fetchByKeys({
        for (final r in library)
          for (final i in r.ingredients) i.key,
      });
    });
