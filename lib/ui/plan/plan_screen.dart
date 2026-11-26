import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/meal_rules/meal_rules_notifier.dart';
import 'package:trendline/data/plans/household_plan_notifier.dart';
import 'package:trendline/data/plans/plan_notifier.dart';
import 'package:trendline/data/schedule/schedule_notifier.dart';
import 'package:trendline/data/setup/setup_status.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/schedule.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/meal_rules/meal_rules_screen.dart';
import 'package:trendline/ui/plan/household_plan_screen.dart';
import 'package:trendline/ui/prep/prep_screen.dart';
import 'package:trendline/ui/setup/setup_checklist.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// "1 portion", "1.25 portions", "250 g".
String planAmount(PlannedItem i) {
  if (!i.isPortions) return formatGrams(i.amount);
  final n = i.amount == i.amount.roundToDouble()
      ? i.amount.toStringAsFixed(0)
      : i.amount.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  return i.amount == 1 ? '1 portion' : '$n portions';
}

const List<MealSlot> _slotOrder = [
  MealSlot.breakfast,
  MealSlot.lunch,
  MealSlot.snack,
  MealSlot.dinner,
];

/// The week's plan: make one, lock what you like, swap, regenerate, save.
class PlanScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  bool _nextWeek = false;
  bool _busy = false;

  DateTime get _weekStart {
    final thisWeek = weekStartOf(DateTime.now());
    return _nextWeek ? addDays(thisWeek, 7) : thisWeek;
  }

  /// Makes the plan, or first shows the setup checklist if something the
  /// plan needs (a weigh-in, say) is missing; planning goes ahead from its
  /// button once it's all done.
  Future<void> _generate(PlanNotifier notifier) async {
    final status = await ref.read(setupStatusProvider.future);
    if (!mounted) return;
    if (!status.canPlan) {
      final go = await showSetupSheet(
        context,
        planLabel: _nextWeek ? 'Plan next week' : 'Plan this week',
      );
      if (go != true || !mounted) return;
    }
    await _run(notifier.generate);
  }

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
    final week = _weekStart;
    final state = ref.watch(planProvider(week));
    final notifier = ref.read(planProvider(week).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          if (ref.watch(householdIdProvider) != null)
            IconButton(
              tooltip: 'Household meals',
              icon: const Icon(Icons.groups_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HouseholdPlanScreen(weekStart: week),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Prep',
            icon: const Icon(Icons.kitchen_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const PrepScreen())),
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: RefreshIndicator(
        // Picks up what other household members changed.
        onRefresh: () async {
          ref.read(householdRefreshProvider)();
          await ref.read(planProvider(week).future);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: Space.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Space.sm,
              ),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('This week')),
                  ButtonSegment(value: true, label: Text('Next week')),
                ],
                selected: {_nextWeek},
                onSelectionChanged: (s) => setState(() => _nextWeek = s.first),
              ),
            ),
            _RulesTile(hasPlan: state.value?.plan != null),
            switch (state) {
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(planProvider(week)),
              ),
              AsyncData(value: PlanState(plan: null)) => Column(
                children: [
                  const EmptyState(
                    title: 'No plan for this week',
                    message:
                        'The planner fills breakfast, lunch and dinner with '
                        'dishes cooked in batches, keeps your meal rules, and '
                        'sizes portions to your targets.',
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _generate(notifier),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      _nextWeek ? 'Plan next week' : 'Plan this week',
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  TextButton(
                    onPressed: () => showSetupSheet(context),
                    child: const Text('Setup checklist'),
                  ),
                ],
              ),
              AsyncData(value: final s) => _PlanView(
                state: s,
                busy: _busy,
                onRegenerate: () => _run(notifier.generate),
                onSave: () => _run(notifier.save),
                onFitShared: () => _run(notifier.fitShared),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(Space.xl),
                child: CenteredProgress(),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// The meal rules the planner keeps, and the way in to change them.
class _RulesTile extends ConsumerWidget {
  const new({required this.hasPlan});

  /// Whether the week has a plan, which only picks up changed rules when
  /// it's regenerated.
  final bool hasPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(mealRulesProvider).value?.length;
    final summary = switch (count) {
      null => 'Things you always or often have',
      0 => 'None yet. Add things you always or often have',
      1 => '1 rule',
      final n => '$n rules',
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      leading: const Icon(Icons.rule),
      title: const Text('Meal rules'),
      subtitle: Text(
        hasPlan && (count ?? 0) > 0
            ? '$summary. Regenerate to use changes'
            : summary,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MealRulesScreen()),
      ),
    );
  }
}

class _PlanView extends ConsumerWidget {
  const new({
    required this.state,
    required this.busy,
    required this.onRegenerate,
    required this.onSave,
    required this.onFitShared,
  });

