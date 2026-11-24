import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/dish_templates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';

/// Reads the dish template file that ships with the app. Overridden in
/// tests.
final dishTemplatesSourceProvider = Provider<Future<String> Function()>(
  (ref) =>
      () => rootBundle.loadString('assets/dish_templates.json'),
);

/// The built-in dish templates and flavour profiles.
final dishTemplatesProvider = FutureProvider<DishTemplates>(
  (ref) async =>
      parseDishTemplates(await ref.watch(dishTemplatesSourceProvider)()),
);

/// The basic foods the templates use (raw and cooked forms), fetched once.
final templateFoodsProvider = FutureProvider<Map<FoodKey, FoodDraft>>((
  ref,
) async {
  if (ref.watch(currentUserIdProvider) == null) return const {};
  final templates = await ref.watch(dishTemplatesProvider.future);
  return await ref
      .watch(referenceFoodRepositoryProvider)
      .fetchByKeys(templates.foodKeys);
});
