import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/food/food_browser.dart';
import 'package:trendline/ui/food/portion_sheet.dart';

/// A chosen ingredient: the (saved) food and its raw grams.
typedef PickedIngredient = ({Food food, RecipeIngredient ingredient});

/// Pick a food and its raw amount for a recipe. Pops with a
/// [PickedIngredient], or null if cancelled.
class IngredientPickerScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<IngredientPickerScreen> createState() =>
      _IngredientPickerScreenState();
}

class _IngredientPickerScreenState
    extends ConsumerState<IngredientPickerScreen> {
  bool _saving = false;

  Future<void> _onChosen(FoodChoice choice) async {
    if (_saving) return;
    final result = await showAppSheet<PortionResult>(
      context,
      builder: (_) => PortionSheet(
        title: choice.name,
        subtitle: 'Raw weight, before cooking',
        per100g: choice.per100g,
        servingG: choice.servingG,
        actionLabel: 'Add to recipe',
      ),
    );
    if (result is! PortionGrams || !mounted) return;

    setState(() => _saving = true);
    try {
      // Ingredients are always the user's own foods, so new ones are saved.
      final food = switch (choice) {
        SavedFood(:final food) => food,
        NewFood(:final draft) =>
          await ref.read(foodsProvider.notifier).save(draft),
      };
      if (!mounted) return;
      Navigator.of(context).pop<PickedIngredient>((
        food: food,
        ingredient: RecipeIngredient(foodId: food.id, rawGrams: result.grams),
      ));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add ingredient'),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: FoodBrowser(onChosen: _onChosen),
    );
  }
}
