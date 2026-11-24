import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// What the user chose in a [PortionSheet].
sealed class PortionResult {
  const new();
}

class PortionGrams extends PortionResult {
  const new(this.grams);

  final double grams;
}

class PortionDelete extends PortionResult {
  const new();
}

/// Asks how much was eaten, showing the nutrition live as it's typed.
class PortionSheet extends StatefulWidget {
  const new({
    required this.title,
    required this.per100g,
    required this.actionLabel,
    super.key,
    this.subtitle,
    this.servingG,
    this.initialGrams,
    this.allowDelete = false,
  });

  final String title;
  final String? subtitle;
  final Nutrition per100g;
  final double? servingG;
  final double? initialGrams;
  final String actionLabel;
  final bool allowDelete;

  @override
  State<PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<PortionSheet> {
  late final TextEditingController _grams;

  @override
  void initState() {
    super.initState();
    final start = widget.initialGrams ?? widget.servingG ?? 100;
    _grams = TextEditingController(text: _plain(start));
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  double? get _value {
    final g = parseDecimal(_grams.text);
    if (g == null || g <= 0 || g > FoodLogEntry.maxGrams) return null;
    return g;
  }

  void _set(double grams) => setState(() => _grams.text = _plain(grams));

  void _submit() {
    final grams = _value;
    if (grams != null) Navigator.of(context).pop(PortionGrams(grams));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final grams = _value;
    final portion = grams == null ? null : widget.per100g.forGrams(grams);
    final serving = widget.servingG;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: text.titleLarge),
        if (widget.subtitle != null)
          Text(widget.subtitle!, style: text.bodySmall),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _grams,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'g'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          children: [
            if (serving != null)
              ActionChip(
                label: Text('1 serving (${formatGrams(serving)})'),
                onPressed: () => _set(serving),
              ),
            ActionChip(label: const Text('100 g'), onPressed: () => _set(100)),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text(
          portion == null ? '– kcal' : '${formatKcal(portion.kcal)} kcal',
          style: text.headlineSmall?.tabular,
        ),
        const SizedBox(height: Space.xs),
        MacroLine(portion ?? Nutrition.zero),
        const SizedBox(height: Space.xl),
        FilledButton(
          // Read the field when pressed, not the value from the last build,
          // so a tap straight after typing never saves a stale amount.
          onPressed: grams == null ? null : _submit,
          child: Text(widget.actionLabel),
        ),
        if (widget.allowDelete) ...[
          const SizedBox(height: Space.sm),
          TextButton(
            onPressed: () => Navigator.of(context).pop(const PortionDelete()),
            child: const Text('Remove from log'),
          ),
        ],
      ],
    );
  }
}

String _plain(double grams) => grams == grams.roundToDouble()
    ? grams.toStringAsFixed(0)
    : grams.toStringAsFixed(1);
