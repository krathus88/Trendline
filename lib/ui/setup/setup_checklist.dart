import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/setup/setup_status.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/goals/goal_screen.dart';
import 'package:trendline/ui/meal_rules/meal_rules_screen.dart';
import 'package:trendline/ui/preferences/food_preferences_screen.dart';
import 'package:trendline/ui/profile/profile_form_screen.dart';
import 'package:trendline/ui/progress/weigh_in_sheet.dart';
import 'package:trendline/ui/schedule/day_schedule_screen.dart';
import 'package:trendline/ui/settings/health_connect_sheet.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Opens the setup checklist in a sheet. With [planLabel], the sheet ends
/// with a button of that label once planning can run, and returns true if
/// it was pressed.
Future<bool?> showSetupSheet(BuildContext context, {String? planLabel}) =>
    showAppSheet<bool>(
      context,
      builder: (_) => _SetupSheet(planLabel: planLabel),
    );

class _SetupSheet extends ConsumerWidget {
  const new({required this.planLabel});

  final String? planLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final status = ref.watch(setupStatusProvider).value;
    final label = planLabel;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Set up planning', style: text.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            status == null || status.canPlan
                ? 'Everything needed is done. The rest make plans fit you '
                      'better.'
                : 'Plans are sized to your targets, so the steps marked '
                      '“Needed” come first. The rest make plans fit you '
                      'better.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.md),
          if (status == null)
            const CenteredProgress()
          else
            SetupChecklist(status: status),
          if (label != null) ...[
            const SizedBox(height: Space.lg),
            FilledButton(
              onPressed: status?.canPlan ?? false
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: Text(label),
            ),
          ],
        ],
      ),
    );
  }
}

/// On Today while planning can't run yet: what's done and what's left.
class SetupCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(setupStatusProvider).value;
    if (status == null || status.canPlan) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Finish setting up', style: text.titleMedium),
              const SizedBox(height: Space.xs),
              Text(
                '${status.doneCount} of ${status.steps.length} done. Your '
                'targets and plans need the steps marked “Needed”.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.sm),
              SetupChecklist(status: status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every setup step with a tick when done; tapping one opens where it's
/// done (done ones too, to change them).
class SetupChecklist extends ConsumerWidget {
  const new({required this.status, super.key});

  final SetupStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Column(
      children: [
        for (final step in status.steps)
          _StepTile(
            step: step,
            done: status.isDone(step),
            text: text,
            colors: colors,
            onTap: () => _open(context, ref, step),
          ),
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, SetupStep step) {
    Future<void> push(Widget screen) =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => screen));
    return switch (step) {
      SetupStep.profile => push(
        ProfileFormScreen(existing: ref.read(profileProvider).value),
      ),
      SetupStep.goal => push(
        GoalScreen(existing: ref.read(goalProvider).value),
      ),
      SetupStep.weighIn => showAppSheet<void>(
        context,
        builder: (_) => WeighInSheet(
          unit: ref.read(profileProvider).value?.weightUnit ?? WeightUnit.kg,
        ),
      ),
      SetupStep.daySchedule => push(const DayScheduleScreen()),
      SetupStep.mealRules => push(const MealRulesScreen()),
      SetupStep.foodPreferences => push(const FoodPreferencesScreen()),
      SetupStep.healthConnect => showAppSheet<void>(
        context,
        builder: (_) => const HealthConnectSheet(),
      ),
    };
  }
}

class _StepTile extends StatelessWidget {
  const new({
    required this.step,
    required this.done,
    required this.text,
    required this.colors,
    required this.onTap,
  });

  final SetupStep step;
  final bool done;
  final TextTheme text;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (title, why) = _copy(step);
    final needed = step.isRequired && !done;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done
            ? colors.accent
            : needed
            ? colors.warning
            : colors.textTertiary,
      ),
      title: Text(title),
      subtitle: Text(why, style: text.bodySmall),
      trailing: needed
          ? Text(
              'Needed',
              style: text.labelSmall?.copyWith(color: colors.warning),
            )
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

(String, String) _copy(SetupStep step) => switch (step) {
  SetupStep.profile => ('Profile', 'Age, height and sex, for your energy use'),
  SetupStep.goal => ('Goal', 'Lose, maintain or gain, and how fast'),
  SetupStep.weighIn => (
    'First weigh-in',
    'Your targets start from your weight',
  ),
  SetupStep.daySchedule => (
    'Day schedule',
    'When you wake and sleep. Until set, a 07:00–23:00 day',
  ),
  SetupStep.mealRules => (
    'Meal rules',
    'Things you always have, like a morning coffee',
  ),
  SetupStep.foodPreferences => (
    'Food preferences',
    'Likes, dislikes and foods to never plan',
  ),
  SetupStep.healthConnect => (
    'Health Connect',
    'Import weigh-ins from your scale’s app',
  ),
};
