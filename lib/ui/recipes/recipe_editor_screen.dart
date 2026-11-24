import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/food/portion_sheet.dart';
import 'package:trendline/ui/recipes/ingredient_picker_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// Create or edit a recipe: ingredients in raw grams, portions, and the
/// cooked weight once it's been weighed.
class RecipeEditorScreen extends ConsumerStatefulWidget {
  const new({super.key, this.existing});

  final Recipe? existing;

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _portions;
  late final TextEditingController _cooked;
  late final TextEditingController _fridgeDays;
  late final TextEditingController _method;
  late bool _freezable;
  late List<RecipeIngredient> _ingredients;

  /// Foods picked in this session that the cached list may not show yet.
  final _picked = <String, Food>{};
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _name = TextEditingController(text: r?.name ?? '');
    _portions = TextEditingController(text: '${r?.portions ?? 4}');
    _cooked = TextEditingController(
      text: r?.cookedWeightG == null ? '' : _plain(r!.cookedWeightG!),
    );
    _fridgeDays = TextEditingController(text: '${r?.fridgeDays ?? 3}');
    _method = TextEditingController(text: r?.method ?? '');
    _freezable = r?.freezable ?? true;
    _ingredients = [...?r?.ingredients];
  }

  @override
  void dispose() {
    for (final c in [_name, _portions, _cooked, _fridgeDays, _method]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The recipe as currently entered, or null if a number can't be read.
  Recipe? get _draft {
    final portions = int.tryParse(_portions.text.trim());
    final fridgeDays = int.tryParse(_fridgeDays.text.trim());
    final cookedText = _cooked.text.trim();
    final cooked = cookedText.isEmpty ? null : parseDecimal(cookedText);
    if (portions == null || fridgeDays == null) return null;
    if (cookedText.isNotEmpty && cooked == null) return null;
    return Recipe(
      id: widget.existing?.id ?? '',
      name: _name.text,
      ingredients: _ingredients,
      portions: portions,
      cookedWeightG: cooked,
      fridgeDays: fridgeDays,
      freezable: _freezable,
      method: _method.text,
    );
  }

  Future<void> _addIngredient() async {
    final picked = await Navigator.of(context).push<PickedIngredient>(
      MaterialPageRoute(builder: (_) => const IngredientPickerScreen()),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked[picked.food.id] = picked.food;
      _ingredients = [..._ingredients, picked.ingredient];
    });
  }

  Future<void> _editIngredient(int index, Food? food) async {
    final ingredient = _ingredients[index];
    final result = await showAppSheet<PortionResult>(
      context,
      builder: (_) => PortionSheet(
        title: food?.name ?? 'Ingredient',
        subtitle: 'Raw weight, before cooking',
        per100g: food?.per100g ?? Nutrition.zero,
        initialGrams: ingredient.rawGrams,
        actionLabel: 'Save',
        allowDelete: true,
        deleteLabel: 'Remove from recipe',
      ),
    );
    if (!mounted) return;
    setState(() {
      switch (result) {
        case PortionGrams(:final grams):
          _ingredients = [
            for (final (i, x) in _ingredients.indexed)
              if (i == index)
                RecipeIngredient(foodId: x.foodId, rawGrams: grams)
              else
                x,
          ];
        case PortionDelete():
          _ingredients = [..._ingredients]..removeAt(index);
        case null:
          break;
      }
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    final problem = draft == null
        ? 'Check the numbers: portions and fridge days are whole numbers.'
        : validateRecipe(draft);
    setState(() => _error = problem);
    if (problem != null) return;

    setState(() => _saving = true);
    try {
      await ref.read(recipesProvider.notifier).save(draft!);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this recipe?'),
        content: const Text(
          'Portions you’ve already logged keep their details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await ref.read(recipesProvider.notifier).delete(id);
      navigator.pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final foods = {...ref.watch(foodsByIdProvider), ..._picked};
    final draft = _draft;
    final nutrition = draft == null || _ingredients.isEmpty
        ? null
        : recipeNutrition(draft, foods);
    final warning = draft == null ? null : cookedWeightWarning(draft);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New recipe' : 'Edit recipe'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Delete recipe',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Space.xxl,
        ),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.sentences,
            maxLength: 200,
          ),
          const SizedBox(height: Space.sm),
          Text('Ingredients (raw weight)', style: text.titleSmall),
          for (final (i, ingredient) in _ingredients.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                foods[ingredient.foodId]?.name ?? 'Loading…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                formatGrams(ingredient.rawGrams),
                style: text.labelMedium?.tabular,
              ),
              onTap: () => _editIngredient(i, foods[ingredient.foodId]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addIngredient,
              icon: const Icon(Icons.add),
              label: const Text('Add ingredient'),
            ),
          ),
          const SizedBox(height: Space.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _portions,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Portions'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: TextField(
                  controller: _cooked,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cooked weight',
                    suffixText: 'g',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            warning ?? _weighHint(widget.existing?.estimatedCookedWeightG),
            style: text.bodySmall?.copyWith(
              color: warning != null ? colors.error : colors.textTertiary,
            ),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fridgeDays,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Keeps in the fridge',
                    suffixText: 'days',
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Freezable'),
                  value: _freezable,
                  onChanged: (v) => setState(() => _freezable = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _method,
            decoration: const InputDecoration(
              labelText: 'Method (optional)',
              alignLabelWithHint: true,
            ),
            minLines: 3,
            maxLines: 12,
            maxLength: 10000,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (nutrition != null) ...[
            const SizedBox(height: Space.md),
            _NutritionSummary(nutrition: nutrition, recipe: draft!),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              _error!,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save recipe'),
          ),
        ],
      ),
    );
  }
}

class _NutritionSummary extends StatelessWidget {
  const new({required this.nutrition, required this.recipe});

  final RecipeNutrition nutrition;
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final portion = recipe.portionG;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatKcal(nutrition.perPortion.kcal)} kcal per portion',
          style: text.headlineSmall?.tabular,
        ),
        if (portion != null)
          Text(
            'A portion is ${formatGrams(portion)} cooked · '
            '${formatKcal(nutrition.per100gCooked!.kcal)} kcal per 100 g',
            style: text.bodySmall,
          ),
        const SizedBox(height: Space.xs),
        MacroLine(nutrition.perPortion),
        if (!nutrition.complete)
          Text('Some ingredients are still loading.', style: text.bodySmall),
      ],
    );
  }
}

String _plain(double grams) => grams == grams.roundToDouble()
    ? grams.toStringAsFixed(0)
    : grams.toStringAsFixed(1);

/// How to record the cooked weight, with the expected weight of a dish the
/// planner made.
String _weighHint(double? estimate) {
  const weigh =
      'After cooking, weigh everything in the pot (minus the pot). Until '
      'then, portions can’t be logged by weight.';
  return estimate == null
      ? weigh
      : 'Expected about ${formatGrams(estimate)}. $weigh';
}
