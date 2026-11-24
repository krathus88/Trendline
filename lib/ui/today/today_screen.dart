import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/food_logs/food_log_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/food/food_picker_screen.dart';
import 'package:trendline/ui/food/nutrition_widgets.dart';
import 'package:trendline/ui/food/portion_sheet.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// A day's food log, by meal. Targets and the plan arrive in later
/// milestones; for now this is logging and totals.
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
          child: _DayLog(entries: value, onAdd: _add, onEdit: _edit),
        ),
        _ => const CenteredProgress(),
      },
    );
  }
}

class _DayLog extends StatelessWidget {
  const new({required this.entries, required this.onAdd, required this.onEdit});

  final List<FoodLogEntry> entries;
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
        _Totals(total: total),
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
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const new({required this.total});

  final Nutrition total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
                Text(formatKcal(total.kcal), style: text.displaySmall?.tabular),
                const SizedBox(width: Space.sm),
                Text('kcal', style: text.bodySmall),
              ],
            ),
            const SizedBox(height: Space.md),
            MacroLine(total),
          ],
        ),
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
