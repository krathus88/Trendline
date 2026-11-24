import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/energy/day_complete_notifier.dart';
import 'package:trendline/data/energy/energy_notifier.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/goals/targets_provider.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/adaptive_tdee.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/energy.dart';
import 'package:trendline/domain/goals.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeWeighInRepository weighIns;
  late FakeFoodLogRepository logs;
  late FakeGoalRepository goals;
  late FakeEnergyRepository energy;
  late ProviderContainer container;
  final today = dayOf(DateTime.now());

  Future<void> start() async {
    container =
        ProviderContainer.test(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              profileRepositoryProvider.overrideWithValue(profiles),
              weighInRepositoryProvider.overrideWithValue(weighIns),
              foodLogRepositoryProvider.overrideWithValue(logs),
              goalRepositoryProvider.overrideWithValue(goals),
              energyRepositoryProvider.overrideWithValue(energy),
            ],
          )
          // Riverpod 3 pauses providers nobody listens to.
          ..listen(authStatusProvider, (_, _) {})
          ..listen(energyProvider, (_, _) {})
          ..listen(targetsProvider, (_, _) {});
    await container.read(authStatusProvider.future);
  }

  /// [days] of eating [intakeKcal] with a true burn of [trueKcal], all
  /// logged, complete and weighed, ending yesterday.
  Future<void> seedHistory({
    int days = 22,
    double trueKcal = 2500,
    double intakeKcal = 2000,
    bool markComplete = true,
  }) async {
    var kg = 100.0;
    for (var i = days; i >= 1; i--) {
      final day = addDays(today, -i);
      await weighIns.add(
        measuredAt: day.add(const Duration(hours: 7)),
        weightKg: kg,
      );
      logs.dailyKcal[day] = intakeKcal;
      if (markComplete) energy.completeDays.add(day);
      kg -= (trueKcal - intakeKcal) / kcalPerKg;
    }
  }

  setUp(() {
    auth = FakeAuthRepository(initial: const SignedIn('user-1'));
    profiles = FakeProfileRepository(profile: testProfile);
    weighIns = FakeWeighInRepository();
    logs = FakeFoodLogRepository();
    goals = FakeGoalRepository(goal: Goal.maintenance);
    energy = FakeEnergyRepository();
  });

  tearDown(() => auth.dispose());

  group('energy estimate', () {
    test('nothing until the first weigh-in', () async {
      await start();
      expect(await container.read(energyProvider.future), isNull);
      expect(await container.read(targetsProvider.future), isNull);
    });

    test('starts from the formula', () async {
      await weighIns.add(measuredAt: DateTime.now(), weightKg: 90);
      await start();
      final e = (await container.read(energyProvider.future))!;
      expect(e.isLearned, isFalse);
      expect(e.confidence, 0);
      expect(e.tdeeKcal, e.formulaKcal);
      expect(e.lastAttempt?.outcome, AdaptiveOutcome.notEnoughHistory);
    });

    test('learns from three weeks of complete logging and saves it', () async {
      await seedHistory();
      await start();
      final e = (await container.read(energyProvider.future))!;
      expect(e.isLearned, isTrue);
      expect(e.confidence, confidenceStep);
      // Moves from the formula towards the true 2,500 kcal.
      final step = e.tdeeKcal - e.formulaKcal;
      expect(step.abs(), lessThanOrEqualTo(maxChangeKcal + 1e-9));
      expect(step.sign, (2500 - e.formulaKcal).sign);
      expect(energy.estimates.single.computedOn, today);
    });

    test('days not marked complete teach it nothing', () async {
      await seedHistory(markComplete: false);
      await start();
      final e = (await container.read(energyProvider.future))!;
      expect(e.isLearned, isFalse);
      expect(energy.estimates, isEmpty);
    });

    test('a day marked complete with nothing logged is ignored', () async {
      await seedHistory();
      // Six days in the middle of the window: 15 of 21 is under 80%.
      for (var i = 5; i <= 10; i++) {
        logs.dailyKcal.remove(addDays(today, -i));
      }
      await start();
      final e = (await container.read(energyProvider.future))!;
      expect(e.lastAttempt?.outcome, AdaptiveOutcome.tooFewCompleteDays);
    });

    test('uses the saved estimate until the next weekly update', () async {
      await seedHistory();
      energy.estimates.add(
        EnergyEstimate(
          computedOn: addDays(today, -3),
          tdeeKcal: 2400,
          confidence: 0.5,
          windowDays: 21,
          completeShare: 1,
          observedKcal: 2450,
        ),
      );
      await start();
      final e = (await container.read(energyProvider.future))!;
      expect(e.tdeeKcal, 2400);
      expect(e.confidence, 0.5);
      expect(energy.estimates, hasLength(1));
    });
  });

  group('targets', () {
    test('need a goal', () async {
      goals.goal = null;
      await weighIns.add(measuredAt: DateTime.now(), weightKg: 90);
      await start();
      expect(await container.read(targetsProvider.future), isNull);
    });

    test('maintenance eats the estimate', () async {
      await weighIns.add(measuredAt: DateTime.now(), weightKg: 90);
      await start();
      final t = (await container.read(targetsProvider.future))!;
      expect(t.targets.kcal, closeTo(t.energy.tdeeKcal, 5));
      expect(t.adjusted, isFalse);
      expect(t.projectedDate, isNull);
    });

    test('an over-fast goal is capped and flagged', () async {
      goals.goal = const Goal(
        kind: GoalKind.targetAndPace,
        targetWeightKg: 80,
        paceValue: 2,
      );
      await weighIns.add(measuredAt: DateTime.now(), weightKg: 90);
      await start();
      final t = (await container.read(targetsProvider.future))!;
      expect(t.plan.cappedByPace, isTrue);
      expect(t.adjusted, isTrue);
      expect(t.targets.kcal, greaterThanOrEqualTo(t.targets.floorKcal));
      expect(t.projectedDate, isNotNull);
    });

    test('changing the goal updates the targets', () async {
      await weighIns.add(measuredAt: DateTime.now(), weightKg: 90);
      await start();
      final before = (await container.read(targetsProvider.future))!;
      await container
          .read(goalProvider.notifier)
          .save(
            const Goal(
              kind: GoalKind.targetAndPace,
              targetWeightKg: 80,
              paceValue: 0.5,
            ),
          );
      final after = (await container.read(targetsProvider.future))!;
      expect(after.targets.kcal, lessThan(before.targets.kcal));
      expect(goals.saves, 1);
    });
  });

  group('day complete', () {
    test('marks and unmarks a day', () async {
      await start();
      final day = addDays(today, -1);
      final provider = dayCompleteProvider(day);
      container.listen(provider, (_, _) {});
      expect(await container.read(provider.future), isFalse);

      await container.read(provider.notifier).set(complete: true);
      expect(container.read(provider).value, isTrue);
      expect(energy.completeDays, {day});

      await container.read(provider.notifier).set(complete: false);
      expect(energy.completeDays, isEmpty);
    });
  });
}
