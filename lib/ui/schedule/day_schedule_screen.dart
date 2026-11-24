import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/schedule/schedule_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/schedule.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "Breakfast 07:30 · Lunch 13:45 · Snacks 17:00 · Dinner 20:00"
String mealTimesSummary(DaySchedule s) {
  final times = mealTimes(s);
  return [
    for (final slot in const [
      MealSlot.breakfast,
      MealSlot.lunch,
      MealSlot.snack,
      MealSlot.dinner,
    ])
      '${mealSlotLabel(slot)} ${formatClock(times[slot]!)}',
  ].join(' · ');
}

/// Wake and sleep times for each weekday, and the meal times they give.
class DayScheduleScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(scheduleProvider);
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Day schedule')),
      body: switch (week) {
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(scheduleProvider),
        ),
        AsyncLoading() when week.value == null => const CenteredProgress(),
        _ => ListView(
          padding: const EdgeInsets.only(bottom: Space.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Text(
                'Meal times follow from when you wake and go to sleep. '
                'Sleep can be after midnight.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
            for (final day in week.value!)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                ),
                title: Text(
                  '${_weekdays[day.weekday - 1]}   '
                  '${formatClock(day.wakeMinute)}–'
                  '${formatClock(day.sleepMinute)}',
                  style: text.bodyLarge?.tabular,
                ),
                subtitle: Text(mealTimesSummary(day)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAppSheet<void>(
                  context,
                  builder: (_) => _DaySheet(day: day),
                ),
              ),
          ],
        ),
      },
    );
  }
}

enum _ApplyTo { thisDay, weekdays, weekend, everyDay }

class _DaySheet extends ConsumerStatefulWidget {
  const new({required this.day});

  final DaySchedule day;

  @override
  ConsumerState<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<_DaySheet> {
  late int _wake = widget.day.wakeMinute;
  late int _sleep = widget.day.sleepMinute;
  _ApplyTo _applyTo = _ApplyTo.thisDay;
  bool _saving = false;

  Future<void> _pick({required bool wake}) async {
    final current = wake ? _wake : _sleep;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      initialEntryMode: TimePickerEntryMode.input,
      helpText: wake ? 'Wake up' : 'Go to sleep',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final minute = picked.hour * 60 + picked.minute;
      if (wake) {
        _wake = minute;
      } else {
        _sleep = minute;
      }
    });
  }

  List<int> get _days => switch (_applyTo) {
    _ApplyTo.thisDay => [widget.day.weekday],
    _ApplyTo.weekdays => [1, 2, 3, 4, 5],
    _ApplyTo.weekend => [6, 7],
    _ApplyTo.everyDay => [1, 2, 3, 4, 5, 6, 7],
  };

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(scheduleProvider.notifier).save([
        for (final d in _days)
          DaySchedule(weekday: d, wakeMinute: _wake, sleepMinute: _sleep),
      ]);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final draft = DaySchedule(
      weekday: widget.day.weekday,
      wakeMinute: _wake,
      sleepMinute: _sleep,
    );
    final problem = validateSchedule(draft);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_weekdays[widget.day.weekday - 1], style: text.titleLarge),
        const SizedBox(height: Space.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wake up'),
          trailing: Text(formatClock(_wake), style: text.titleMedium?.tabular),
          onTap: () => _pick(wake: true),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Go to sleep'),
          trailing: Text(formatClock(_sleep), style: text.titleMedium?.tabular),
          onTap: () => _pick(wake: false),
        ),
        const SizedBox(height: Space.sm),
        Text(
          problem ?? mealTimesSummary(draft),
          style: text.bodySmall?.copyWith(
            color: problem == null ? colors.textSecondary : colors.error,
          ),
        ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final (option, label) in const [
              (_ApplyTo.thisDay, 'This day'),
              (_ApplyTo.weekdays, 'Weekdays'),
              (_ApplyTo.weekend, 'Weekend'),
              (_ApplyTo.everyDay, 'Every day'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _applyTo == option,
                onSelected: (_) => setState(() => _applyTo = option),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        FilledButton(
          onPressed: _saving || problem != null ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
