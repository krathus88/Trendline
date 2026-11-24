import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/energy/day_complete_notifier.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/data/goals/targets_provider.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/food_picker_screen.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/food/portion_sheet.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// A day's food log, by meal, against the day's targets. The plan
/// arrives in a later milestone.
class TodayScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  DateTime _day = dayOf(DateTime.now());

  bool get _isToday => _day == dayOf(DateTime.now());

  void _move(int days) => setState(() => _day = addDays(_day, days));

  Future<void> _add(MealSlot slot) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => FoodPickerScreen(day: _day, slot: slot),
    ),
  );

  Future<void> _edit(FoodLogEntry entry) async {
    final per100g = entry.grams <= 0
        ? Nutrition.zero
        : Nutrition(
            kcal: entry.nutrition.kcal * 100 / entry.grams,
            proteinG: entry.nutrition.proteinG * 100 / entry.grams,
            carbsG: entry.nutrition.carbsG * 100 / entry.grams,
            fatG: entry.nutrition.fatG * 100 / entry.grams,
            fibreG: entry.nutrition.fibreG * 100 / entry.grams,
            fibreUnknown: entry.nutrition.fibreUnknown,
          );
    final result = await showAppSheet<PortionResult>(
      context,
      builder: (_) => PortionSheet(
        title: entry.foodName,
        subtitle: entry.foodBrand,
        per100g: per100g,
        initialGrams: entry.grams,
        actionLabel: 'Save',
        allowDelete: true,
      ),
    );
    if (!mounted || result == null) return;

    final log = ref.read(foodLogProvider(_day).notifier);
    try {
      switch (result) {
        case PortionGrams(:final grams):
          await log.updateGrams(entry, grams);
        case PortionDelete():
          await log.delete(entry.id);
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(foodLogProvider(_day));

    return Scaffold(
      appBar: AppBar(
        title: Text(formatDayLabel(_day)),
        actions: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => _move(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: _isToday ? null : () => _move(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: switch (log) {
        AsyncError(:final error) when log.value == null => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(foodLogProvider(_day)),
        ),
        AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => ref.refresh(foodLogProvider(_day).future),
          child: _DayLog(
            day: _day,
            entries: value,
            targets: ref.watch(targetsProvider).value?.targets,
            onAdd: _add,
            onEdit: _edit,
          ),
        ),
        _ => const CenteredProgress(),
      },
    );
  }
}

class _DayLog extends StatelessWidget {
  const new({
    required this.day,
    required this.entries,
    required this.targets,
    required this.onAdd,
    required this.onEdit,
  });

  final DateTime day;
  final List<FoodLogEntry> entries;
  final DailyTargets? targets;
  final ValueChanged<MealSlot> onAdd;
  final ValueChanged<FoodLogEntry> onEdit;

  @override
  Widget build(BuildContext context) {
    final total = Nutrition.sum(entries.map((e) => e.nutrition));
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        _Totals(total: total, targets: targets),
        for (final slot in MealSlot.values)
          _SlotSection(
            slot: slot,
            entries: [
              for (final e in entries)
                if (e.slot == slot) e,
            ],
            onAdd: () => onAdd(slot),
            onEdit: onEdit,
          ),
        const SizedBox(height: Space.xl),
        _DayComplete(day: day),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const new({required this.total, required this.targets});

  final Nutrition total;

  /// Null until there's a goal and a weigh-in.
  final DailyTargets? targets;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final t = targets;

    if (t == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Eaten', style: text.bodySmall),
              const SizedBox(height: Space.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatKcal(total.kcal),
                    style: text.displaySmall?.tabular,
                  ),
                  const SizedBox(width: Space.sm),
                  Text('kcal', style: text.bodySmall),
                ],
              ),
              const SizedBox(height: Space.md),
              MacroLine(total),
              const SizedBox(height: Space.md),
              Text(
                'Add a weigh-in to see your targets.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    final left = t.kcal - total.kcal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        left >= 0 ? 'Left today' : 'Over today',
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        formatKcal(left.abs()),
                        style: text.displaySmall?.tabular.copyWith(
                          color: left >= 0
                              ? colors.textPrimary
                              : colors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${formatKcal(total.kcal)} / ${formatKcal(t.kcal)} kcal',
                  style: text.bodySmall?.tabular.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            _Bar(value: total.kcal, target: t.kcal, color: colors.accent),
            const SizedBox(height: Space.lg),
            _MacroBar(
              label: 'Protein',
              value: total.proteinG,
              target: t.proteinG,
              color: colors.protein,
              atLeast: true,
            ),
            _MacroBar(
              label: 'Carbs',
              value: total.carbsG,
              target: t.carbsG,
              color: colors.carbs,
            ),
            _MacroBar(
              label: 'Fat',
              value: total.fatG,
              target: t.fatG,
              color: colors.fat,
            ),
            _MacroBar(
              label: 'Fibre',
              value: total.fibreG,
              target: t.fibreG,
              color: colors.fibre,
              atLeast: true,
              valueIsMinimum: total.fibreUnknown,
            ),
            if (total.fibreUnknown)
              Text(
                'Some of today’s foods have no fibre figure, so the real '
                'amount is likely higher.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const new({required this.value, required this.target, required this.color});

  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: LinearProgressIndicator(
      value: target <= 0 ? 0 : (value / target).clamp(0, 1),
      minHeight: 6,
      color: color,
      backgroundColor: context.colors.surfaceMuted,
    ),
  );
}

class _MacroBar extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
    this.atLeast = false,
    this.valueIsMinimum = false,
  });

  final String label;
  final double value;
  final double target;
  final Color color;

  /// A minimum to reach (protein, fibre) rather than a budget.
  final bool atLeast;

  /// The value leaves out foods with no figure for this nutrient, so the
  /// real amount is at least this.
  final bool valueIsMinimum;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final goal = atLeast
        ? 'at least ${target.round()} g'
        : '${target.round()} g';
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: text.labelMedium)),
              Text(
                '${valueIsMinimum ? '≥' : ''}${value.round()} / $goal',
                style: text.labelMedium?.tabular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          _Bar(value: value, target: target, color: color),
        ],
      ),
    );
  }
}