  final PlanState state;
  final bool busy;
  final VoidCallback onRegenerate;
  final VoidCallback onSave;
  final VoidCallback onFitShared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final plan = state.plan!;
    final targets = state.targets;
    final schedules = ref.watch(scheduleProvider).value ?? fullWeek(const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.saved
                      ? 'Saved'
                      : 'Not saved yet. Lock what you like, then save.',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
              TextButton.icon(
                onPressed: busy ? null : onRegenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('Regenerate'),
              ),
              if (!state.saved)
                FilledButton(
                  onPressed: busy ? null : onSave,
                  child: const Text('Save'),
                ),
            ],
          ),
        ),
        for (final note in plan.notes)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.gutter,
              vertical: Space.xs,
            ),
            child: Text(
              note,
              style: text.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        if (state.saved && state.estimated.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              0,
            ),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'The household’s meals have changed. Your portions of '
                      'the new ones are estimates until they’re fitted to '
                      'your day.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: Space.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: busy ? null : onFitShared,
                        child: const Text('Fit my portions'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (var d = 0; d < 7; d++)
          _Day(
            date: state.dayOf(d),
            items: plan.itemsOn(d),
            total: plan.totalOn(d),
            targets: targets?[d],
            schedule: schedules[state.dayOf(d).weekday - 1],
            weekStart: state.weekStart,
            leftovers: {
              for (final (day, slot, key) in state.leftovers)
                if (day == d) (slot, key),
            },
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const new({
    required this.date,
    required this.items,
    required this.total,
    required this.targets,
    required this.schedule,
    required this.weekStart,
    this.leftovers = const {},
  });

  /// Items (by meal and key) that eat up a leftover portion.
  final Set<(MealSlot, String)> leftovers;
  final DateTime date;
  final List<PlannedItem> items;
  final Nutrition total;
  final PlanTargets? targets;
  final DaySchedule schedule;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final times = mealTimes(schedule);
    final kcal = total.kcal;
    final protein = total.proteinG;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEE d MMM').format(date),
                  style: text.titleMedium,
                ),
              ),
              Text(
                targets == null
                    ? '${formatKcal(kcal)} kcal'
                    : '${formatKcal(kcal)} / ${formatKcal(targets!.kcal)} kcal'
                          ' · P ${protein.round()} g',
                style: text.labelMedium?.tabular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const Divider(),
          for (final slot in _slotOrder)
            for (final i in items.where((i) => i.slot == slot))
              _ItemRow(
                item: i,
                time: formatClock(times[slot]!),
                weekStart: weekStart,
                leftover: leftovers.contains((i.slot, i.key)),
              ),
        ],
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const new({
    required this.item,
    required this.time,
    required this.weekStart,
    this.leftover = false,
  });

  /// It eats up a leftover portion already cooked.
  final bool leftover;
  final PlannedItem item;
  final String time;
  final DateTime weekStart;

  /// A household dish: chosen together, so it's changed in the household's
  /// week; only its amount is the user's, fitted when they plan.
  Future<void> _sharedInfo(BuildContext context) async {
    final open = await showAppSheet<bool>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleLarge),
          Text(planAmount(item)),
          const SizedBox(height: Space.sm),
          const Text(
            'Shared with your household. Change the dish in Household '
            'meals; your portion is fitted to your day when you plan.',
          ),
          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('Household meals'),
          ),
        ],
      ),
    );
    if (open == true && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HouseholdPlanScreen(weekStart: weekStart),
        ),
      );
    }
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    if (item.shared) {
      await _sharedInfo(context);
      return;
    }
    final notifier = ref.read(planProvider(weekStart).notifier);
    final action = await showAppSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleLarge),
          Text(planAmount(item)),
          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('lock'),
            icon: Icon(item.locked ? Icons.lock_open : Icons.lock_outline),
            label: Text(
              item.locked ? 'Unlock' : 'Lock (keep when regenerating)',
            ),
          ),
          if (item.isDish) ...[
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop('swap'),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Swap for another dish'),
            ),
          ],
          const SizedBox(height: Space.sm),
          TextButton(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: const Text('Remove from the plan'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'lock':
        notifier.toggleLock(item);
      case 'remove':
        notifier.remove(item);
      case 'swap':
        final options = await notifier.swapOptions(item.slot);
        if (!context.mounted) return;
        final choice = await showAppSheet<DishCandidate>(
          context,
          builder: (context) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    leading: o.favourite
                        ? const Icon(Icons.star, semanticLabel: 'Favourite')
                        : null,
                    title: Text(o.name),
                    trailing: Text('${formatKcal(o.perPortion.kcal)} kcal'),
                    onTap: () => Navigator.of(context).pop(o),
                  ),
              ],
            ),
          ),
        );
        if (choice != null) notifier.swap(item, choice);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return InkWell(
      onTap: () => _actions(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                time,
                style: text.labelMedium?.tabular.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: text.bodyMedium),
                  Text(
                    '${leftover ? 'Leftover · ' : ''}${planAmount(item)} · '
                    '${formatKcal(item.nutrition.kcal)} kcal',
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (item.shared)
              Tooltip(
                message: 'Shared with your household',
                child: Icon(
                  Icons.groups_outlined,
                  size: 16,
                  color: colors.textTertiary,
                ),
              )
            else if (item.locked)
              Icon(Icons.lock, size: 16, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}
