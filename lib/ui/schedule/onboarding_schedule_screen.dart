import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/schedule/schedule_notifier.dart';
import 'package:trendline/domain/schedule.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/schedule/day_schedule_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// The last onboarding step, after the goal: when the user wakes and goes
/// to sleep on weekdays and at the weekend, which sets their meal times.
///
/// Optional: skipping leaves the standard 07:00–23:00 day standing in, and
/// the setup checklist keeps offering it. Single days are changed later in
/// Settings → Day schedule.
class OnboardingScheduleScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OnboardingScheduleScreen> createState() =>
      _OnboardingScheduleScreenState();
}

class _OnboardingScheduleScreenState
    extends ConsumerState<OnboardingScheduleScreen> {
  static const _weekdays = [1, 2, 3, 4, 5];
  static const _weekend = [6, 7];

  ({int wake, int sleep}) _weekdayTimes = (wake: 7 * 60, sleep: 23 * 60);
  ({int wake, int sleep}) _weekendTimes = (wake: 8 * 60, sleep: 23 * 60);
  bool _saving = false;

  DaySchedule _day(int weekday, ({int wake, int sleep}) times) => DaySchedule(
    weekday: weekday,
    wakeMinute: times.wake,
    sleepMinute: times.sleep,
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(scheduleProvider.notifier).save([
        for (final d in _weekdays) _day(d, _weekdayTimes),
        for (final d in _weekend) _day(d, _weekendTimes),
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
    final weekday = _day(1, _weekdayTimes);
    final weekend = _day(6, _weekendTimes);
    final ok =
        validateSchedule(weekday) == null && validateSchedule(weekend) == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your day'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Space.xxl,
        ),
        children: [
          Text(
            'Plans put meals at times that suit your day: breakfast soon '
            'after you wake, dinner a few hours before you sleep. Sleep can '
            'be after midnight.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          _TimesCard(
            title: 'Weekdays',
            day: weekday,
            onChanged: (t) => setState(() => _weekdayTimes = t),
          ),
          const SizedBox(height: Space.md),
          _TimesCard(
            title: 'Weekend',
            day: weekend,
            onChanged: (t) => setState(() => _weekendTimes = t),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'You can set single days later in Settings → Day schedule.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: ok && !_saving ? _save : null,
            child: const Text('Continue'),
          ),
          const SizedBox(height: Space.sm),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Skip: use 07:00–23:00 for now'),
          ),
        ],
      ),
    );
  }
}

/// Wake and sleep times for a group of days, with the meal times they give
/// (or what's wrong with them).
class _TimesCard extends StatelessWidget {
  const new({
    required this.title,
    required this.day,
    required this.onChanged,
  });

  final String title;
  final DaySchedule day;
  final ValueChanged<({int wake, int sleep})> onChanged;

  Future<void> _pick(BuildContext context, {required bool wake}) async {
    final current = wake ? day.wakeMinute : day.sleepMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      initialEntryMode: TimePickerEntryMode.input,
      helpText: '$title: ${wake ? 'wake up' : 'go to sleep'}',
    );
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    onChanged(
      wake
          ? (wake: minute, sleep: day.sleepMinute)
          : (wake: day.wakeMinute, sleep: minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final problem = validateSchedule(day);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wake up'),
              trailing: Text(
                formatClock(day.wakeMinute),
                style: text.titleMedium?.tabular,
              ),
              onTap: () => _pick(context, wake: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Go to sleep'),
              trailing: Text(
                formatClock(day.sleepMinute),
                style: text.titleMedium?.tabular,
              ),
              onTap: () => _pick(context, wake: false),
            ),
            Text(
              problem ?? mealTimesSummary(day),
              style: text.bodySmall?.copyWith(
                color: problem == null ? colors.textSecondary : colors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
