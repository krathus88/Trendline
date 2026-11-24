import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/weigh_ins/weigh_ins_notifier.dart';
import 'package:trendline/domain/adaptive_tdee.dart';
import 'package:trendline/domain/body_composition.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/energy.dart';
import 'package:trendline/domain/trend.dart';

/// The current estimate of daily energy use, and where it came from.
@immutable
class EnergyState {
  const new({
    required this.trendKg,
    required this.bmrKcal,
    required this.formulaKcal,
    required this.tdeeKcal,
    required this.confidence,
    this.leanMassKg,
    this.lastUpdatedOn,
    this.lastAttempt,
  });

  /// Current trend weight.
  final double trendKg;
  final double bmrKcal;

  /// The formula estimate at the current weight.
  final double formulaKcal;

  /// The estimate used for targets: learned if there is one, else formula.
  final double tdeeKcal;

  /// 0 when only the formula is known, rising to 1 with weekly updates.
  final double confidence;
  final double? leanMassKg;

  /// When the estimate last learned from logging. Null: formula only.
  final DateTime? lastUpdatedOn;

  /// The latest update attempt, when one ran but couldn't update; explains
  /// what's missing.
  final AdaptiveResult? lastAttempt;

  bool get isLearned => lastUpdatedOn != null;
}

/// Null until the user has a profile and at least one weigh-in.
final energyProvider = AsyncNotifierProvider<EnergyNotifier, EnergyState?>(
  EnergyNotifier.new,
);

class EnergyNotifier extends AsyncNotifier<EnergyState?> {
  @override
  Future<EnergyState?> build() async {
    if (ref.watch(currentUserIdProvider) == null) return null;
    final profile = await ref.watch(profileProvider.future);
    final weighIns = await ref.watch(weighInsProvider.future);
    if (profile == null || weighIns.isEmpty) return null;

    final now = DateTime.now();
    final today = dayOf(now);
    final trend = computeTrend(weighIns, until: now);
    final trendKg = trend.last.trendKg;
    final lean = recentLeanMassKg(weighIns, today: today);
    final bmr = estimateBmr(
      profile,
      weightKg: trendKg,
      on: today,
      leanMassKg: lean,
    );
    final formula = bmr * activityFactor(profile.activityLevel);

    final repo = ref.read(energyRepositoryProvider);
    final latest = await repo.fetchLatest();
    var tdee = latest?.tdeeKcal ?? formula;
    var confidence = latest?.confidence ?? 0;
    var updatedOn = latest?.computedOn;
    AdaptiveResult? attempt;

    final due =
        updatedOn == null ||
        daysBetween(updatedOn, today) >= updateIntervalDays;
    if (due) {
      final from = addDays(today, -maxWindowDays);
      final to = addDays(today, -1);
      final complete = await repo.fetchCompleteDays(from, to);
      final kcal = await ref
          .read(foodLogRepositoryProvider)
          .fetchDailyKcal(from, to);
      // A day marked complete with nothing logged is a mistake, not a fast.
      final completeKcal = {
        for (final d in complete)
          if ((kcal[d] ?? 0) > 0) d: kcal[d]!,
      };
      final result = updateEnergyEstimate(
        priorKcal: tdee,
        priorConfidence: confidence,
        lastUpdatedOn: updatedOn,
        completeDayKcal: completeKcal,
        trend: trend,
        today: today,
      );
      if (result.estimate case final e?) {
        await repo.save(e);
        tdee = e.tdeeKcal;
        confidence = e.confidence;
        updatedOn = e.computedOn;
      } else {
        attempt = result;
      }
    }

    return EnergyState(
      trendKg: trendKg,
      bmrKcal: bmr,
      formulaKcal: formula,
      tdeeKcal: tdee,
      confidence: confidence,
      leanMassKg: lean,
      lastUpdatedOn: updatedOn,
      lastAttempt: attempt,
    );
  }
}
