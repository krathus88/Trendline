import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:trendline/app.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/profile.dart';

import 'fake_auth_repository.dart';
import 'fakes.dart';

/// Every fake the app needs, wired into one place for widget tests.
class TestBackend {
  new({Profile? profile, AuthStatus auth = const SignedIn('user-1')})
    : auth = FakeAuthRepository(initial: auth),
      profiles = FakeProfileRepository(profile: profile);

  final FakeAuthRepository auth;
  final FakeProfileRepository profiles;
  final weighIns = FakeWeighInRepository();
  final foods = FakeFoodRepository();
  final referenceFoods = FakeReferenceFoodRepository();
  final recipes = FakeRecipeRepository();
  final foodLogs = FakeFoodLogRepository();
  final scanner = FakeBarcodeScanner();
  final health = FakeHealthSource();
  final goals = FakeGoalRepository(goal: Goal.maintenance);
  final energy = FakeEnergyRepository();

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
    foodLogRepositoryProvider.overrideWithValue(foodLogs),
    barcodeScannerProvider.overrideWithValue(scanner),
    healthSourceProvider.overrideWithValue(health),
    goalRepositoryProvider.overrideWithValue(goals),
    energyRepositoryProvider.overrideWithValue(energy),
    offClientProvider.overrideWith((ref) => fakeOffClient((r) => off(r))),
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
