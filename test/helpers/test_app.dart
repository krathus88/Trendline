import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:trendline/app.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/plans/plan_notifier.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/dish_template_providers.dart';
import 'package:trendline/data/recipes/recipe_library_providers.dart';
import 'package:trendline/data/snapshots/today_snapshot_notifier.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/planner.dart';
import 'package:trendline/domain/profile.dart';

import 'fake_auth_repository.dart';
import 'fakes.dart';

/// Every fake the app needs, wired into one place for widget tests.
class TestBackend {
  new({Profile? profile, AuthStatus auth = const SignedIn('user-1')})
    : auth = FakeAuthRepository(initial: auth),
      profiles = FakeProfileRepository(profile: profile) {
    plans.onSaved = (plan) => prep.layOut(plan, recipes.items);
  }

  final FakeAuthRepository auth;
  final FakeProfileRepository profiles;
  final weighIns = FakeWeighInRepository();
  final foods = FakeFoodRepository();
  final referenceFoods = FakeReferenceFoodRepository();
  final recipes = FakeRecipeRepository();
  final preferences = FakeFoodPreferencesRepository();
  final schedules = FakeScheduleRepository();
  final rules = FakeMealRuleRepository();
  final plans = FakeMealPlanRepository();
  final prep = FakePrepRepository();
  final snapshots = FakeSnapshotStore();
  final foodLogs = FakeFoodLogRepository();
  final scanner = FakeBarcodeScanner();
  final health = FakeHealthSource();
  final goals = FakeGoalRepository(goal: Goal.maintenance);
  final energy = FakeEnergyRepository();
  final households = FakeHouseholdRepository();

  /// The recipe library file's contents. Null uses the real one.
  String? library;

  /// The dish template file's contents. Null uses the real one.
  String? templates;

  /// Open Food Facts responses. Defaults to "not found" for everything.
  Future<http.Response> Function(http.Request) off = (_) async =>
      http.Response('{}', 404);

  List<Override> get overrides => [
    authRepositoryProvider.overrideWithValue(auth),
    profileRepositoryProvider.overrideWithValue(profiles),
    weighInRepositoryProvider.overrideWithValue(weighIns),
    foodRepositoryProvider.overrideWithValue(foods),
    referenceFoodRepositoryProvider.overrideWithValue(referenceFoods),
    recipeRepositoryProvider.overrideWithValue(recipes),
    householdRepositoryProvider.overrideWithValue(households),
    foodPreferencesRepositoryProvider.overrideWithValue(preferences),
    scheduleRepositoryProvider.overrideWithValue(schedules),
    mealRuleRepositoryProvider.overrideWithValue(rules),
    mealPlanRepositoryProvider.overrideWithValue(plans),
    prepRepositoryProvider.overrideWithValue(prep),
    snapshotStoreProvider.overrideWithValue(snapshots),
    // Plan on the test's thread with a short search, so it's quick and
    // fake-async friendly.
    planRunnerProvider.overrideWithValue(
      (input, seed) async => planWeek(
        PlannerInput(
          targets: input.targets,
          dishes: input.dishes,
          rules: input.rules,
          locked: input.locked,
          iterations: 400,
        ),
        Random(seed),
      ),
    ),
    foodLogRepositoryProvider.overrideWithValue(foodLogs),
    barcodeScannerProvider.overrideWithValue(scanner),
    healthSourceProvider.overrideWithValue(health),
    goalRepositoryProvider.overrideWithValue(goals),
    energyRepositoryProvider.overrideWithValue(energy),
    offClientProvider.overrideWith((ref) => fakeOffClient((r) => off(r))),
    if (library case final source?)
      recipeLibrarySourceProvider.overrideWithValue(() async => source),
    if (templates case final source?)
      dishTemplatesSourceProvider.overrideWithValue(() async => source),
  ];

  Future<void> pump(WidgetTester tester) async {
    addTearDown(auth.dispose);
    // A tall phone-width screen, so whole forms are built without scrolling.
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: const TrendlineApp()),
    );
    await tester.pumpAndSettle();
  }
}
