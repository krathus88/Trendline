import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/prep/prep_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/domain/prep.dart';
import 'package:trendline/domain/recipe.dart';
import 'package:trendline/domain/recipe_library.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

String _day(DateTime day) => DateFormat('EEE d MMM').format(day);

/// "1 portion", "1.25 portions".
String portionsLabel(double n) {
  final s = n == n.roundToDouble()
      ? n.toStringAsFixed(0)
      : n.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return n == 1 ? '1 portion' : '$s portions';
}

/// "Dinner, Mon 7 Dec", or "Leftover" for a portion kept for no meal.
String portionMeal(PrepPortion p) =>
    p.day == null ? 'Leftover' : '${mealSlotLabel(p.slot!)}, ${_day(p.day!)}';

/// Batch cooks to do and cooked portions to eat: what to cook and when,
/// then what's in the fridge and freezer with use-by dates.
class PrepScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(prepProvider);
    // The household's batches use its shared recipes.
    final recipes = {
      for (final r in [
        ...?ref.watch(recipesProvider).value,
        ...?ref.watch(sharedRecipesProvider).value,
      ])
        r.id: r,
    };
    final me = ref.watch(currentUserIdProvider);
    final today = dayOf(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Prep')),
      body: switch (state) {
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(prepProvider),
        ),
        AsyncData(:final value) => _PrepList(
          sessions: activeSessions(value, today),
          recipes: recipes,
          today: today,
          me: me,
        ),
        _ => const CenteredProgress(),
      },
    );
  }
}

class _PrepList extends StatelessWidget {
  const new({
    required this.sessions,
    required this.recipes,
    required this.today,
    required this.me,
  });

  final List<PrepSession> sessions;
  final Map<String, Recipe> recipes;
  final DateTime today;

  /// Only the user's own portions are theirs to eat.
  final String? me;

