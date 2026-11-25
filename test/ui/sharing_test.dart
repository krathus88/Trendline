import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/goals.dart';
import 'package:trendline/domain/sharing.dart';
import 'package:trendline/domain/weigh_in.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

Future<void> _openSharing(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sharing'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('makes a code, then switches what a viewer sees', (tester) async {
    final backend = TestBackend(profile: testProfile);
    await backend.pump(tester);
    await _openSharing(tester);

    expect(find.textContaining('Nothing is shared until'), findsOneWidget);

    await tester.tap(find.text('Share with someone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Alex');
    await tester.tap(find.text('Make a code'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one thing to share.'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Weight trend'));
    await tester.tap(find.text('Make a code'));
    await tester.pumpAndSettle();

    final invite = backend.sharing.invites.single;
    expect(invite.kinds, {ShareKind.weight});
    expect(find.textContaining('Weight trend · works once'), findsOneWidget);

    // Someone accepts it (outside this app); it shows as a viewer.
    backend.sharing
      ..invites.clear()
      ..shares.add(
        const Share(
          id: 's1',
          ownerId: 'user-1',
          viewerId: 'b',
          ownerName: 'Alex',
          viewerName: 'Bea',
          kinds: {ShareKind.weight},
        ),
      );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Bea'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Meal plans'));
    await tester.pumpAndSettle();
    expect(backend.sharing.shares.single.kinds, {
      ShareKind.weight,
      ShareKind.plans,
    });

    await tester.tap(find.byTooltip('Stop sharing with Bea'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Stop sharing'));
    await tester.pumpAndSettle();
    expect(backend.sharing.shares, isEmpty);
    expect(find.text('Bea'), findsNothing);
  });

  testWidgets('a viewer enters a code and sees only what is shared', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    final today = dayOf(DateTime.now());
    backend.sharing
      ..validCodes['QRSTU23456'] = {ShareKind.weight, ShareKind.plans}
      ..weighIns['owner'] = [
        for (var d = 0; d < 5; d++)
          WeighIn(
            id: 'w$d',
            measuredAt: addDays(today, d - 4).add(const Duration(hours: 7)),
            weightKg: 80 - d * 0.2,
          ),
      ]
      ..targets['owner'] = const SharedTargets(
        kcal: 1800,
        proteinG: 120,
        carbsG: 200,
        fatG: 60,
        fibreG: 30,
      )
      ..plans['owner'] = [
        SharedPlanItem(
          day: weekStartOf(today),
          slot: MealSlot.lunch,
          name: 'Lentil soup',
          amount: 1.5,
          isRecipe: true,
          kcal: 450,
          proteinG: 24,
        ),
      ];
    await backend.pump(tester);
    await _openSharing(tester);

    await tester.tap(find.text('Enter a code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Code'), 'nope');
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Bea');
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the 10-character code.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Code'),
      'qrstu-23456',
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Weight trend, Meal plans'), findsOneWidget);

    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    expect(
      find.text('Read-only: you can see this, not change it.'),
      findsOneWidget,
    );
    expect(find.textContaining('Trend '), findsOneWidget);
    expect(find.text('Lentil soup'), findsOneWidget);
    expect(find.text('1.5 portions · 450 kcal'), findsOneWidget);
    expect(find.text('Daily targets'), findsNothing, reason: 'not shared');

    await tester.tap(find.byTooltip('Stop viewing'));
    await tester.pumpAndSettle();
    expect(backend.sharing.shares, isEmpty);
    expect(find.text('Sam'), findsNothing);
  });

  testWidgets('targets are published only while a share includes them', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    backend.goals.goal = Goal.maintenance;
    await backend.weighIns.add(
      measuredAt: DateTime.now().subtract(const Duration(hours: 1)),
      weightKg: 90,
    );
    backend.sharing.shares.add(
      const Share(
        id: 's1',
        ownerId: 'user-1',
        viewerId: 'b',
        ownerName: 'Alex',
        viewerName: 'Bea',
        kinds: {ShareKind.weight},
      ),
    );
    await backend.pump(tester);
    expect(backend.sharing.publishes, 0);

    await _openSharing(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Daily targets'));
    await tester.pumpAndSettle();
    expect(backend.sharing.publishes, 1);
    expect(backend.sharing.published!.kcal, greaterThanOrEqualTo(1500));

    await tester.tap(find.widgetWithText(SwitchListTile, 'Daily targets'));
    await tester.pumpAndSettle();
    expect(backend.sharing.published, isNull);
    expect(backend.sharing.publishes, 1);
  });

  testWidgets('a viewer looks back and ahead through the shared weeks', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    final thisWeek = weekStartOf(DateTime.now());
    SharedPlanItem item(DateTime day, String name) => SharedPlanItem(
      day: day,
      slot: MealSlot.dinner,
      name: name,
      amount: 1,
      isRecipe: true,
      kcal: 500,
      proteinG: 30,
    );
    backend.sharing
      ..validCodes['QRSTU23456'] = {ShareKind.plans}
      ..plans['owner'] = [
        item(thisWeek, 'Lentil soup'),
        item(addDays(thisWeek, 7), 'Chilli'),
        item(addDays(thisWeek, -14), 'Risotto'),
      ];
    await backend.pump(tester);
    await _openSharing(tester);
    await tester.tap(find.text('Enter a code'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Code'),
      'QRSTU23456',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Bea');
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();

    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Lentil soup'), findsOneWidget);

    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('Chilli'), findsOneWidget);
    expect(find.text('Lentil soup'), findsNothing);
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull, reason: 'no plans further ahead');

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Week of'), findsOneWidget);
    expect(find.text('Risotto'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.text('No plan saved for that week'), findsOneWidget);
  });
}
