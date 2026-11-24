import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/adaptive_tdee.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/energy.dart';
import 'package:trendline/domain/trend.dart';
import 'package:trendline/domain/weigh_in.dart';

/// A simulated person: true daily burn [trueTdee], eating [intake] a day,
/// weighing in every day from [start] with the weight implied by the deficit.
({Map<DateTime, double> intake, List<TrendPoint> trend}) simulate({
  required DateTime start,
  required int days,
  double trueTdee = 2500,
  double intake = 2000,
  double startKg = 100,
  bool Function(int day)? complete,
  bool Function(int day)? weighs,
  double Function(int day)? noiseKg,
}) {
  final logs = <DateTime, double>{};
  final weighIns = <WeighIn>[];
  var kg = startKg;
  for (var i = 0; i < days; i++) {
    final day = addDays(start, i);
    if (complete?.call(i) ?? true) logs[day] = intake;
    if (weighs?.call(i) ?? true) {
      weighIns.add(
        WeighIn(
          id: '$i',
          measuredAt: day.add(const Duration(hours: 7)),
          weightKg: kg + (noiseKg?.call(i) ?? 0),
        ),
      );
    }
    kg -= (trueTdee - intake) / kcalPerKg;
  }
  return (intake: logs, trend: computeTrend(weighIns));
}

void main() {
  final start = DateTime(2026, 9);

  AdaptiveResult run({
    required ({Map<DateTime, double> intake, List<TrendPoint> trend}) data,
    required DateTime today,
    double prior = 2200,
    double confidence = 0,
    DateTime? lastUpdatedOn,
  }) => updateEnergyEstimate(
    priorKcal: prior,
    priorConfidence: confidence,
    lastUpdatedOn: lastUpdatedOn,
    completeDayKcal: data.intake,
    trend: data.trend,
    today: today,
  );

  test('no complete days: keeps the prior', () {
    final data = simulate(start: start, days: 30, complete: (_) => false);
    final result = run(data: data, today: addDays(start, 30));
    expect(result.outcome, AdaptiveOutcome.notEnoughHistory);
    expect(result.estimate, isNull);
  });

  test('under two weeks of logging: keeps the prior', () {
    final data = simulate(start: start, days: 10);
    final result = run(data: data, today: addDays(start, 10));
    expect(result.outcome, AdaptiveOutcome.notEnoughHistory);
  });

  test('reads the true burn from intake and weight change', () {
    final data = simulate(start: start, days: 22);
    final result = run(data: data, today: addDays(start, 22));
    expect(result.outcome, AdaptiveOutcome.updated);
    expect(result.windowDays, maxWindowDays);
    final estimate = result.estimate!;
    expect(estimate.observedKcal, closeTo(2500, 1));
    // Moves 40% of the way from the prior: 2200 + 0.4 * 300.
    expect(estimate.tdeeKcal, closeTo(2320, 1));
    expect(estimate.confidence, confidenceStep);
  });

  test('never moves more than 150 kcal in one update', () {
    final data = simulate(start: start, days: 22);
    final up = run(data: data, today: addDays(start, 22), prior: 1800);
    expect(up.estimate!.tdeeKcal, closeTo(1950, 1e-9));
    final down = run(data: data, today: addDays(start, 22), prior: 3200);
    expect(down.estimate!.tdeeKcal, closeTo(3050, 1e-9));
  });

  test('small differences blend rather than jump', () {
    final data = simulate(start: start, days: 22, trueTdee: 2300);
    final estimate = run(data: data, today: addDays(start, 22)).estimate!;
    final observed = estimate.observedKcal;
    expect(estimate.tdeeKcal, closeTo(2200 + 0.4 * (observed - 2200), 1e-6));
  });

  test('converges on the true burn over weekly updates', () {
    final data = simulate(start: start, days: 120);
    var prior = 2000.0;
    var confidence = 0.0;
    DateTime? last;
    for (var day = 22; day <= 120; day++) {
      final today = addDays(start, day);
      final r = run(
        data: data,
        today: today,
        prior: prior,
        confidence: confidence,
        lastUpdatedOn: last,
      );
      if (r.outcome == AdaptiveOutcome.updated) {
        final e = r.estimate!;
        expect((e.tdeeKcal - prior).abs(), lessThanOrEqualTo(maxChangeKcal));
        prior = e.tdeeKcal;
        confidence = e.confidence;
        last = today;
      }
    }
    expect(prior, closeTo(2500, 10));
    expect(confidence, 1);
  });

  test('only updates once a week', () {
    final data = simulate(start: start, days: 30);
    final result = run(
      data: data,
      today: addDays(start, 30),
      lastUpdatedOn: addDays(start, 25),
    );
    expect(result.outcome, AdaptiveOutcome.tooSoon);
  });

  test('needs 80% of days complete, and says how many more', () {
    // Every third day incomplete: 14 of 21 complete, two-thirds.
    final data = simulate(start: start, days: 22, complete: (i) => i % 3 != 0);
    final result = run(data: data, today: addDays(start, 22));
    expect(result.outcome, AdaptiveOutcome.tooFewCompleteDays);
    expect(result.completeDaysNeeded, greaterThan(0));
  });

  test('incomplete days are left out rather than counted as low intake', () {
    // Same person, a few unlogged days; the estimate must match one with
    // every day logged, not be dragged down.
    final full = simulate(start: start, days: 22, trueTdee: 2300);
    final gaps = simulate(
      start: start,
      days: 22,
      trueTdee: 2300,
      complete: (i) => i != 10 && i != 15,
    );
    final a = run(data: full, today: addDays(start, 22)).estimate!;
    final b = run(data: gaps, today: addDays(start, 22)).estimate!;
    expect(b.tdeeKcal, closeTo(a.tdeeKcal, 1e-6));
  });

  test('needs real weigh-ins in the window', () {
    final data = simulate(start: start, days: 22, weighs: (i) => i < 2);
    final result = run(data: data, today: addDays(start, 22));
    expect(result.outcome, AdaptiveOutcome.tooFewWeighIns);
  });

  test('daily water-weight noise barely moves the estimate', () {
    final clean = simulate(start: start, days: 22, trueTdee: 2300);
    final noisy = simulate(
      start: start,
      days: 22,
      trueTdee: 2300,
      noiseKg: (i) => i.isEven ? 0.8 : -0.8,
    );
    final a = run(data: clean, today: addDays(start, 22)).estimate!;
    final b = run(data: noisy, today: addDays(start, 22)).estimate!;
    expect((a.tdeeKcal - b.tdeeKcal).abs(), lessThan(60));
  });

  test('impossible data stays inside the sanity range', () {
    final data = simulate(start: start, days: 22, intake: 50, trueTdee: 60);
    final e = run(data: data, today: addDays(start, 22), prior: 900).estimate!;
    expect(e.observedKcal, greaterThanOrEqualTo(minTdeeKcal));
    expect(e.tdeeKcal, greaterThanOrEqualTo(minTdeeKcal));
  });
  test('exactly 80% of days complete is enough', () {
    expect(completeDaysRequired(15), 12);
    expect(completeDaysRequired(21), 17);
    expect(completeDaysRequired(14), 12);
    // A 15-day window with exactly 12 complete days (80%).
    final data = simulate(
      start: start,
      days: 15,
      complete: (i) => i != 5 && i != 7 && i != 9,
    );
    final result = run(data: data, today: addDays(start, 15));
    expect(result.windowDays, 15);
    expect(result.completeDays, 12);
    expect(result.outcome, AdaptiveOutcome.updated);
  });
}
