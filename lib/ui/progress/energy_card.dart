import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/goals/targets_provider.dart';
import 'package:trendline/domain/adaptive_tdee.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/goals/goal_screen.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// The estimated daily burn, how sure the app is of it, and where the goal
/// stands.
class EnergyCard extends ConsumerWidget {
  const new({required this.unit, super.key});

  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(targetsProvider).value;
    if (t == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final e = t.energy;

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
                      Text('Daily burn estimate', style: text.bodySmall),
                      const SizedBox(height: Space.xs),
                      Text(
                        '${formatKcal(e.tdeeKcal)} kcal',
                        style: text.headlineSmall?.tabular,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Target', style: text.bodySmall),
                    const SizedBox(height: Space.xs),
                    Text(
                      '${formatKcal(t.targets.kcal)} kcal',
                      style: text.titleMedium?.tabular,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Text('Confidence', style: text.labelMedium),
                const SizedBox(width: Space.md),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: e.confidence,
                      minHeight: 6,
                      color: colors.accent,
                      backgroundColor: colors.surfaceMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              energyExplanation(e.isLearned, e.lastUpdatedOn, e.lastAttempt),
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const Divider(height: Space.xl),
            Text(goalSummary(t, unit), style: text.bodyMedium),
            for (final n in goalNotes(t.plan, t.targets, unit)) ...[
              const SizedBox(height: Space.xs),
              Text(
                n,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where the estimate comes from and, if it can't learn yet, what's needed.
String energyExplanation(
  bool learned,
  DateTime? updatedOn,
  AdaptiveResult? attempt,
) {
  final source = learned && updatedOn != null
      ? 'Learned from your logging, updated ${formatShortDate(updatedOn)}.'
      : 'From a formula for now.';
  final nudge = switch (attempt?.outcome) {
    AdaptiveOutcome.notEnoughHistory =>
      'Mark days as fully logged for two weeks to start learning your real '
          'burn.',
    AdaptiveOutcome.tooFewCompleteDays =>
      '${attempt!.completeDaysNeeded} more fully logged days in the last '
          '${attempt.windowDays} are needed for the next update.',
    AdaptiveOutcome.tooFewWeighIns =>
      'Weigh in at least 4 times across a week for the next update.',
    _ => null,
  };
  return nudge == null ? source : '$source $nudge';
}

String goalSummary(TodayTargets t, WeightUnit unit) {
  final target = t.plan.targetWeightKg;
  final date = t.projectedDate;
  return switch (t.plan.status) {
    GoalStatus.reached => 'Goal reached. Maintaining.',
    GoalStatus.datePassed => 'Goal date passed. Maintaining.',
    GoalStatus.maintaining => 'Maintaining your weight.',
    GoalStatus.losing when target != null && date != null =>
      '${formatWeight(target, unit)} around ${formatLongDate(date)}, '
          'losing ${formatPace(t.targets.kgPerWeek, unit)}.',
    GoalStatus.losing => 'Losing ${formatPace(t.targets.kgPerWeek, unit)}.',
  };
}
