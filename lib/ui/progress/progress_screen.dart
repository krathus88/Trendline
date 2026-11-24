import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/health/health_sync_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/trend.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/domain/weigh_in.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/progress/energy_card.dart';
import 'package:trendline/ui/progress/trend_chart.dart';
import 'package:trendline/ui/progress/weigh_in_sheet.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/tokens.dart';
import 'package:trendline/ui/theme/typography.dart';

enum _Range {
  month(30, '30 days'),
  quarter(90, '90 days'),
  year(365, '1 year');

  new(this.days, this.label);

  final int days;
  final String label;
}

class ProgressScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  _Range _range = _Range.month;

  WeightUnit get _unit =>
      ref.watch(profileProvider).value?.weightUnit ?? WeightUnit.kg;

  Future<void> _addWeighIn() =>
      showAppSheet<void>(context, builder: (_) => WeighInSheet(unit: _unit));

  Future<void> _delete(WeighIn w) async {
    try {
      await ref.read(weighInsProvider.notifier).delete(w.id);
      if (mounted && w.source == WeighInSource.healthConnect) {
        showMessageSnack(
          context,
          "Deleted. It won't be imported from Health Connect again.",
        );
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  /// Pull to refresh: imports from Health Connect if connected, otherwise
  /// reloads from the server.
  Future<void> _refresh() async {
    final health = ref.read(healthSyncProvider).value;
    try {
      if (health != null && health.connected) {
        await ref.read(healthSyncProvider.notifier).sync();
      }
      await ref.read(weighInsProvider.notifier).reload();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weighIns = ref.watch(weighInsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWeighIn,
        icon: const Icon(Icons.add),
        label: const Text('Weigh-in'),
      ),
      body: switch (weighIns) {
        AsyncData(:final value) when value.isEmpty => const EmptyState(
          title: 'No weigh-ins yet',
          message:
              'Weigh yourself in the morning, after the loo and before '
              'eating, for the most consistent readings.',
        ),
        AsyncData(:final value) => _content(value),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(weighInsProvider),
        ),
        _ => const CenteredProgress(),
      },
    );
  }

  Widget _content(List<WeighIn> weighIns) {
    final trend = ref.watch(trendProvider);
    final today = dayOf(DateTime.now());
    final start = addDays(today, -(_range.days - 1));
    final visible = [
      for (final p in trend)
        if (!p.day.isBefore(start)) p,
    ];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          96, // clear of the floating button
        ),
        children: [
          _Summary(trend: trend, unit: _unit),
          const SizedBox(height: Space.md),
          EnergyCard(
            unit: _unit,
            strengthTraining:
                ref.watch(profileProvider).value?.strengthTraining ?? false,
          ),
          const SizedBox(height: Space.lg),
          SegmentedButton<_Range>(
            segments: [
              for (final r in _Range.values)
                ButtonSegment(value: r, label: Text(r.label)),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            height: 220,
            child: visible.length < 2
                ? const EmptyState(
                    title: 'Not enough data yet',
                    message: 'The chart appears after two days of weigh-ins.',
                  )
                : TrendChart(points: visible, unit: _unit),
          ),
          const SizedBox(height: Space.xl),
          Text('Weigh-ins', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          for (final w in weighIns)
            _WeighInTile(weighIn: w, unit: _unit, onDelete: () => _delete(w)),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const new({required this.trend, required this.unit});

  final List<TrendPoint> trend;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final current = trend.isEmpty ? null : trend.last.trendKg;
    final weekly = weeklyTrendChangeKg(trend);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trend weight', style: text.bodySmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    current == null ? '–' : formatWeight(current, unit),
                    style: text.headlineMedium?.tabular,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Last 7 days', style: text.bodySmall),
                const SizedBox(height: Space.xs),
                Text(
                  weekly == null
                      ? 'Need a week'
                      : formatWeightChange(weekly, unit),
                  style: text.titleMedium?.tabular.copyWith(
                    color: weekly == null
                        ? colors.textTertiary
                        : colors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeighInTile extends StatelessWidget {
  const new({
    required this.weighIn,
    required this.unit,
    required this.onDelete,
  });

  final WeighIn weighIn;
  final WeightUnit unit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final fat = weighIn.bodyFatPct;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        formatWeight(weighIn.weightKg, unit),
        style: text.bodyLarge?.tabular,
      ),
      subtitle: Text(
        [
          formatDateTime(weighIn.measuredAt),
          if (fat != null) '${fat.toStringAsFixed(1)}% body fat',
          if (weighIn.source == WeighInSource.healthConnect) 'Health Connect',
        ].join(' · '),
        style: text.bodySmall?.tabular.copyWith(color: colors.textTertiary),
      ),
      trailing: IconButton(
        tooltip: 'Delete weigh-in',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}
