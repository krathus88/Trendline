import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/food_browser.dart';
import 'package:trendline/ui/food/portion_sheet.dart';
import 'package:trendline/ui/recipes/recipe_editor_screen.dart';

/// Pick a food and portion to log into [slot] on [day].
class FoodPickerScreen extends ConsumerStatefulWidget {
  const new({required this.day, required this.slot, super.key});

  final DateTime day;
  final MealSlot slot;

  @override
  ConsumerState<FoodPickerScreen> createState() => _FoodPickerScreenState();
}

class _FoodPickerScreenState extends ConsumerState<FoodPickerScreen> {
  bool _logging = false;

  Future<void> _onChosen(FoodChoice choice) async {
    if (_logging) return;
    final result = await showAppSheet<PortionResult>(
      context,
      builder: (_) => PortionSheet(
        title: choice.name,
        subtitle: choice.brand,
        per100g: choice.per100g,
        servingG: choice.servingG,
        actionLabel: 'Add to ${mealSlotLabel(widget.slot).toLowerCase()}',
      ),
    );
    if (result is! PortionGrams || !mounted) return;

    setState(() => _logging = true);
    try {
      // New foods are saved first, so they're quick to find next time.
      final food = switch (choice) {
        SavedFood(:final food) => food,
        NewFood(:final draft) =>
          await ref.read(foodsProvider.notifier).save(draft),
      };
      await ref
          .read(foodLogProvider(widget.day).notifier)
          .add(slot: widget.slot, food: food, grams: result.grams);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  Future<void> _onRecipeChosen(Recipe recipe) async {
    if (_logging) return;
    final n = recipeNutrition(recipe, ref.read(foodsByIdProvider));
    final per100g = n.per100gCooked;
    if (per100g == null || !n.complete) {
      // Portions are eaten by cooked weight, so the batch must be weighed.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              n.complete
                  ? 'Weigh ${recipe.name} after cooking to log it by weight.'
                  : 'Still loading the recipe’s ingredients. Try again.',
            ),
            action: n.complete
                ? SnackBarAction(
                    label: 'Add weight',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecipeEditorScreen(existing: recipe),
                      ),
                    ),
                  )
                : null,
          ),
        );
      return;
    }
    final result = await showAppSheet<PortionResult>(
      context,
      builder: (_) => PortionSheet(
        title: recipe.name,
        subtitle: 'Cooked weight',
        per100g: per100g,
        servingG: recipe.portionG,
        servingLabel: '1 portion',
        actionLabel: 'Add to ${mealSlotLabel(widget.slot).toLowerCase()}',
      ),
    );
    if (result is! PortionGrams || !mounted) return;

    setState(() => _logging = true);
    try {
      await ref
          .read(foodLogProvider(widget.day).notifier)
          .addRecipe(
            slot: widget.slot,
            recipe: recipe,
            per100gCooked: per100g,
            grams: result.grams,
          );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${mealSlotLabel(widget.slot).toLowerCase()}'),
        bottom: _logging
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: FoodBrowser(
        onChosen: _onChosen,
        onRecipeChosen: _onRecipeChosen,
        includeShared: true,
      ),
    );
  }
}
