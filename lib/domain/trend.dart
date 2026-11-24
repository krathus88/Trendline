import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/weigh_in.dart';

/// One day on the weight trend.
class TrendPoint {
  const new({required this.day, required this.trendKg, this.weightKg});

  /// Local calendar day (midnight).
  final DateTime day;

  /// The smoothed weight on this day.
  final double trendKg;

  /// The reading used for this day, or null if there wasn't one.
  final double? weightKg;
}

/// The default smoothing factor. Each reading moves the trend 10% of the way
/// towards it, so day-to-day water swings barely register while a real change
/// shows within a week or two.
const double defaultTrendAlpha = 0.1;

/// Smooths weigh-ins into a daily trend with an exponential moving average:
/// `trend = trend + alpha * (weight - trend)`.
///
/// * One reading per day: the earliest of the day (most consistent: usually
///   first thing in the morning).
/// * Days without a reading carry the trend forward unchanged.
/// * The trend starts at the first reading.
/// * The result runs from the first reading's day to [until] (or the last
///   reading's day if [until] is null or earlier).
List<TrendPoint> computeTrend(
  Iterable<WeighIn> weighIns, {
  double alpha = defaultTrendAlpha,
  DateTime? until,
}) {
  assert(alpha > 0 && alpha <= 1, 'alpha must be in (0, 1]');
  if (weighIns.isEmpty) return const [];

  // Earliest reading per local day.
  final earliestByDay = <DateTime, WeighIn>{};
  for (final w in weighIns) {
    final day = dayOf(w.measuredAt);
    final current = earliestByDay[day];
    if (current == null || w.measuredAt.isBefore(current.measuredAt)) {
      earliestByDay[day] = w;
    }
  }

  final days = earliestByDay.keys.toList()..sort();
  final first = days.first;
  var last = days.last;
  if (until != null && dayOf(until).isAfter(last)) last = dayOf(until);

  final points = <TrendPoint>[];
  var trend = earliestByDay[first]!.weightKg;
  for (var day = first; !day.isAfter(last); day = addDays(day, 1)) {
    final reading = earliestByDay[day]?.weightKg;
    if (reading != null && day != first) {
      trend += alpha * (reading - trend);
    }
    points.add(TrendPoint(day: day, trendKg: trend, weightKg: reading));
  }
  return points;
}

/// How much the trend moved over the last 7 days, in kg (negative means
/// losing). Null until there are at least 8 days of trend.
double? weeklyTrendChangeKg(List<TrendPoint> trend) {
  if (trend.length < 8) return null;
  return trend.last.trendKg - trend[trend.length - 8].trendKg;
}
