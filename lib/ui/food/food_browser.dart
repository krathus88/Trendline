import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/foods/foods_notifier.dart';
import 'package:trendline/data/off/off_product.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/manual_food_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// A food the user picked: one they've saved, or a new one from Open Food
/// Facts that isn't saved yet.
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

/// Saved foods (filtered as you type), Open Food Facts search (on submit, to
/// respect their rate limit), barcode scanning and manual entry.
class FoodBrowser extends ConsumerStatefulWidget {
  const new({required this.onChosen, super.key});

  final ValueChanged<FoodChoice> onChosen;

  @override
  ConsumerState<FoodBrowser> createState() => _FoodBrowserState();
}

class _FoodBrowserState extends ConsumerState<FoodBrowser> {
  final _query = TextEditingController();
  String _filter = '';

  String? _searchedFor;
  List<OffProduct>? _results;
  Object? _searchError;
  bool _searching = false;
  bool _scanning = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
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

  Future<void> _addManually({String? barcode}) async {
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(builder: (_) => ManualFoodScreen(barcode: barcode)),
    );
    if (food != null && mounted) widget.onChosen(SavedFood(food));
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
              hintText: 'Search your foods or UK products',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _filter = v.trim()),
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
            for (final p in _results!)
              _FoodTile(
                name: p.name,
                brand: p.brand,
                per100g: p.per100g,
                onTap: () => widget.onChosen(NewFood(p.toDraft())),
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
