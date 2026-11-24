import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/meal_rules/meal_rules_notifier.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/food_browser.dart';
import 'package:trendline/ui/meal_rules/meal_rule_editor_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// A rule's food or recipe, ready for the editor.
typedef RuleTarget = ({String? foodId, String? recipeId, String name});

/// "Every day · breakfast · 250 g", "At least 2 a week · any meal ·
/// 120–180 g", "At most 3 a week · dinner · 1 portion".
String ruleSummary(MealRule r) {
  final how = switch (r.frequency) {
    RuleFrequency.daily => 'Every day',
    RuleFrequency.minPerWeek => 'At least ${r.timesPerWeek} a week',
    RuleFrequency.maxPerWeek => 'At most ${r.timesPerWeek} a week',
  };
  final meal = r.slot == null
      ? 'any meal'
      : mealSlotLabel(r.slot!).toLowerCase();
  String amount(double v) => r.isRecipe
      ? (v == 1 ? '1 portion' : '${_plain(v)} portions')
      : formatGrams(v);
  final size = r.amountMin == r.amountMax
      ? amount(r.amountMin)
      : r.isRecipe
      ? '${_plain(r.amountMin)}–${_plain(r.amountMax)} portions'
      : '${_plain(r.amountMin)}–${formatGrams(r.amountMax)}';
  return '$how · $meal · $size';
}

String _plain(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Mandatory and recurring items the planner must respect.
class MealRulesScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _add(BuildContext context) async {
    final target = await Navigator.of(context).push<RuleTarget>(
      MaterialPageRoute(builder: (_) => const _TargetPickerScreen()),
    );
    if (target == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MealRuleEditorScreen(target: target),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(mealRulesProvider);
    final foods = ref.watch(foodsByIdProvider);
    final recipes = {
      for (final r in ref.watch(recipesProvider).value ?? const <Recipe>[])
        r.id: r,
    };
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    String nameOf(MealRule r) =>
        (r.isRecipe ? recipes[r.recipeId]?.name : foods[r.foodId]?.name) ??
        'Loading…';

    return Scaffold(
      appBar: AppBar(title: const Text('Meal rules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add rule'),
      ),
      body: switch (rules) {
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(mealRulesProvider),
        ),
        AsyncLoading() when rules.value == null => const CenteredProgress(),
        _ => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Text(
                'Things the planner must include, like a daily cappuccino '
                'at breakfast, or salmon at least twice a week.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
            for (final problem in ruleConflicts(rules.value!, nameOf))
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                  vertical: Space.xs,
                ),
                child: Text(
                  'Can’t all be kept: $problem',
                  style: text.bodyMedium?.copyWith(color: colors.error),
                ),
              ),
            if (rules.value!.isEmpty)
              const EmptyState(
                title: 'No rules yet',
                message: 'Add the things you always (or often) have.',
              ),
            for (final r in rules.value!)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                ),
                title: Text(nameOf(r)),
                subtitle: Text(ruleSummary(r)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MealRuleEditorScreen(
                      target: (
                        foodId: r.foodId,
                        recipeId: r.recipeId,
                        name: nameOf(r),
                      ),
                      existing: r,
                    ),
                  ),
                ),
              ),
          ],
        ),
      },
    );
  }
}

/// Pick the food or recipe a rule is about.
class _TargetPickerScreen extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_TargetPickerScreen> createState() =>
      _TargetPickerScreenState();
}

class _TargetPickerScreenState extends ConsumerState<_TargetPickerScreen> {
  bool _saving = false;

  Future<void> _food(FoodChoice choice) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Rules are about the user's own foods, so a new one is saved first.
      final food = switch (choice) {
        SavedFood(:final food) => food,
        NewFood(:final draft) =>
          await ref.read(foodsProvider.notifier).save(draft),
      };
      if (mounted) {
        Navigator.of(
          context,
        ).pop<RuleTarget>((foodId: food.id, recipeId: null, name: food.name));
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rule for…')),
    body: FoodBrowser(
      onChosen: _food,
      onRecipeChosen: (r) =>
          Navigator.of(context)
              .pop<RuleTarget>((foodId: null, recipeId: r.id, name: r.name)),
    ),
  );
}
