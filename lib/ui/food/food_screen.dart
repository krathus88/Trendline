import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/food_browser.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/recipes/recipe_list.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// The food library: saved foods (and finding new ones), and recipes.
class FoodScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Food'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Foods'),
              Tab(text: 'Recipes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            FoodBrowser(
              onChosen: (choice) => showAppSheet<void>(
                context,
                builder: (_) => _FoodDetails(choice: choice),
              ),
            ),
            const RecipeList(),
          ],
        ),
      ),
    );
  }
}

class _FoodDetails extends ConsumerStatefulWidget {
  const new({required this.choice});

  final FoodChoice choice;

  @override
  ConsumerState<_FoodDetails> createState() => _FoodDetailsState();
}

class _FoodDetailsState extends ConsumerState<_FoodDetails> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessageSnack(context, done);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = widget.choice;
    final n = c.per100g;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.name, style: text.titleLarge),
        if (c.brand != null) Text(c.brand!, style: text.bodySmall),
        const SizedBox(height: Space.lg),
        Text('${formatKcal(n.kcal)} kcal', style: text.headlineSmall?.tabular),
        Text('per 100 g', style: text.bodySmall),
        const SizedBox(height: Space.sm),
        MacroLine(n),
        if (c.servingG != null) ...[
          const SizedBox(height: Space.sm),
          Text(
            'One serving: ${formatGrams(c.servingG!)}',
            style: text.bodySmall,
          ),
        ],
        const SizedBox(height: Space.xl),
        switch (c) {
          NewFood(:final draft) => FilledButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref.read(foodsProvider.notifier).save(draft),
                    'Saved to your foods',
                  ),
            child: const Text('Save to my foods'),
          ),
          SavedFood(:final food) => OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref.read(foodsProvider.notifier).delete(food.id),
                    'Removed. Past logs keep their details.',
                  ),
            child: const Text('Remove from my foods'),
          ),
        },
      ],
    );
  }
}
