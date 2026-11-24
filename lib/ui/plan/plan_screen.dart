import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/plans/plan_notifier.dart';
import 'package:trendline/data/schedule/schedule_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/schedule.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
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
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
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
                  onPressed: _busy ? null : () => _run(notifier.generate),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Plan this week'),
                ),
              ],
            ),
            AsyncData(value: final s) => _PlanView(
              state: s,
              busy: _busy,
              onRegenerate: () => _run(notifier.generate),
              onSave: () => _run(notifier.save),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: CenteredProgress(),
            ),
          },
        ],
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
  });

  final PlanState state;
  final bool busy;
  final VoidCallback onRegenerate;
  final VoidCallback onSave;

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
        for (var d = 0; d < 7; d++)
          _Day(
            date: state.dayOf(d),
            items: plan.itemsOn(d),
            total: plan.totalOn(d),
            targets: targets,
            schedule: schedules[state.dayOf(d).weekday - 1],
            weekStart: state.weekStart,
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
  });

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
              ),
        ],
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const new({required this.item, required this.time, required this.weekStart});

  final PlannedItem item;
  final String time;
  final DateTime weekStart;

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
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
                    '${planAmount(item)} · '
                    '${formatKcal(item.nutrition.kcal)} kcal',
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (item.locked)
              Icon(Icons.lock, size: 16, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}
