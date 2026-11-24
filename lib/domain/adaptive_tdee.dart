import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/energy.dart';
import 'package:trendline/domain/trend.dart';

/// The longest window of days each update looks at.
const int maxWindowDays = 21;

/// The shortest: fewer days are too noisy to learn from.
const int minWindowDays = 14;

/// Days between updates.
const int updateIntervalDays = 7;

/// Share of the window's days that must be marked complete: 80%.
const double minCompleteShare = 0.8;

/// Complete days needed in a window of [windowDays]. Whole-number maths:
/// `windowDays * 0.8` isn't exact in floating point (15 * 0.8 is just over
/// 12), which would wrongly reject exactly 80%.
int completeDaysRequired(int windowDays) => (windowDays * 4 + 4) ~/ 5;

/// Weigh-ins needed inside the window, and how many days apart the first
/// and last must be, for the rate of change to mean anything.
const int minWeighInsInWindow = 4;
const int minWeighInSpanDays = 7;

/// How far each update moves towards what the data shows.
const double blendWeight = 0.4;

/// The most one update may change the estimate, in kcal.
const double maxChangeKcal = 150;

/// How much confidence each successful update adds (0 to 1).
const double confidenceStep = 0.25;

/// Sanity range for any estimate, in kcal per day.
const double minTdeeKcal = 800;
const double maxTdeeKcal = 6000;

/// An energy estimate learned from logging.
@immutable
class EnergyEstimate {
  const new({
    required this.computedOn,
    required this.tdeeKcal,
    required this.confidence,
    required this.windowDays,
    required this.completeShare,
    required this.observedKcal,
  });

  /// Local calendar day of the update.
  final DateTime computedOn;
  final double tdeeKcal;

  /// 0 (formula only) to 1.
  final double confidence;
  final int windowDays;
  final double completeShare;

  /// What the window's data alone suggested, before blending and capping.
  final double observedKcal;
}

enum AdaptiveOutcome {
  updated,

  /// The last update was less than a week ago.
  tooSoon,

  /// Fewer than [minWindowDays] days since the first complete day.
  notEnoughHistory,

  /// Under [minCompleteShare] of the window's days are complete.
  tooFewCompleteDays,

  /// Not enough weigh-ins in the window to trust the trend.
  tooFewWeighIns,
}

@immutable
class AdaptiveResult {
  const new({
    required this.outcome,
    this.estimate,
    this.windowDays = 0,
    this.completeDays = 0,
  });

  final AdaptiveOutcome outcome;

  /// Set when [outcome] is [AdaptiveOutcome.updated].
  final EnergyEstimate? estimate;
  final int windowDays;
  final int completeDays;

  /// Complete days still needed for an update, for nudging the user.
  int get completeDaysNeeded => math.max(
    0,
    completeDaysRequired(math.max(windowDays, minWindowDays)) - completeDays,
  );
}

/// Learns daily energy use from logged intake and weight change.
///
/// Over the window ending yesterday (today isn't over yet):
/// `observed = mean intake on complete days − weight change per day × 7700`.
///
/// The weight change is the slope of a straight line fitted through the
/// window's daily readings. Unlike the difference in the smoothed trend, it
/// doesn't lag behind real change and uses every reading, so a single high
/// or low day at either end of the window barely moves it.
/// Only complete days count: a partly logged day understates intake. The
/// result moves [blendWeight] of the way from [priorKcal] towards observed,
/// by at most [maxChangeKcal].
AdaptiveResult updateEnergyEstimate({
  required double priorKcal,
  required double priorConfidence,
  required DateTime? lastUpdatedOn,
  required Map<DateTime, double> completeDayKcal,
  required List<TrendPoint> trend,
  required DateTime today,
}) {
  final day = dayOf(today);
  if (lastUpdatedOn != null &&
      daysBetween(lastUpdatedOn, day) < updateIntervalDays) {
    return const AdaptiveResult(outcome: AdaptiveOutcome.tooSoon);
  }

  final end = addDays(day, -1);
  final kcalByDay = {
    for (final e in completeDayKcal.entries) dayOf(e.key): e.value,
  };
  final completeDays = kcalByDay.keys.toList()..sort();
  if (completeDays.isEmpty) {
    return const AdaptiveResult(outcome: AdaptiveOutcome.notEnoughHistory);
  }
  final history = daysBetween(completeDays.first, end) + 1;
  if (history < minWindowDays) {
    return AdaptiveResult(
      outcome: AdaptiveOutcome.notEnoughHistory,
      windowDays: math.max(history, 0),
      completeDays: completeDays.length,
    );
  }

  final windowDays = math.min(history, maxWindowDays);
  final start = addDays(end, -(windowDays - 1));
  final inWindow = [
    for (final d in completeDays)
      if (!d.isBefore(start) && !d.isAfter(end)) d,
  ];
  if (inWindow.length < completeDaysRequired(windowDays)) {
    return AdaptiveResult(
      outcome: AdaptiveOutcome.tooFewCompleteDays,
      windowDays: windowDays,
      completeDays: inWindow.length,
    );
  }

  // The day's reading (the earliest of the day) for each day in the window.
  final readings = [
    for (final p in trend)
      if (p.weightKg != null && !p.day.isBefore(start) && !p.day.isAfter(end))
        (x: daysBetween(start, p.day).toDouble(), kg: p.weightKg!),
  ];
  if (readings.length < minWeighInsInWindow ||
      readings.last.x - readings.first.x < minWeighInSpanDays) {
    return AdaptiveResult(
      outcome: AdaptiveOutcome.tooFewWeighIns,
      windowDays: windowDays,
      completeDays: inWindow.length,
    );
  }

  var intake = 0.0;
  for (final d in inWindow) {
    intake += kcalByDay[d]!;
  }
  final meanIntake = intake / inWindow.length;
  final kgPerDay = _slope(readings);
  final observed = (meanIntake - kgPerDay * kcalPerKg).clamp(
    minTdeeKcal,
    maxTdeeKcal,
  );
  final step = (blendWeight * (observed - priorKcal)).clamp(
    -maxChangeKcal,
    maxChangeKcal,
  );

  return AdaptiveResult(
    outcome: AdaptiveOutcome.updated,
    windowDays: windowDays,
    completeDays: inWindow.length,
    estimate: EnergyEstimate(
      computedOn: day,
      tdeeKcal: (priorKcal + step).clamp(minTdeeKcal, maxTdeeKcal),
      confidence: math.min(1, priorConfidence + confidenceStep),
      windowDays: windowDays,
      completeShare: inWindow.length / windowDays,
      observedKcal: observed,
    ),
  );
}

/// Least-squares slope of kg against day, in kg per day.
double _slope(List<({double x, double kg})> points) {
  final n = points.length;
  var sx = 0.0;
  var sy = 0.0;
  for (final p in points) {
    sx += p.x;
    sy += p.kg;
  }
  final mx = sx / n;
  final my = sy / n;
  var num = 0.0;
  var den = 0.0;
  for (final p in points) {
    num += (p.x - mx) * (p.kg - my);
    den += (p.x - mx) * (p.x - mx);
  }
  return den == 0 ? 0 : num / den;
}