  @override
  Widget build(BuildContext context) {
    final toCook = [
      for (final s in sessions)
        if (!s.cooked && recipes.containsKey(s.recipeId)) s,
    ];
    final cooked = [
      for (final s in sessions)
        if (s.cooked && recipes.containsKey(s.recipeId))
          for (final p in s.openPortionsFor(me)) (session: s, portion: p),
    ];
    if (toCook.isEmpty && cooked.isEmpty) {
      return const EmptyState(
        title: 'Nothing to prep',
        message:
            'Save a week’s plan and the batches it cooks show here, with '
            'what to cook and when.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: [
        if (toCook.isNotEmpty) ...[
          const _Header('To cook'),
          for (final s in toCook)
            _SessionTile(
              session: s,
              recipe: recipes[s.recipeId]!,
              today: today,
            ),
        ],
        if (cooked.isNotEmpty) ...[
          const _Header('Cooked portions'),
          for (final c in cooked)
            _PortionTile(
              session: c.session,
              portion: c.portion,
              recipe: recipes[c.session.recipeId]!,
              today: today,
            ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.lg,
      Space.gutter,
      Space.xs,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _SessionTile extends StatelessWidget {
  const new({required this.session, required this.recipe, required this.today});

  final PrepSession session;
  final Recipe recipe;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overdue = session.cookOn.isBefore(today);
    final meals = session.openPortions.where((p) => p.day != null).length;
    return ListTile(
      title: Text(recipe.name),
      subtitle: Text(
        '${overdue ? 'Was due' : 'Cook on'} ${_day(session.cookOn)} · '
        '${portionsLabel(session.portionCount)} for '
        '${meals == 1 ? '1 meal' : '$meals meals'}'
        '${session.isShared ? ' · household' : ''}',
        style: overdue ? TextStyle(color: colors.error) : null,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PrepSessionScreen(sessionId: session.id),
        ),
      ),
    );
  }
}

class _PortionTile extends ConsumerWidget {
  const new({
    required this.session,
    required this.portion,
    required this.recipe,
    required this.today,
  });

  final PrepSession session;
  final PrepPortion portion;
  final Recipe recipe;
  final DateTime today;

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final timing = portionTiming(portion, today);
    final canFreeze =
        recipe.freezable &&
        portion.storage == PrepStorage.fridge &&
        timing != PortionTiming.expired;
    var slot = portion.slot ?? MealSlot.lunch;
    final action = await showAppSheet<String>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(recipe.name, style: Theme.of(context).textTheme.titleLarge),
            Text(portionMeal(portion)),
            const SizedBox(height: Space.lg),
            if (timing != PortionTiming.expired) ...[
              Wrap(
                spacing: Space.sm,
                children: [
                  for (final s in MealSlot.values)
                    ChoiceChip(
                      label: Text(mealSlotLabel(s)),
                      selected: slot == s,
                      onSelected: (_) => setSheetState(() => slot = s),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop('eat'),
                icon: const Icon(Icons.check),
                label: const Text('Eaten today'),
              ),
            ],
            if (canFreeze) ...[
              const SizedBox(height: Space.sm),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop('freeze'),
                icon: const Icon(Icons.ac_unit),
                label: const Text('Move to the freezer'),
              ),
            ],
            const SizedBox(height: Space.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop('discard'),
              child: const Text('Thrown away'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    final notifier = ref.read(prepProvider.notifier);
    try {
      switch (action) {
        case 'eat':
          await notifier.eat(
            session: session,
            portion: portion,
            recipe: recipe,
            foods: ref.read(foodsByIdProvider),
            day: today,
            slot: slot,
          );
          if (context.mounted) {
            showMessageSnack(context, 'Logged ${recipe.name}');
          }
        case 'freeze':
          await notifier.freeze(portion);
        case 'discard':
          await notifier.discard(portion);
      }
    } on Object catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final grams = session.gramsOf(portion);
    final timing = portionTiming(portion, today);
    final frozen = portion.storage == PrepStorage.freezer;
    final (status, warn) = switch (timing) {
      PortionTiming.expired => ('Past its use-by date', true),
      PortionTiming.missed when portion.day != null => (
        'Missed: eat it another time${frozen ? '' : ' or freeze it'}',
        true,
      ),
      _ =>
        frozen
            ? ('In the freezer, best by ${_day(portion.useBy)}', false)
            : ('In the fridge, use by ${_day(portion.useBy)}', false),
    };
    return ListTile(
      title: Text(recipe.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${portionMeal(portion)} · ${switch (grams) {
              final g? => formatGrams(g.roundToDouble()),
              null => portionsLabel(portion.amount),
            }}',
          ),
          Text(
            status,
            style: text.bodySmall?.copyWith(
              color: warn ? colors.error : colors.textTertiary,
            ),
          ),
        ],
      ),
      trailing: Icon(
        frozen ? Icons.ac_unit : Icons.kitchen_outlined,
        size: 18,
        color: colors.textTertiary,
      ),
      onTap: () => _actions(context, ref),
    );
  }
}

/// One batch: the scaled ingredient list, what it should weigh, its
/// portions, and marking it cooked with its measured weight.
class PrepSessionScreen extends ConsumerStatefulWidget {
  const new({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<PrepSessionScreen> createState() => _PrepSessionScreenState();
}

class _PrepSessionScreenState extends ConsumerState<PrepSessionScreen> {
  final _weight = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _markCooked(PrepSession session, double grams) async {
    setState(() => _busy = true);
    try {
      await ref.read(prepProvider.notifier).markCooked(session, grams);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    PrepSession? session;
    for (final s in ref.watch(prepProvider).value ?? const <PrepSession>[]) {
      if (s.id == widget.sessionId) session = s;
    }
    Recipe? recipe;
    for (final r in [
      ...?ref.watch(recipesProvider).value,
      ...?ref.watch(sharedRecipesProvider).value,
    ]) {
      if (r.id == session?.recipeId) recipe = r;
    }
    final me = ref.watch(currentUserIdProvider);
    final names = {
      for (final m
          in ref.watch(householdProvider).value?.members ??
              const <HouseholdMember>[])
        m.userId: m.displayName,
    };
    // Whose a household portion is, in front of its meal.
    String portionLabel(PrepPortion p) {
      if (!(session?.isShared ?? false) || p.eaterId == null) {
        return portionMeal(p);
      }
      final who = p.eaterId == me ? 'You' : names[p.eaterId] ?? 'Someone';
      return '$who · ${portionMeal(p)}';
    }

    if (session == null || recipe == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(title: 'This batch is no longer planned'),
      );
    }
    final s = session;
    final r = recipe;
    final foods = ref.watch(foodsByIdProvider);
    final method = recipeMethod(
      r,
      ref.watch(recipeLibraryProvider).value ?? const [],
    );
    final expected = expectedCookedWeightG(r, s.portionCount);
    final typed = parseDecimal(_weight.text);
    final valid = typed != null && typed > 0 && typed < 50000;
    final warning = valid ? sessionWeightWarning(r, s, typed) : null;

    return Scaffold(
      appBar: AppBar(title: Text(r.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Space.xxl,
        ),
        children: [
          Text(
            s.cooked
                ? 'Cooked ${formatShortDate(s.cookedAt!.toLocal())} · '
                      '${formatGrams(s.cookedWeightG!)}'
                : 'Cook on ${_day(s.cookOn)} · '
                      '${portionsLabel(s.portionCount)} '
                      '(the recipe makes ${r.portions})',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          Text('Ingredients', style: text.titleMedium),
          const SizedBox(height: Space.xs),
          for (final i in scaledIngredients(r, s.portionCount))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                children: [
                  Expanded(child: Text(foods[i.foodId]?.name ?? 'Loading…')),
                  Text(formatGrams(i.rawGrams)),
                ],
              ),
            ),
          if (method != null && method.trim().isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Text('Method', style: text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(method),
          ],
          const SizedBox(height: Space.lg),
          Text('Portions', style: text.titleMedium),
          const SizedBox(height: Space.xs),
          for (final p in s.portions)
            if (p.status != PortionStatus.discarded)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                child: Row(
                  children: [
                    Expanded(child: Text(portionLabel(p))),
                    Text(switch (s.gramsOf(p)) {
                      final g? => formatGrams(g.roundToDouble()),
                      null => portionsLabel(p.amount),
                    }),
                  ],
                ),
              ),
          if (!s.cooked) ...[
            const SizedBox(height: Space.xl),
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Cooked weight of the whole batch',
                suffixText: 'g',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.xs),
            Text(
              warning ??
                  (expected == null
                      ? 'Weigh it in the pot, then take off the pot’s weight.'
                      : 'Expect about '
                            '${formatGrams(expected.roundToDouble())}. Weigh '
                            'it in the pot, then take off the pot’s weight.'),
              style: text.bodySmall?.copyWith(
                color: warning != null ? colors.error : colors.textTertiary,
              ),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: valid && !_busy ? () => _markCooked(s, typed) : null,
              child: const Text('Mark cooked'),
            ),
          ],
        ],
      ),
    );
  }
}
