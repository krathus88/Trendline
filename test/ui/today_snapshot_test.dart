import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/snapshots/today_snapshot.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/nutrition.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

final DateTime _today = dayOf(DateTime.now());

String _saved({String food = 'Saved porridge', DateTime? day}) => TodaySnapshot(
  userId: 'user-1',
  day: day ?? _today,
  savedAt: DateTime(2026, 12, 7, 7, 45),
  entries: [
    FoodLogEntry(
      id: 'l1',
      eatenOn: day ?? _today,
      eatenAt: DateTime.now(),
      slot: MealSlot.breakfast,
      foodName: food,
      grams: 80,
      nutrition: const Nutrition(kcal: 304, proteinG: 9, carbsG: 48, fatG: 6),
    ),
  ],
  targets: null,
  planned: const [],
).encode();

void main() {
  testWidgets('Today is saved on the device once it has loaded', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    await backend.foodLogs.add(
      day: _today,
      slot: MealSlot.lunch,
      food: const Food(
        id: 'f1',
        name: 'Soup',
        per100g: Nutrition(kcal: 50, proteinG: 2, carbsG: 6, fatG: 2),
        source: FoodSource.manual,
      ),
      grams: 300,
    );
    await backend.pump(tester);

    final saved = TodaySnapshot.decode(backend.snapshots.values['today'])!;
    expect(saved.userId, 'user-1');
    expect(saved.day, _today);
    expect(saved.entries.single.foodName, 'Soup');
  });

  testWidgets('without signal, the app opens on the saved copy', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    backend.snapshots.values['today'] = _saved();
    backend.profiles.failFetch = true;
    backend.foodLogs.failFetch = true;
    await backend.pump(tester);

    expect(find.text('Saved porridge'), findsOneWidget);
    expect(
      find.textContaining('Can’t reach the server. Showing what was saved'),
      findsOneWidget,
    );

    // Back online: the live log replaces the copy.
    backend.foodLogs.failFetch = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Saved porridge'), findsNothing);
    expect(find.textContaining('Showing what was saved'), findsNothing);
  });

  testWidgets('a copy from another day isn’t shown as today', (tester) async {
    final backend = TestBackend(profile: testProfile);
    backend.snapshots.values['today'] = _saved(day: addDays(_today, -1));
    backend.foodLogs.failFetch = true;
    await backend.pump(tester);
    expect(find.text('Saved porridge'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('signing out deletes the copy', (tester) async {
    final backend = TestBackend(profile: testProfile);
    backend.goals.goal = Goal.maintenance;
    backend.snapshots.values['today'] = _saved();
    await backend.pump(tester);
    expect(backend.snapshots.values, isNotEmpty);

    await backend.auth.signOut();
    await tester.pumpAndSettle();
    expect(backend.snapshots.values, isEmpty);
  });
}
