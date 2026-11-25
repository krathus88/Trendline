import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/plans/household_plan_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// Portions as shown in a list of servings: "1", "1.25".
String _portions(double amount) => amount == amount.roundToDouble()
    ? amount.toStringAsFixed(0)
    : amount.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

/// "Bea 1.25", or "Bea ~1.25" while it's an estimate she hasn't fitted.
String _serving(String who, double amount, {required bool estimated}) =>
    '$who ${estimated ? '~' : ''}${_portions(amount)}';

/// The household's shared meals for a week: chosen together, cooked once,
/// with each member's portions.
class HouseholdPlanScreen extends ConsumerStatefulWidget {
  const new({required this.weekStart, super.key});

  final DateTime weekStart;

  @override
  ConsumerState<HouseholdPlanScreen> createState() =>
      _HouseholdPlanScreenState();
}

class _HouseholdPlanScreenState extends ConsumerState<HouseholdPlanScreen> {
  Set<MealSlot> _meals = {MealSlot.dinner};
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(householdPlanProvider(widget.weekStart));
    final notifier = ref.read(householdPlanProvider(widget.weekStart).notifier);
    final household = ref.watch(householdProvider).value;
    final me = ref.watch(currentUserIdProvider);
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final names = {
      for (final m in household?.members ?? const <HouseholdMember>[])
        m.userId: m.displayName,
    };

    Widget mealChooser() => Wrap(
      spacing: Space.sm,
      children: [
        for (final slot in [
          MealSlot.breakfast,
          MealSlot.lunch,
          MealSlot.dinner,
        ])
          FilterChip(
            label: Text(mealSlotLabel(slot)),
            selected: _meals.contains(slot),
            onSelected: (on) => setState(
              () =>
                  _meals = on ? {..._meals, slot} : ({..._meals}..remove(slot)),
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Household · week of ${DateFormat('d MMM').format(widget.weekStart)}',
        ),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: switch (state) {
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () =>
              ref.invalidate(householdPlanProvider(widget.weekStart)),
        ),
        AsyncLoading() when !state.hasValue => const CenteredProgress(),
        _ => RefreshIndicator(
          onRefresh: () async {
            notifier.refresh();
            await ref.read(householdPlanProvider(widget.weekStart).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Space.xxl,
            ),
            children: [
              Text(
                'Shared meals are planned for everyone and cooked once, with '
                'everyone’s likes and dislikes in mind (anything someone never '
                'wants is left out). Each person’s portion is fitted to their '
                'own day when they plan their week, so nobody’s targets are '
                'shared: only portion sizes. ~ marks a portion not fitted yet. '
                'Planning again keeps the portions of dishes that stay.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: Space.md),
              Text('Meals to share', style: text.labelMedium),
              mealChooser(),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.value!.dishes.isEmpty
                          ? 'No shared meals this week'
                          : state.value!.saved
                          ? 'Saved'
                          : 'Not saved yet',
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy || _meals.isEmpty
                        ? null
                        : () => _run(() => notifier.generate(meals: _meals)),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      state.value!.dishes.isEmpty
                          ? 'Plan shared meals'
                          : 'Plan again',
                    ),
                  ),
                  if (!state.value!.saved && state.value!.dishes.isNotEmpty)
                    FilledButton(
                      onPressed: _busy ? null : () => _run(notifier.save),
                      child: const Text('Save'),
                    ),
                ],
              ),
              for (final note in state.value!.notes)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    note,
                    style: text.bodySmall?.copyWith(color: colors.error),
                  ),
                ),
              for (var d = 0; d < 7; d++)
                if (state.value!.dishes.where((x) => x.day == d).toList()
                    case final dishes when dishes.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: Space.lg),
                    child: Text(
                      DateFormat('EEE d MMM')
                          .format(addDays(widget.weekStart, d)),
                      style: text.titleMedium,
                    ),
                  ),
                  const Divider(),
                  for (final dish in dishes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(dish.name),
                      subtitle: Text(
                        [
                          mealSlotLabel(dish.slot),
                          for (final MapEntry(key: eater, value: amount)
                              in dish.amounts.entries)
                            _serving(
                              eater == me ? 'You' : names[eater] ?? 'Someone',
                              amount,
                              estimated: dish.estimated.contains(eater),
                            ),
                        ].join(' · '),
                      ),
                      trailing: Text(
                        '${formatKcal(dish.perPortion.kcal)} kcal\nper portion',
                        textAlign: TextAlign.end,
                        style: text.labelSmall?.tabular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      onLongPress: state.value!.saved
                          ? null
                          : () => notifier.remove(dish),
                    ),
                ],
            ],
          ),
        ),
      },
    );
  }
}