/// Marks the day as fully logged. Only complete days teach the app the
/// user's real energy use.
class _DayComplete extends ConsumerWidget {
  const new({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = dayCompleteProvider(dayOf(day));
    final complete = ref.watch(provider).value ?? false;
    final text = Theme.of(context).textTheme;
    return Card(
      child: SwitchListTile(
        value: complete,
        title: const Text('Everything eaten is logged'),
        subtitle: Text(
          'Only fully logged days are used to learn your real calorie burn.',
          style: text.bodySmall,
        ),
        onChanged: (v) async {
          try {
            await ref.read(provider.notifier).set(complete: v);
          } on Object catch (e) {
            if (context.mounted) showErrorSnack(context, e);
          }
        },
      ),
    );
  }
}

class _SlotSection extends StatelessWidget {
  const new({
    required this.slot,
    required this.entries,
    required this.onAdd,
    required this.onEdit,
  });

  final MealSlot slot;
  final List<FoodLogEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<FoodLogEntry> onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final kcal = entries.fold<double>(0, (sum, e) => sum + e.nutrition.kcal);

    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(mealSlotLabel(slot), style: text.titleMedium),
              ),
              if (entries.isNotEmpty)
                Text(
                  '${formatKcal(kcal)} kcal',
                  style: text.labelMedium?.tabular.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
          for (final e in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                e.foodName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [formatGrams(e.grams), ?e.foodBrand].join(' · '),
                style: text.bodySmall?.tabular,
              ),
              trailing: Text(
                formatKcal(e.nutrition.kcal),
                style: text.bodyMedium?.tabular,
              ),
              onTap: () => onEdit(e),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add food'),
            ),
          ),
        ],
      ),
    );
  }
}
