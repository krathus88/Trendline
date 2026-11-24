import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/trend.dart';
import 'package:trendline/domain/units.dart';
import 'package:trendline/ui/common/format.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/typography.dart';

/// Daily readings as faint dots, the smoothed trend as a line. The trend is
/// what matters; the dots show the day-to-day noise around it.
class TrendChart extends StatelessWidget {
  const new({required this.points, required this.unit, super.key});

  /// Already limited to the range being shown, oldest first.
  final List<TrendPoint> points;
  final WeightUnit unit;

  /// Axis values: kg, or pounds for lb and stones users.
  double _axisValue(double kg) => unit == WeightUnit.kg ? kg : kgToLb(kg);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final first = points.first.day;
    double x(DateTime day) => daysBetween(first, day).toDouble();

    final trendSpots = [
      for (final p in points) FlSpot(x(p.day), _axisValue(p.trendKg)),
    ];
    final readingSpots = [
      for (final p in points)
        if (p.weightKg != null) FlSpot(x(p.day), _axisValue(p.weightKg!)),
    ];

    final values = [...trendSpots, ...readingSpots].map((s) => s.y);
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    // Keep at least a 2-unit window so a flat trend doesn't look dramatic.
    final pad = math.max((hi - lo) * 0.15, 1);
    final minY = (lo - pad).floorToDouble();
    final maxY = (hi + pad).ceilToDouble();
    final yInterval = _niceInterval(maxY - minY);
    final maxX = math.max(x(points.last.day), 1).toDouble();
    final xInterval = math.max((maxX / 4).roundToDouble(), 1).toDouble();

    final labelStyle = text.labelSmall?.tabular.copyWith(
      color: colors.textTertiary,
    );

    return LineChart(
      duration: const Duration(milliseconds: 200),
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: yInterval,
              getTitlesWidget: (value, meta) =>
                  value == meta.min || value == meta.max
                  ? const SizedBox.shrink()
                  : SideTitleWidget(
                      meta: meta,
                      child: Text(value.toStringAsFixed(0), style: labelStyle),
                    ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: xInterval,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  formatShortDate(addDays(first, value.round())),
                  style: labelStyle,
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => colors.textPrimary,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            // Must return one item per touched spot (null hides it), so
            // only the trend line gets a tooltip.
            getTooltipItems: (spots) => spots
                .map(
                  (s) => s.barIndex == 1
                      ? LineTooltipItem(
                          '${formatShortDate(addDays(first, s.x.round()))}\n'
                          '${formatWeight(_kgFromAxis(s.y), unit)}',
                          text.labelMedium!.tabular.copyWith(
                            color: colors.background,
                          ),
                        )
                      : null,
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          // 0: daily readings, dots only.
          LineChartBarData(
            spots: readingSpots,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 2.5,
                color: colors.textTertiary.withValues(alpha: 0.5),
                strokeWidth: 0,
              ),
            ),
          ),
          // 1: the trend.
          LineChartBarData(
            spots: trendSpots,
            color: colors.accent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  double _kgFromAxis(double value) =>
      unit == WeightUnit.kg ? value : lbToKg(value);
}

/// A round grid step giving roughly four lines.
double _niceInterval(double range) {
  final raw = range / 4;
  for (final step in [0.5, 1, 2, 5, 10, 20, 50]) {
    if (raw <= step) return step.toDouble();
  }
  return 100;
}
