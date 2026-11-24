import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/preferences/food_preferences_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe_library.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

String preferenceLabel(Preference? p) => switch (p) {
  Preference.like => 'Like',
  Preference.dislike => 'Dislike',
  Preference.never => 'Never',
  null => 'No preference',
};

String cuisineLabel(Cuisine c) => c.name[0].toUpperCase() + c.name.substring(1);

/// Friendly names for the basic foods the user has preferences on.
final _preferenceFoodNamesProvider = FutureProvider<Map<FoodKey, String>>((
  ref,
) async {
  final prefs = await ref.watch(foodPreferencesProvider.future);
  final drafts = await ref
      .watch(referenceFoodRepositoryProvider)
      .fetchByKeys(prefs.ingredients.keys.toSet());
  return {for (final e in drafts.entries) e.key: e.value.name};
});

/// Likes, dislikes and nevers for cuisines and basic foods.
class FoodPreferencesScreen extends ConsumerWidget {
  const new({super.key});

  Future<void> _set(
    BuildContext context,
    Future<void> Function() change,
  ) async {
    try {
      await change();
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _addFood(BuildContext context, WidgetRef ref) async {
    final food = await Navigator.of(context).push<FoodDraft>(
      MaterialPageRoute(builder: (_) => const _BasicFoodSearchScreen()),
    );
    final code = food?.referenceCode;
    final name = food?.referenceName;
    if (food == null || code == null || name == null || !context.mounted) {
      return;
    }
    final preference = await showAppSheet<Preference>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(food.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Space.lg),
          for (final p in Preference.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(p),
                child: Text(preferenceLabel(p)),
              ),
            ),
        ],
      ),
    );
    if (preference == null || !context.mounted) return;
    await _set(
      context,
      () => ref.read(foodPreferencesProvider.notifier).setIngredient((
        code: code,
        name: name,
      ), preference),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final prefs = ref.watch(foodPreferencesProvider);
    final names = ref.watch(_preferenceFoodNamesProvider).value ?? const {};
    final notifier = ref.read(foodPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Food preferences')),
      body: switch (prefs) {
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(foodPreferencesProvider),
        ),
        AsyncLoading() when prefs.value == null => const CenteredProgress(),
        _ => ListView(
          padding: const EdgeInsets.only(bottom: Space.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Text(
                'The planner makes dishes with what you like more often, '
                'what you dislike less often, and never uses what you mark '
                'Never. You don’t need to say why.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
            const _Header('Cuisines'),
            for (final c in Cuisine.values)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                ),
                title: Text(cuisineLabel(c)),
                trailing: _PreferencePicker(
                  value: prefs.value!.cuisines[c],
                  onChanged: (p) =>
                      _set(context, () => notifier.setCuisine(c, p)),
                ),
              ),
            const SizedBox(height: Space.md),
            const _Header('Foods'),
            for (final MapEntry(:key, :value)
                in prefs.value!.ingredients.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                ),
                title: Text(names[key] ?? key.name),
                trailing: _PreferencePicker(
                  value: value,
                  onChanged: (p) =>
                      _set(context, () => notifier.setIngredient(key, p)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addFood(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a food'),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _Header extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.sm,
      Space.gutter,
      Space.xs,
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}

class _PreferencePicker extends StatelessWidget {
  const new({required this.value, required this.onChanged});

  final Preference? value;
  final ValueChanged<Preference?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<Preference?>(
    value: value,
    underline: const SizedBox.shrink(),
    items: [
      for (final p in [null, ...Preference.values])
        DropdownMenuItem(value: p, child: Text(preferenceLabel(p))),
    ],
    onChanged: onChanged,
  );
}

/// Search basic foods (as you type) and pick one.
class _BasicFoodSearchScreen extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_BasicFoodSearchScreen> createState() =>
      _BasicFoodSearchScreenState();
}

class _BasicFoodSearchScreenState
    extends ConsumerState<_BasicFoodSearchScreen> {
  Timer? _timer;
  String _query = '';
  List<FoodDraft> _results = const [];
  Object? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _changed(String value) {
    _timer?.cancel();
    final query = value.trim();
    _query = query;
    if (query.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _timer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await ref
            .read(referenceFoodRepositoryProvider)
            .search(query);
        if (mounted && _query == query) {
          setState(() {
            _results = results;
            _error = null;
          });
        }
      } on Object catch (e) {
        if (mounted) setState(() => _error = e);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose a food')),
    body: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search basic foods',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _changed,
          ),
        ),
        if (_error != null)
          ErrorView(error: _error!, onRetry: () => _changed(_query))
        else
          for (final d in _results)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Space.gutter,
              ),
              title: Text(d.name),
              onTap: () => Navigator.of(context).pop(d),
            ),
      ],
    ),
  );
}
