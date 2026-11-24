import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/recipe_library.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/recipes/recipe_editor_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// "Indian · lunch, dinner · 4 portions"
String librarySummary(LibraryRecipe r) {
  final cuisine = r.cuisine.name[0].toUpperCase() + r.cuisine.name.substring(1);
  final meals = [for (final m in r.meals) mealSlotLabel(m).toLowerCase()]
      .join(', ');
  final portions = r.portions == 1 ? '1 portion' : '${r.portions} portions';
  return '$cuisine · $meals · $portions';
}

/// A library recipe: what's in it, per-portion nutrition, and adding it to
/// the user's recipes.
class LibraryRecipeSheet extends ConsumerStatefulWidget {
  const new({required this.recipe, super.key});

  final LibraryRecipe recipe;

  @override
  ConsumerState<LibraryRecipeSheet> createState() => _LibraryRecipeSheetState();
}

class _LibraryRecipeSheetState extends ConsumerState<LibraryRecipeSheet> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await ref.read(recipesProvider.notifier).addFromLibrary(widget.recipe);
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessageSnack(
        context,
        'Added to your recipes. Weigh it after cooking to log portions.',
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final r = widget.recipe;
    final foods = ref.watch(libraryFoodsProvider).value ?? const {};
    final n = libraryRecipeNutrition(r, {
      for (final e in foods.entries) e.key: e.value.per100g,
    });
    ref.watch(recipesProvider);
    final copy = ref.read(recipesProvider.notifier).copyOf(r);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(r.name, style: text.titleLarge),
          Text(librarySummary(r), style: text.bodySmall),
          const SizedBox(height: Space.lg),
          if (n != null) ...[
            Text(
              '${formatKcal(n.perPortion.kcal)} kcal per portion',
              style: text.headlineSmall?.tabular,
            ),
            const SizedBox(height: Space.xs),
            MacroLine(n.perPortion),
            const SizedBox(height: Space.lg),
          ],
          Text('Ingredients (raw weight)', style: text.titleSmall),
          const SizedBox(height: Space.xs),
          for (final i in r.ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      foods[i.key]?.name ?? i.cofidName,
                      style: text.bodyMedium,
                    ),
                  ),
                  Text(
                    formatGrams(i.rawGrams),
                    style: text.labelMedium?.tabular.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.xl),
          if (copy != null)
            OutlinedButton(
              onPressed: () {
                Navigator.of(context)
                  ..pop()
                  ..push(
                    MaterialPageRoute<void>(
                      builder: (_) => RecipeEditorScreen(existing: copy),
                    ),
                  );
              },
              child: const Text('In your recipes: open it'),
            )
          else
            FilledButton(
              onPressed: _adding || n == null ? null : _add,
              child: const Text('Add to my recipes'),
            ),
        ],
      ),
    );
  }
}
