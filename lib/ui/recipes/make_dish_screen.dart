import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/preferences/food_preferences_notifier.dart';
import 'package:trendline/data/recipes/dish_template_providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/dish_templates.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// Make a dish from a template: the planner's way of inventing meals, here
/// by hand. Choices follow the user's preferences; any can be changed.
class MakeDishScreen extends ConsumerStatefulWidget {
  const new({super.key, this.seed});

  /// Fixes the first dish (for tests); otherwise it's random.
  final int? seed;

  @override
  ConsumerState<MakeDishScreen> createState() => _MakeDishScreenState();
}

class _MakeDishScreenState extends ConsumerState<MakeDishScreen> {
  late int _seed = widget.seed ?? Random().nextInt(1 << 31);
  String? _templateId;
  String? _flavourId;
  Map<int, TemplateOption?> _chosen = const {};
  bool _adding = false;

  void _shuffle() => setState(() {
    _seed++;
    _flavourId = null;
    _chosen = const {};
  });

  Future<void> _add(GeneratedDish dish, double? estimate) async {
    setState(() => _adding = true);
    try {
      await ref
          .read(recipesProvider.notifier)
          .addFromLibrary(
            dish.toRecipe(),
            origin: RecipeOrigin.template,
            foods: await ref.read(templateFoodsProvider.future),
            estimatedCookedWeightG: estimate,
          );
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
    final templates = ref.watch(dishTemplatesProvider);
    final foods = ref.watch(templateFoodsProvider);
    final prefs = ref.watch(foodPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Make a dish'),
        actions: [
          IconButton(
            tooltip: 'Something else',
            icon: const Icon(Icons.shuffle),
            onPressed: _shuffle,
          ),
        ],
      ),
      body: switch ((templates, foods, prefs)) {
        (AsyncError(:final error), _, _) ||
        (_, AsyncError(:final error), _) ||
        (_, _, AsyncError(:final error)) => ErrorView(
          error: error,
          onRetry: () => ref
            ..invalidate(dishTemplatesProvider)
            ..invalidate(templateFoodsProvider)
            ..invalidate(foodPreferencesProvider),
        ),
        (
          AsyncData(value: final t),
          AsyncData(value: final f),
          AsyncData(value: final p),
        ) =>
          _body(context, t, f, p),
        _ => const CenteredProgress(),
      },
    );
  }

  Widget _body(
    BuildContext context,
    DishTemplates all,
    Map<FoodKey, dynamic> foods,
    FoodPreferences prefs,
  ) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final template = all.templates.firstWhere(
      (t) => t.id == _templateId,
      orElse: () => all.templates[_seed % all.templates.length],
    );
    final result = generateDish(
      template,
      all.flavours,
      prefs,
      Random(_seed),
      flavourId: _flavourId,
      chosen: _chosen,
    );
    final per100g = {
      for (final e in ref.read(templateFoodsProvider).value!.entries)
        e.key: e.value.per100g,
    };
    final dish = result is GeneratedDish ? result : null;
    final nutrition = dish == null
        ? null
        : libraryRecipeNutrition(dish.toRecipe(), per100g);
    final estimate = dish?.expectedCookedWeightG({
      for (final e in per100g.entries) e.key: e.value.kcal,
    });
    final names = {
      for (final e in ref.read(templateFoodsProvider).value!.entries)
        e.key: e.value.name,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        Text('Dish', style: text.labelMedium),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final t in all.templates)
              ChoiceChip(
                label: Text(_shapeLabel(t)),
                selected: t.id == template.id,
                onSelected: (_) => setState(() {
                  _templateId = t.id;
                  _flavourId = null;
                  _chosen = const {};
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        Text('Flavour', style: text.labelMedium),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final id in template.flavourIds)
              ChoiceChip(
                label: Text(all.flavours[id]!.name),
                selected: dish?.flavour.id == id,
                onSelected:
                    prefs.cuisines[all.flavours[id]!.cuisine] ==
                        Preference.never
                    ? null
                    : (_) => setState(() => _flavourId = id),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        if (result case NoDish(:final reason))
          Text(reason, style: text.bodyMedium?.copyWith(color: colors.error))
        else if (dish != null) ...[
          Text(dish.name, style: text.titleLarge),
          if (nutrition != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              '${formatKcal(nutrition.perPortion.kcal)} kcal per portion · '
              '${template.portions} portions',
              style: text.titleMedium?.tabular,
            ),
            const SizedBox(height: Space.xs),
            MacroLine(nutrition.perPortion),
          ],
          if (estimate != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              'Expect about ${formatGrams(estimate)} cooked, so roughly '
              '${formatGrams((estimate / template.portions / 10).round() * 10)}'
              ' a portion.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: Space.lg),
          for (final (i, slot) in template.slots.indexed)
            _SlotPicker(
              slot: slot,
              value: dish.picks[i],
              prefs: prefs,
              onChanged: (o) => setState(() => _chosen = {..._chosen, i: o}),
            ),
          const SizedBox(height: Space.md),
          Text('Ingredients (raw weight)', style: text.titleSmall),
          for (final i in dish.ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Expanded(child: Text(names[i.key] ?? i.cofidName)),
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
          FilledButton(
            onPressed: _adding || nutrition == null
                ? null
                : () => _add(dish, estimate),
            child: const Text('Add to my recipes'),
          ),
        ],
      ],
    );
  }
}

/// "Rice bowl", "Noodle stir-fry": the template name without placeholders.
String _shapeLabel(DishTemplate t) {
  final words = t.name
      .replaceAll(RegExp(r'\{[a-z]+\}'), '')
      .replaceAll(RegExp(r'\b(and|with)\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return words.isEmpty ? t.id : words[0].toUpperCase() + words.substring(1);
}

class _SlotPicker extends StatelessWidget {
  const new({
    required this.slot,
    required this.value,
    required this.prefs,
    required this.onChanged,
  });

  final TemplateSlot slot;
  final TemplateOption? value;
  final FoodPreferences prefs;
  final ValueChanged<TemplateOption?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final o in slot.options)
        if (prefs.ingredients[o.raw] != Preference.never) o,
    ];
    final role = slot.role.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              role[0].toUpperCase() + role.substring(1),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          DropdownButton<TemplateOption?>(
            value: options.contains(value) ? value : null,
            underline: const SizedBox.shrink(),
            items: [
              if (slot.optional) const DropdownMenuItem(child: Text('None')),
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o.label)),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
