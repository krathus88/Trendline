import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/sharing/sharing_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/sharing.dart';
import 'package:trendline/domain/trend.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/progress/trend_chart.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

/// What someone shares with the user, read-only.
class SharedViewScreen extends ConsumerWidget {
  const new({required this.share, super.key});

  final Share share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The latest version of this share (the owner may have changed it).
    final current = ref
        .watch(sharingProvider)
        .value
        ?.incoming
        .where((s) => s.id == share.id)
        .firstOrNull;
    final s = current ?? share;
    final unit = ref.watch(profileProvider).value?.weightUnit ?? WeightUnit.kg;

    Future<void> refresh() async {
      ref
        ..invalidate(sharingProvider)
        ..invalidate(viewedWeighInsProvider(s.ownerId))
        ..invalidate(viewedTargetsProvider(s.ownerId))
        ..invalidate(viewedPlanProvider);
      await ref.read(sharingProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.ownerName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
          IconButton(
            tooltip: 'Stop viewing',
            icon: const Icon(Icons.visibility_off_outlined),
            onPressed: () async {
              final navigator = Navigator.of(context);
              try {
                await ref.read(sharingProvider.notifier).end(s);
                navigator.pop();
              } on Object catch (e) {
                if (context.mounted) showErrorSnack(context, e);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xxl,
          ),
          children: [
            if (current == null && ref.watch(sharingProvider).hasValue)
              const EmptyState(title: 'This share has ended')
            else if (s.kinds.isEmpty)
              const EmptyState(
                title: 'Nothing shared right now',
                message: 'They can switch things back on at any time.',
              )
            else ...[
              Text(
                'Read-only: you can see this, not change it.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.colors.textTertiary),
              ),
              if (s.includes(ShareKind.weight))
                _WeightSection(ownerId: s.ownerId, unit: unit),
              if (s.includes(ShareKind.targets))
                _TargetsSection(ownerId: s.ownerId),
              if (s.includes(ShareKind.plans)) _PlanSection(ownerId: s.ownerId),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium),
  );
}

Widget _loading<T>(
  AsyncValue<T> value,
  VoidCallback retry,
  Widget Function(T data) data,
) => switch (value) {
  AsyncError(:final error) => ErrorView(error: error, onRetry: retry),
  AsyncLoading() when !value.hasValue => const Padding(
    padding: EdgeInsets.all(Space.lg),
    child: CenteredProgress(),
  ),
  _ => data(value.value as T),
};

class _WeightSection extends ConsumerWidget {
  const new({required this.ownerId, required this.unit});

  final String ownerId;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weighIns = ref.watch(viewedWeighInsProvider(ownerId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(ShareKind.weight.label),
        _loading(
          weighIns,
          () => ref.invalidate(viewedWeighInsProvider(ownerId)),
          (list) {
            final trend = computeTrend(list, until: DateTime.now());
            if (trend.length < 2) {
              return const EmptyState(
                title: 'Not enough data yet',
                message: 'The chart appears after two days of weigh-ins.',
              );
            }
            final week = weeklyTrendChangeKg(trend);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    'Trend ${formatWeight(trend.last.trendKg, unit)}',
                    if (week != null)
                      '${formatWeightChange(week, unit)} a week',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.sm),
                SizedBox(
                  height: 220,
                  child: TrendChart(points: trend, unit: unit),
                ),
                Text(
                  'Last $sharedWeightDays days',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.colors.textTertiary),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TargetsSection extends ConsumerWidget {
  const new({required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(viewedTargetsProvider(ownerId));
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(ShareKind.targets.label),
        _loading(
          targets,
          () => ref.invalidate(viewedTargetsProvider(ownerId)),
          (t) {
            if (t == null) {
              return const EmptyState(
                title: 'Not available yet',
                message:
                    'They appear once their app has opened since sharing '
                    'started.',
              );
            }
            Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: text.bodyMedium)),
                  Text(value, style: text.bodyMedium?.tabular),
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('Calories', '${formatKcal(t.kcal)} kcal'),
                row('Protein (at least)', formatGrams(t.proteinG)),
                row('Carbs', formatGrams(t.carbsG)),
                row('Fat', formatGrams(t.fatG)),
                row('Fibre (at least)', formatGrams(t.fibreG)),
                if (t.updatedAt != null)
                  Text(
                    'Updated ${formatDateTime(t.updatedAt!)}',
                    style: text.bodySmall?.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// How far back and ahead the shared plan's weeks go from this week.
const _earliestWeek = -8;
const _latestWeek = 1;

/// "This week", "Next week", "Last week", or "Week of 7 Dec".
String sharedWeekLabel(int offset, DateTime weekStart) => switch (offset) {
  0 => 'This week',
  1 => 'Next week',
  -1 => 'Last week',
  _ => 'Week of ${DateFormat('d MMM').format(weekStart)}',
};

class _PlanSection extends ConsumerStatefulWidget {
  const new({required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<_PlanSection> createState() => _PlanSectionState();
}

class _PlanSectionState extends ConsumerState<_PlanSection> {
  /// Weeks from this week.
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final week = addDays(weekStartOf(dayOf(DateTime.now())), 7 * _offset);
    final key = (widget.ownerId, week);
    final plan = ref.watch(viewedPlanProvider(key));
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionTitle('Meal plan')),
            IconButton(
              tooltip: 'Previous week',
              icon: const Icon(Icons.chevron_left),
              onPressed: _offset > _earliestWeek
                  ? () => setState(() => _offset--)
                  : null,
            ),
            Text(sharedWeekLabel(_offset, week), style: text.labelLarge),
            IconButton(
              tooltip: 'Next week',
              icon: const Icon(Icons.chevron_right),
              onPressed: _offset < _latestWeek
                  ? () => setState(() => _offset++)
                  : null,
            ),
          ],
        ),
        _loading(plan, () => ref.invalidate(viewedPlanProvider(key)), (items) {
          if (items.isEmpty) {
            return const EmptyState(title: 'No plan saved for that week');
          }
          final days = <DateTime, List<SharedPlanItem>>{};
          for (final i in items) {
            (days[i.day] ??= []).add(i);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final MapEntry(key: day, value: list) in days.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: Space.md,
                    bottom: Space.xs,
                  ),
                  child: Text(
                    '${formatDayLabel(day)} · ${formatKcal(_kcal(list))} kcal',
                    style: text.titleSmall,
                  ),
                ),
                for (final i in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            mealSlotLabel(i.slot),
                            style: text.bodySmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                        Expanded(child: Text(i.name, style: text.bodyMedium)),
                        Text(
                          '${_amount(i)} · ${formatKcal(i.kcal)} kcal',
                          style: text.bodySmall?.tabular,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        }),
      ],
    );
  }

  static double _kcal(List<SharedPlanItem> items) =>
      items.fold(0, (sum, i) => sum + i.kcal);

  static String _amount(SharedPlanItem i) {
    if (!i.isRecipe) return formatGrams(i.amount);
    final portions = (i.amount * 100).round() / 100;
    final shown = portions == portions.roundToDouble()
        ? portions.toStringAsFixed(0)
        : portions.toString();
    return portions == 1 ? '1 portion' : '$shown portions';
  }
}
