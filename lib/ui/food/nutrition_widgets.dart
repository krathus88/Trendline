import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// "P 12 g · C 40 g · F 3 g · Fibre 5 g", each with its macro colour.
class MacroLine extends StatelessWidget {
  const new(this.nutrition, {super.key, this.dense = false});

  final Nutrition nutrition;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style =
        (dense
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.labelMedium)
            ?.tabular
            .copyWith(color: colors.textSecondary);

    Widget item(String label, double grams, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.xs),
        Text('$label ${formatGrams(grams)}', style: style),
      ],
    );

    return Wrap(
      spacing: Space.md,
      runSpacing: Space.xs,
      children: [
        item('Protein', nutrition.proteinG, colors.protein),
        item('Carbs', nutrition.carbsG, colors.carbs),
        item('Fat', nutrition.fatG, colors.fat),
        item('Fibre', nutrition.fibreG, colors.fibre),
      ],
    );
  }
}

/// "379 kcal per 100 g"
class Per100Line extends StatelessWidget {
  const new(this.per100g, {super.key});

  final Nutrition per100g;

  @override
  Widget build(BuildContext context) => Text(
    '${formatKcal(per100g.kcal)} kcal per 100 g',
    style: Theme.of(context).textTheme.bodySmall?.tabular,
  );
}
