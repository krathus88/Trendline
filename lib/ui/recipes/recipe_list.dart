import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/recipes/recipe_editor_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// The user's recipes, with a button to add one.
class RecipeList extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider);

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
          child: FilledButton.tonalIcon(
            onPressed: open,
            icon: const Icon(Icons.add),
            label: const Text('New recipe'),
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
          _ when (recipes.value ?? const []).isEmpty => const EmptyState(
            title: 'No recipes yet',
            message:
                'Add a dish you cook in batches. Weigh it after cooking to '
                'log portions by weight.',
          ),
          _ => Column(
            children: [
              for (final r in recipes.value!)
                RecipeTile(recipe: r, onTap: () => open(r)),
            ],
          ),
        },
      ],
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
