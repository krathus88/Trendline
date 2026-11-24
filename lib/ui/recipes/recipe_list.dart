import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/recipes/library_recipe_sheet.dart';
import 'package:trendline/ui/recipes/make_dish_screen.dart';
import 'package:trendline/ui/recipes/recipe_editor_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// The user's recipes, with a button to add one, then the built-in library.
class RecipeList extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);
    final library = ref.watch(recipeLibraryProvider).value ?? const [];

    void open([Recipe? recipe]) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeEditorScreen(existing: recipe),
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: open,
                  icon: const Icon(Icons.add),
                  label: const Text('New recipe'),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MakeDishScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Make a dish'),
                ),
              ),
            ],
          ),
        ),
        switch (recipes) {
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(recipesProvider),
          ),
          AsyncLoading() when recipes.value == null => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: CenteredProgress(),
          ),
          _ when !(recipes.value ?? const []).any((r) => r.listed) =>
            const EmptyState(
              title: 'No recipes yet',
              message:
                  'Add a dish you cook in batches. Weigh it after cooking to '
                  'log portions by weight.',
            ),
          _ => Column(
            children: [
              for (final r in recipes.value!)
                if (r.listed) RecipeTile(recipe: r, onTap: () => open(r)),
            ],
          ),
        },
        if (library.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Space.xs,
            ),
            child: Text(
              'From the library',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          for (final r in library) _LibraryTile(recipe: r),
        ],
      ],
    );
  }
}

class _LibraryTile extends ConsumerWidget {
  const new({required this.recipe});

  final LibraryRecipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final foods = ref.watch(libraryFoodsProvider).value ?? const {};
    final n = libraryRecipeNutrition(recipe, {
      for (final e in foods.entries) e.key: e.value.per100g,
    });
    ref.watch(recipesProvider);
    final added = ref.read(recipesProvider.notifier).copyOf(recipe) != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      title: Text(recipe.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        added ? '${librarySummary(recipe)} · added' : librarySummary(recipe),
      ),
      trailing: n == null
          ? null
          : Text(
              '${formatKcal(n.perPortion.kcal)} kcal\nper portion',
              textAlign: TextAlign.end,
              style: text.labelSmall?.tabular.copyWith(
                color: colors.textSecondary,
              ),
            ),
      onTap: () => showAppSheet<void>(
        context,
        builder: (_) => LibraryRecipeSheet(recipe: recipe),
      ),
    );
  }
}

/// A recipe with its portions and energy per portion.
class RecipeTile extends ConsumerWidget {
  const new({required this.recipe, required this.onTap, super.key});

  final Recipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final n = recipeNutrition(recipe, ref.watch(foodsByIdProvider));
    final portions = recipe.portions == 1
        ? '1 portion'
        : '${recipe.portions} portions';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      title: Text(recipe.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        recipe.cookedWeightG == null
            ? '$portions · not weighed yet'
            : '$portions of ${formatGrams(recipe.portionG!)}',
      ),
      trailing: Text(
        '${formatKcal(n.perPortion.kcal)} kcal\nper portion',
        textAlign: TextAlign.end,
        style: text.labelSmall?.tabular.copyWith(color: colors.textSecondary),
      ),
      onTap: onTap,
    );
  }
}
