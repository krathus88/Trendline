import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/label_basis.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/recipes/ingredient_picker_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// What [ManualFoodScreen] saved: the food, and the mix made with it if the
/// user filled in "Made with".
typedef ManualFoodResult = ({Food food, Recipe? mix});

/// Enter a food from its label. Saves it and pops with a
/// [ManualFoodResult].
///
/// "Made with" is for something made up before it's eaten, like a coffee
/// sachet with milk: it also saves a one-portion recipe (a mix) of this food
/// plus the others, which is what gets logged and put in meal rules.
class ManualFoodScreen extends ConsumerStatefulWidget {
  const new({super.key, this.barcode, this.allowMix = true});

  /// Pre-filled when a scanned product wasn't found online.
  final String? barcode;

  /// Whether to offer "Made with".
  final bool allowMix;

  @override
  ConsumerState<ManualFoodScreen> createState() => _ManualFoodScreenState();
}

class _ManualFoodScreenState extends ConsumerState<ManualFoodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fibre = TextEditingController();
  final _sugar = TextEditingController();
  final _salt = TextEditingController();
  final _serving = TextEditingController();

  /// What the typed values are per, as printed on the label, and (made up
  /// with water) how much one serving makes.
  LabelBasis _basis = LabelBasis.per100g;
  final _makes = TextEditingController();

  /// "Made with": what else goes in, how much of this food one portion
  /// uses, and the mix's name.
  var _with = <PickedIngredient>[];
  final _amount = TextEditingController();
  final _mixName = TextEditingController();

  /// Set once the food is saved, so retrying after the mix failed to save
  /// doesn't save the food twice.
  Food? _savedFood;
  String? _formError;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _brand,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _fibre,
      _sugar,
      _salt,
      _serving,
      _makes,
      _amount,
      _mixName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseDecimal(c.text);

  Future<void> _addWith() async {
    final picked = await Navigator.of(context).push<PickedIngredient>(
      MaterialPageRoute(
        builder: (_) => const IngredientPickerScreen(
          title: 'Made with',
          amountHint: 'How much goes in one portion (for drinks, 1 ml ≈ 1 g)',
          actionLabel: 'Add',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _with = [..._with, picked];
      // Usually one serving of this food goes in.
      if (_amount.text.trim().isEmpty) _amount.text = _serving.text.trim();
    });
  }

  String get _defaultMixName {
    final name = _name.text.trim();
    final others = _with.map((p) => p.food.name).join(', ');
    final full = '${name.isEmpty ? 'This' : name} with $others';
    return full.length > 200 ? full.substring(0, 200).trim() : full;
  }

  /// The mix as entered, with [foodId] standing for this food, or null when
  /// nothing is made with it.
  Recipe? _mix(String foodId) {
    if (_with.isEmpty) return null;
    final amount = parseDecimal(_amount.text) ?? 0;
    final ingredients = [
      RecipeIngredient(foodId: foodId, rawGrams: amount),
      for (final p in _with) p.ingredient,
    ];
    final name = _mixName.text.trim();
    return Recipe(
      id: '',
      name: name.isEmpty ? _defaultMixName : name,
      ingredients: ingredients,
      portions: 1,
      // Nothing is cooked off: the portion weighs what goes in.
      cookedWeightG: ingredients.fold<double>(0, (s, i) => s + i.rawGrams),
      fridgeDays: 0,
      freezable: false,
      origin: RecipeOrigin.mix,
    );
  }

  Future<void> _save() async {
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    final mixProblem = switch (_mix('')) {
      null => null,
      final mix => validateRecipe(mix),
    };
    if (mixProblem != null) {
      setState(
        () => _formError = mixProblem.startsWith('Each ingredient')
            ? 'Enter how much of this food goes in one portion '
                  '(up to 4999 g).'
            : mixProblem,
      );
      return;
    }

    final factor = _factor;
    final per100g = _formPer100g;
    if (factor == null || per100g == null) {
      setState(() => _formError = 'Enter the serving size.');
      return;
    }
    final problem = validatePer100g(per100g);
    final sugar = _scaled(_sugar, factor);
    if (problem != null) {
      setState(
        () => _formError = _basis == LabelBasis.per100g
            ? problem
            : '$problem Check the serving size and what the values are per.',
      );
      return;
    }
    if (sugar != null && sugar > per100g.carbsG + 0.5) {
      setState(() => _formError = 'Sugar can’t be more than total carbs.');
      return;
    }

    final draft = FoodDraft(
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: widget.barcode,
      per100g: per100g,
      sugarG: sugar,
      saltG: _scaled(_salt, factor),
      servingG: _opt(_serving),
      source: FoodSource.manual,
    );

    setState(() => _saving = true);
    try {
      final food =
          _savedFood ?? await ref.read(foodsProvider.notifier).save(draft);
      _savedFood = food;
      final mix = _mix(food.id);
      final savedMix = mix == null
          ? null
          : await ref.read(recipesProvider.notifier).save(mix);
      if (mounted) {
        Navigator.of(context)
            .pop<ManualFoodResult>((food: food, mix: savedMix));
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Add food')),
      body: Form(
        key: _formKey,
        // Keeps the converted values, the mix's portion summary and its
        // suggested name current.
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xxl,
          ),
          children: [
            if (widget.barcode != null) ...[
              Text(
                'Barcode ${widget.barcode} wasn’t found online. Enter the '
                'details from the label.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.lg),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 200,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            TextFormField(
              controller: _brand,
              decoration: const InputDecoration(
                labelText: 'Brand or shop (optional)',
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 200,
            ),
            const SizedBox(height: Space.sm),
            Text('Label values are per', style: text.titleSmall),
            const SizedBox(height: Space.sm),
            SegmentedButton<LabelBasis>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: LabelBasis.per100g,
                  label: Text('100 g / ml'),
                ),
                ButtonSegment(
                  value: LabelBasis.perServing,
                  label: Text('Serving'),
                ),
                ButtonSegment(
                  value: LabelBasis.per100mlMadeUp,
                  label: Text('100 ml made up'),
                ),
              ],
              selected: {_basis},
              onSelectionChanged: (s) => setState(() => _basis = s.single),
            ),
            const SizedBox(height: Space.xs),
            Text(switch (_basis) {
              LabelBasis.per100g =>
                'Copy the per 100 g (or per 100 ml) column.',
              LabelBasis.perServing =>
                'Copy the per serving column (per sachet, bar, mug…).',
              LabelBasis.per100mlMadeUp =>
                'For a sachet or powder made up with water: copy the per '
                    '100 ml column, and say how much one serving makes.',
            }, style: text.bodySmall?.copyWith(color: colors.textTertiary)),
            const SizedBox(height: Space.md),
            switch (_basis) {
              LabelBasis.per100g => const SizedBox.shrink(),
              LabelBasis.perServing => _Number(
                controller: _serving,
                label: 'Serving size',
                suffix: 'g',
                positive: true,
              ),
              LabelBasis.per100mlMadeUp => _row(
                _Number(
                  controller: _serving,
                  label: 'One serving, dry',
                  suffix: 'g',
                  positive: true,
                ),
                _Number(
                  controller: _makes,
                  label: 'Makes',
                  suffix: 'ml',
                  positive: true,
                ),
              ),
            },
            // Read left to right, in the order of a UK nutrition label, so
            // it can be copied straight down the table.
            _Number(controller: _kcal, label: 'Energy', suffix: 'kcal'),
            _row(
              _Number(controller: _fat, label: 'Fat', suffix: 'g'),
              _Number(controller: _carbs, label: 'Carbohydrate', suffix: 'g'),
            ),
            _row(
              _Number(
                controller: _sugar,
                label: 'of which sugars',
                suffix: 'g',
                required: false,
              ),
              _Number(
                controller: _fibre,
                label: 'Fibre',
                suffix: 'g',
                required: false,
              ),
            ),
            _row(
              _Number(controller: _protein, label: 'Protein', suffix: 'g'),
              _Number(
                controller: _salt,
                label: 'Salt',
                suffix: 'g',
                required: false,
              ),
            ),
            if (_basis == LabelBasis.per100g)
              _Number(
                controller: _serving,
                label: 'One serving (optional)',
                suffix: 'g',
                required: false,
                helper:
                    'How much you usually have: one sachet, slice or bar. '
                    'Offered as “1 serving” when you log it.',
              )
            else
              _convertedPreview(text, colors),
            if (widget.allowMix) ..._madeWith(text, colors),
            if (_formError != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _formError!,
                style: text.bodyMedium?.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_with.isEmpty ? 'Save food' : 'Save food and mix'),
            ),
          ],
        ),
      ),
    );
  }

  /// What to multiply the typed values by for per 100 g, or null while the
  /// serving amounts the basis needs are missing.
  double? get _factor => labelFactor(
    _basis,
    servingG: parseDecimal(_serving.text),
    makesMl: parseDecimal(_makes.text),
  );

  /// An optional typed value converted to per 100 g.
  double? _scaled(TextEditingController c, double factor) {
    final v = _opt(c);
    return v == null ? null : v * factor;
  }

  /// The form's values per 100 g of the food, once the required ones (and
  /// the serving amounts for the chosen basis) are filled in.
  Nutrition? get _formPer100g {
    final kcal = parseDecimal(_kcal.text);
    final protein = parseDecimal(_protein.text);
    final carbs = parseDecimal(_carbs.text);
    final fat = parseDecimal(_fat.text);
    final factor = _factor;
    if (kcal == null ||
        protein == null ||
        carbs == null ||
        fat == null ||
        factor == null) {
      return null;
    }
    // Fibre is optional on labels; blank means unknown, not none.
    final fibre = _opt(_fibre);
    return labelToPer100g(
      Nutrition(
        kcal: kcal,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
        fibreG: fibre ?? 0,
        fibreUnknown: fibre == null,
      ),
      factor,
    );
  }

  /// What will be saved, when the label isn't per 100 g.
  Widget _convertedPreview(TextTheme text, AppColors colors) {
    final per100g = _formPer100g;
    final factor = _factor;
    String g(double v) => '${(v * 10).round() / 10} g';
    final sugar = factor == null ? null : _scaled(_sugar, factor);
    final salt = factor == null ? null : _scaled(_salt, factor);
    final parts = per100g == null
        ? null
        : [
            '${formatKcal(per100g.kcal)} kcal',
            'fat ${g(per100g.fatG)}',
            'carbohydrate ${g(per100g.carbsG)}',
            if (sugar != null) 'sugars ${g(sugar)}',
            if (!per100g.fibreUnknown) 'fibre ${g(per100g.fibreG)}',
            'protein ${g(per100g.proteinG)}',
            if (salt != null) 'salt ${g(salt)}',
          ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Text(
        parts == null
            ? 'Saved per 100 g, worked out from these.'
            : 'Saved per 100 g: ${parts.join(' · ')}',
        style: text.bodySmall?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  List<Widget> _madeWith(TextTheme text, AppColors colors) {
    final amount = parseDecimal(_amount.text);
    final per100g = _formPer100g;
    final portion = per100g == null || amount == null
        ? null
        : _with.fold(
            per100g.forGrams(amount),
            (sum, p) => sum + p.food.per100g.forGrams(p.ingredient.rawGrams),
          );
    return [
      const SizedBox(height: Space.sm),
      Text('Made with (optional)', style: text.titleSmall),
      const SizedBox(height: Space.xs),
      Text(
        'For something you make up before eating it, like a coffee sachet '
        'with milk. Also saves it as a one-portion recipe, to log or use in '
        'meal rules.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      ),
      for (final (i, p) in _with.indexed)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            p.food.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: p.food.brand == null ? null : Text(p.food.brand!),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatGrams(p.ingredient.rawGrams),
                style: text.labelMedium?.tabular,
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    setState(() => _with = [..._with]..removeAt(i)),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _saving ? null : _addWith,
          icon: const Icon(Icons.add),
          label: Text(_with.isEmpty ? 'Made with…' : 'Add another'),
        ),
      ),
      if (_with.isNotEmpty) ...[
        const SizedBox(height: Space.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'This food in one portion',
              suffixText: 'g',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        TextFormField(
          controller: _mixName,
          decoration: InputDecoration(
            labelText: 'Name of the mix',
            hintText: _defaultMixName,
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          textCapitalization: TextCapitalization.sentences,
          maxLength: 200,
        ),
        if (portion != null) ...[
          Text(
            'One portion: ${formatKcal(portion.kcal)} kcal',
            style: text.titleMedium?.tabular,
          ),
          MacroLine(portion),
        ],
      ],
    ];
  }

  Widget _row(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: Space.md),
      Expanded(child: b),
    ],
  );
}

class _Number extends StatelessWidget {
  const new({
    required this.controller,
    required this.label,
    required this.suffix,
    this.required = true,
    this.positive = false,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool required;

  /// Must be more than 0 (an amount, not a nutrient).
  final bool positive;
  final String? helper;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.md),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: helper,
        helperMaxLines: 2,
      ),
      validator: (v) {
        final empty = v == null || v.trim().isEmpty;
        if (empty) return required ? 'Required' : null;
        final value = parseDecimal(v);
        if (value == null || value < 0) return 'Enter a number';
        if (positive && value == 0) return 'More than 0';
        return null;
      },
    ),
  );
}
