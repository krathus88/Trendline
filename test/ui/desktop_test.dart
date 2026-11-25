import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

void main() {
  group('Wide windows', () {
    testWidgets('use a side rail instead of the bottom bar', (tester) async {
      // pump() opens a phone-sized window; widen it afterwards.
      await TestBackend(profile: testProfile).pump(tester);
      tester.view.physicalSize = const Size(1280, 1600);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      expect(find.text('No weigh-ins yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phones keep the bottom bar', (tester) async {
      await TestBackend(profile: testProfile).pump(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('Refresh button', () {
    testWidgets('stands in for pull-to-refresh on desktop', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.pump(tester);
      expect(find.byTooltip('Refresh'), findsOneWidget);

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      await backend.weighIns.add(measuredAt: DateTime.now(), weightKg: 80);
      // The repository changed behind the cache; refreshing shows it.
      await tester.tap(find.byTooltip('Refresh').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('No weigh-ins yet'), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('is not shown on phones', (tester) async {
      await TestBackend(profile: testProfile).pump(tester);
      expect(find.byTooltip('Refresh'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
