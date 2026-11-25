import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/off/off_product.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/manual_food_screen.dart';
import 'package:trendline/ui/recipes/recipe_list.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// A food the user picked: one they've saved, or a new one (from Open Food
/// Facts or the basic foods) that isn't saved yet.
sealed class FoodChoice {
  const new();

  String get name;
  String? get brand;
  Nutrition get per100g;
  double? get servingG;
}

class SavedFood extends FoodChoice {
  const new(this.food);

  final Food food;

  @override
  String get name => food.name;
  @override
  String? get brand => food.brand;
  @override
  Nutrition get per100g => food.per100g;
  @override
  double? get servingG => food.servingG;
}

class NewFood extends FoodChoice {
  const new(this.draft);

  final FoodDraft draft;

  @override
  String get name => draft.name;
  @override
  String? get brand => draft.brand;
  @override
  Nutrition get per100g => draft.per100g;
  @override
  double? get servingG => draft.servingG;
}

/// Saved foods and basic foods (both as you type), Open Food Facts search (on
/// submit, to respect their rate limit), barcode scanning and manual entry.
class FoodBrowser extends ConsumerStatefulWidget {
  const new({
    required this.onChosen,
    super.key,
    this.onRecipeChosen,
    this.allowMix = true,
  });

  final ValueChanged<FoodChoice> onChosen;

  /// When set, the user's recipes are listed too (for logging a portion or
  /// a meal rule). A mix made in "Enter from label" is chosen through it.
  final ValueChanged<Recipe>? onRecipeChosen;

  /// Whether "Enter from label" offers "Made with" (saving a mix).
  final bool allowMix;

  @override
  ConsumerState<FoodBrowser> createState() => _FoodBrowserState();
}

class _FoodBrowserState extends ConsumerState<FoodBrowser> {
  final _query = TextEditingController();
  String _filter = '';

  String? _searchedFor;
  List<OffSearchHit>? _results;
  Object? _searchError;
  bool _searching = false;
  bool _scanning = false;

  /// The search hit whose nutrition is being read, if any.
  String? _opening;

  /// Basic foods (CoFID) for [_basicFor], searched as the user types.
  static const _basicDebounce = Duration(milliseconds: 300);
  static const _basicShown = 8;
  Timer? _basicTimer;
  String? _basicFor;
  List<FoodDraft>? _basicResults;
  Object? _basicError;
  bool _showAllBasic = false;

  @override
  void dispose() {
    _basicTimer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _filter = value.trim());
    _basicTimer?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _basicFor = null;
        _basicResults = null;
        _basicError = null;
      });
      return;
    }
    _basicTimer = Timer(_basicDebounce, () => _searchBasic(query));
  }

  Future<void> _searchBasic(String query) async {
    setState(() {
      _basicFor = query;
      _basicError = null;
      _showAllBasic = false;
    });
    try {
      final results = await ref
          .read(referenceFoodRepositoryProvider)
          .search(query);
      // Ignore answers to a query the user has since changed.
      if (mounted && _basicFor == query) {
        setState(() => _basicResults = results);
      }
    } on Object catch (e) {
      if (mounted && _basicFor == query) setState(() => _basicError = e);
    }
  }

  void _chooseBasic(FoodDraft draft) {
    final saved = ref
        .read(foodsProvider.notifier)
        .byReference(draft.referenceCode!, draft.name);
    widget.onChosen(saved != null ? SavedFood(saved) : NewFood(draft));
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2 || _searching) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _searchedFor = query;
    });
    try {
      final results = await ref.read(offClientProvider).search(query);
      if (mounted) setState(() => _results = results);
    } on Object catch (e) {
      if (mounted) setState(() => _searchError = e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _scan() async {
    final code = await ref.read(barcodeScannerProvider).scan(context);
    if (code == null || !mounted) return;

    final saved = ref.read(foodsProvider.notifier).byBarcode(code);
    if (saved != null) {
      widget.onChosen(SavedFood(saved));
      return;
    }

    setState(() => _scanning = true);
    try {
      final product = await ref.read(offClientProvider).lookup(code);
      if (!mounted) return;
      if (product != null) {
        widget.onChosen(NewFood(product.toDraft()));
      } else {
        await _addManually(barcode: code);
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Search hits have no nutrition: read it by barcode (or reuse the saved
  /// copy). Without usable nutrition, opens manual entry with the barcode.
  Future<void> _chooseHit(OffSearchHit hit) async {
    if (_opening != null) return;
    final saved = ref.read(foodsProvider.notifier).byBarcode(hit.barcode);
    if (saved != null) {
      widget.onChosen(SavedFood(saved));
      return;
    }
    final known = hit.product;
    if (known != null) {
      widget.onChosen(NewFood(known.toDraft()));
      return;
    }

    setState(() => _opening = hit.barcode);
    try {
      final product = await ref.read(offClientProvider).lookup(hit.barcode);
      if (!mounted) return;
      if (product != null) {
        widget.onChosen(NewFood(product.toDraft()));
      } else {
        showMessageSnack(
          context,
          'Open Food Facts has no usable nutrition for this product. '
          'Enter it from the label.',
        );
        await _addManually(barcode: hit.barcode);
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _addManually({String? barcode}) async {
    final result = await Navigator.of(context).push<ManualFoodResult>(
      MaterialPageRoute(
        builder: (_) =>
            ManualFoodScreen(barcode: barcode, allowMix: widget.allowMix),
      ),
    );
    if (result == null || !mounted) return;
    final mix = result.mix;
    final onRecipe = widget.onRecipeChosen;
    // A mix is what's eaten, so it's what gets logged or ruled on.
    if (mix != null && onRecipe != null) {
      onRecipe(mix);
      return;
    }
    if (mix != null) {
      showMessageSnack(context, 'Also saved “${mix.name}” in Recipes.');
    }
    widget.onChosen(SavedFood(result.food));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scanner = ref.watch(barcodeScannerProvider);
    final saved = ref.watch(foodsProvider);
    final filter = _filter.toLowerCase();
    final matches = [
      for (final f in saved.value ?? const <Food>[])
        if (filter.isEmpty ||
            f.name.toLowerCase().contains(filter) ||
            (f.brand?.toLowerCase().contains(filter) ?? false))
          f,
    ];
    final canSearch = _query.text.trim().length >= 2;
    final onRecipe = widget.onRecipeChosen;
    final recipes = onRecipe == null
        ? const <Recipe>[]
        : [
            for (final r
                in ref.watch(recipesProvider).value ?? const <Recipe>[])
              if (filter.isEmpty || r.name.toLowerCase().contains(filter)) r,
          ];

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.sm,
          ),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search foods, basics or UK products',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _onQueryChanged,
            onSubmitted: (_) => _search(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Wrap(
            spacing: Space.sm,
            children: [
              if (scanner.isAvailable)
                ActionChip(
                  avatar: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(_scanning ? 'Looking up…' : 'Scan barcode'),
                  onPressed: _scanning ? null : _scan,
                ),
              ActionChip(
                avatar: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Enter from label'),
                onPressed: _addManually,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        if (recipes.isNotEmpty) ...[
          _Header(filter.isEmpty ? 'Your recipes' : 'Your recipes matching'),
          for (final r in recipes)
            RecipeTile(recipe: r, onTap: () => onRecipe!(r)),
          const SizedBox(height: Space.md),
        ],
        _Header(filter.isEmpty ? 'Your foods' : 'Your foods matching'),
        switch (saved) {
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(foodsProvider),
          ),
          AsyncLoading() when saved.value == null => const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: CenteredProgress(),
          ),
          _ when matches.isEmpty => EmptyState(
            title: filter.isEmpty ? 'No saved foods yet' : 'No saved matches',
            message: filter.isEmpty
                ? 'Search, scan or enter a food. Foods you log are saved '
                      'here for next time.'
                : null,
          ),
          _ => Column(
            children: [
              for (final f in matches)
                _FoodTile(
                  name: f.name,
                  brand: f.brand,
                  per100g: f.per100g,
                  onTap: () => widget.onChosen(SavedFood(f)),
                ),
            ],
          ),
        },
        if (_basicFor != null) ..._basicSection(text),
        if (canSearch && _searchedFor != _query.text.trim())
          ListTile(
            leading: const Icon(Icons.travel_explore),
            title: Text('Search UK products for “${_query.text.trim()}”'),
            onTap: _search,
          ),
        if (_searching || _results != null || _searchError != null) ...[
          const SizedBox(height: Space.md),
          _Header('Open Food Facts · “${_searchedFor ?? ''}”'),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: CenteredProgress(),
            )
          else if (_searchError != null)
            ErrorView(error: _searchError!, onRetry: _search)
          else if (_results!.isEmpty)
            const EmptyState(
              title: 'No usable results',
              message:
                  'Try another name, or enter it from the label. Products '
                  'without full nutrition are hidden.',
            )
          else
            for (final h in _results!)
              _HitTile(
                hit: h,
                opening: _opening == h.barcode,
                onTap: () => _chooseHit(h),
              ),
          Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: Text(
              'Product data from Open Food Facts, a free, crowd-sourced '
              'database (ODbL). Check it against the label.',
              style: text.bodySmall?.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _basicSection(TextTheme text) {
    final results = _basicResults;
    final loading = results == null && _basicError == null;
    final shown = results == null
        ? const <FoodDraft>[]
        : _showAllBasic
        ? results
        : results.take(_basicShown).toList();
    return [
      const SizedBox(height: Space.md),
      const _Header('Basic foods'),
      if (_basicError != null)
        ErrorView(error: _basicError!, onRetry: () => _searchBasic(_basicFor!))
      else if (loading)
        const Padding(
          padding: EdgeInsets.all(Space.xl),
          child: CenteredProgress(),
        )
      else if (results!.isEmpty)
        const EmptyState(title: 'No basic foods match')
      else ...[
        for (final d in shown)
          _FoodTile(
            name: d.name,
            per100g: d.per100g,
            onTap: () => _chooseBasic(d),
          ),
        if (!_showAllBasic && results.length > _basicShown)
          TextButton(
            onPressed: () => setState(() => _showAllBasic = true),
            child: Text('Show all ${results.length}'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xs,
            Space.gutter,
            0,
          ),
          child: Text(
            'Basic foods from CoFID, UK government data. Contains public '
            'sector information licensed under the Open Government Licence '
            'v3.0.',
            style: text.bodySmall?.copyWith(color: context.colors.textTertiary),
          ),
        ),
      ],
    ];
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

/// An Open Food Facts search hit. Its nutrition is read when tapped, so it
/// shows kcal only if the hit already had them.
class _HitTile extends StatelessWidget {
  const new({required this.hit, required this.opening, required this.onTap});

  final OffSearchHit hit;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final per100g = hit.product?.per100g;
    if (per100g != null && !opening) {
      return _FoodTile(
        name: hit.name,
        brand: hit.brand,
        per100g: per100g,
        onTap: onTap,
      );
    }
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      title: Text(hit.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: hit.brand == null ? null : Text(hit.brand!, maxLines: 1),
      trailing: opening
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.chevron_right, color: context.colors.textTertiary),
      onTap: onTap,
    );
  }
}

class _FoodTile extends StatelessWidget {
  const new({
    required this.name,
    required this.per100g,
    required this.onTap,
    this.brand,
  });

  final String name;
  final String? brand;
  final Nutrition per100g;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: brand == null ? null : Text(brand!, maxLines: 1),
      trailing: Text(
        '${formatKcal(per100g.kcal)} kcal\nper 100 g',
        textAlign: TextAlign.end,
        style: text.labelSmall?.tabular.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      onTap: onTap,
    );
  }
}
