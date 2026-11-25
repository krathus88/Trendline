import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/meal_rules.dart';
import 'package:trendline/platform/health_source.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets('Today shows the setup checklist until planning can run', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    backend.goals.goal = Goal.maintenance;
    await backend.pump(tester);

    expect(find.text('Finish setting up'), findsOneWidget);
    // Profile and goal are done (onboarding); nothing else yet. Seven steps,
    // as Health Connect is available here.
    expect(find.textContaining('2 of 7 done'), findsOneWidget);
    expect(find.text('Needed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

    await tester.tap(find.text('First weigh-in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'kg'), '90');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsNothing);
  });

  testWidgets('Health Connect is left out where it is unavailable', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    backend.goals.goal = Goal.maintenance;
    backend.health.status = HealthAvailability.unavailable;
    await backend.pump(tester);
    expect(find.textContaining('2 of 6 done'), findsOneWidget);
    expect(find.text('Health Connect'), findsNothing);
  });

  testWidgets('Settings lists what is done, including optional steps', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    backend.goals.goal = Goal.maintenance;
    await backend.weighIns.add(measuredAt: DateTime.now(), weightKg: 90);
    await backend.rules.save(
      const MealRule(
        id: '',
        foodId: 'f1',
        frequency: RuleFrequency.daily,
        amountMin: 100,
        amountMax: 100,
      ),
    );
    await backend.pump(tester);

    expect(find.text('Finish setting up'), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('4 of 7 done'), findsOneWidget);

    await tester.tap(find.text('Setup checklist'));
    await tester.pumpAndSettle();
    expect(find.text('Set up planning'), findsOneWidget);
    expect(find.text('Needed'), findsNothing);
    expect(find.textContaining('Everything needed is done'), findsOneWidget);
  });
}
