import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Enter a food from its label. Saves it and pops with the saved [Food].
class ManualFoodScreen extends ConsumerStatefulWidget {
  const new({super.key, this.barcode});

  /// Pre-filled when a scanned product wasn't found online.
  final String? barcode;

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
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseDecimal(c.text);

  Future<void> _save() async {
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    final per100g = Nutrition(
      kcal: parseDecimal(_kcal.text)!,
      proteinG: parseDecimal(_protein.text)!,
      carbsG: parseDecimal(_carbs.text)!,
      fatG: parseDecimal(_fat.text)!,
      fibreG: _opt(_fibre) ?? 0,
    );
    final problem = validatePer100g(per100g);
    final sugar = _opt(_sugar);
    if (problem != null) {
      setState(() => _formError = problem);
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
      saltG: _opt(_salt),
      servingG: _opt(_serving),
      source: FoodSource.manual,
    );

    setState(() => _saving = true);
    try {
      final food = await ref.read(foodsProvider.notifier).save(draft);
      if (mounted) Navigator.of(context).pop(food);
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
            Text('Per 100 g', style: text.titleSmall),
            const SizedBox(height: Space.sm),
            _Number(controller: _kcal, label: 'Energy', suffix: 'kcal'),
            _row(
              _Number(controller: _protein, label: 'Protein', suffix: 'g'),
              _Number(controller: _carbs, label: 'Carbs', suffix: 'g'),
            ),
            _row(
              _Number(controller: _fat, label: 'Fat', suffix: 'g'),
              _Number(
                controller: _fibre,
                label: 'Fibre',
                suffix: 'g',
                required: false,
              ),
            ),
            _row(
              _Number(
                controller: _sugar,
                label: 'of which sugars',
                suffix: 'g',
                required: false,
              ),
              _Number(
                controller: _salt,
                label: 'Salt',
                suffix: 'g',
                required: false,
              ),
            ),
            _Number(
              controller: _serving,
              label: 'One serving (optional)',
              suffix: 'g',
              required: false,
            ),
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
              child: const Text('Save food'),
            ),
          ],
        ),
      ),
    );
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
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.md),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (v) {
        final empty = v == null || v.trim().isEmpty;
        if (empty) return required ? 'Required' : null;
        final value = parseDecimal(v);
        if (value == null || value < 0) return 'Enter a number';
        return null;
      },
    ),
  );
}
