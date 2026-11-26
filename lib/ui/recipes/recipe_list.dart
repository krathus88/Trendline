import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/recipes/recipe_favourites_notifier.dart';
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
    final household = ref.watch(householdProvider).value;
    final shared = ref.watch(sharedRecipesProvider);
    final favourites = ref.watch(recipeFavouritesProvider).value ?? const {};
    // Favourites first; otherwise the lists keep their order.
    List<Recipe> starredFirst(List<Recipe> recipes) => [
      for (final r in recipes)
        if (r.listed && favourites.contains(r.id)) r,
      for (final r in recipes)
        if (r.listed && !favourites.contains(r.id)) r,
    ];

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
              for (final r in starredFirst(recipes.value!))
                RecipeTile(recipe: r, onTap: () => open(r)),
            ],
          ),
        },
        if (household != null) ...[
          const SizedBox(height: Space.lg),
          _Heading('Shared with ${household.name}'),
          switch (shared) {
            AsyncError(:final error) => ErrorView(
              error: error,
              onRetry: () => ref.invalidate(sharedRecipesProvider),
            ),
            AsyncLoading() when shared.value == null => const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: CenteredProgress(),
            ),
            _ when !(shared.value ?? const []).any((r) => r.listed) =>
              const EmptyState(
                title: 'Nothing shared yet',
                message:
                    'Open one of your recipes and tap Share to give the '
                    'household a copy.',
              ),
            _ => Column(
              children: [
                for (final r in starredFirst(shared.value!))
                  RecipeTile(recipe: r, onTap: () => open(r)),
              ],
            ),
          },
        ],
        if (library.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const _Heading('From the library'),
          for (final r in library) _LibraryTile(recipe: r),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.sm,
      Space.gutter,
      Space.xs,
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
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

/// A recipe with its portions and energy per portion, and a star to make
/// it a favourite (planned more often, first in lists).
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
    final starred =
        ref.watch(recipeFavouritesProvider).value?.contains(recipe.id) ??
        false;
    return ListTile(
      contentPadding: const EdgeInsets.only(
        left: Space.xs,
        right: Space.gutter,
      ),
      leading: IconButton(
        tooltip: starred ? 'Remove from favourites' : 'Add to favourites',
        icon: Icon(
          starred ? Icons.star : Icons.star_border,
          color: starred ? colors.accent : colors.textTertiary,
        ),
        onPressed: () async {
          try {
            await ref.read(recipeFavouritesProvider.notifier).toggle(recipe.id);
          } on Object catch (e) {
            if (context.mounted) showErrorSnack(context, e);
          }
        },
      ),
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
