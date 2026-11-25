import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/app.dart';
import 'package:trendline/domain/consent.dart';
import 'package:trendline/domain/privacy_policy.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

Future<void> _openYourData(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  final tile = find.text('Privacy and your data');
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  group('Consent', () {
    testWidgets('a new user agrees before onboarding', (tester) async {
      final backend = TestBackend()..account.consent = null;
      await backend.pump(tester);

      expect(find.text('Your data'), findsOneWidget);
      expect(find.text(privacySummary.first), findsOneWidget);
      final next = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(backend.account.consent?.policyVersion, privacyPolicyVersion);
      // On to the profile, with its own medical disclaimer.
      expect(find.text('Not medical advice'), findsOneWidget);
    });

    testWidgets('opens the full policy', (tester) async {
      final backend = TestBackend()..account.consent = null;
      await backend.pump(tester);

      await tester.tap(find.text('Read the full privacy policy'));
      await tester.pumpAndSettle();
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text(privacyPolicy.first.heading), findsOneWidget);
    });

    testWidgets('"Not now" signs out without recording consent', (
      tester,
    ) async {
      final backend = TestBackend()..account.consent = null;
      await backend.pump(tester);

      await tester.tap(find.text('Not now, sign out'));
      await tester.pumpAndSettle();
      expect(backend.auth.signOutCalls, 1);
      expect(backend.account.consent, isNull);
      expect(find.text('Continue with Discord'), findsOneWidget);
    });

    testWidgets('asks again when the policy has changed', (tester) async {
      final backend = TestBackend(profile: testProfile)
        ..account.consent = Consent(
          policyVersion: privacyPolicyVersion - 1,
          consentedAt: DateTime(2026),
        );
      await backend.pump(tester);

      expect(find.text('Privacy policy updated'), findsOneWidget);
      expect(find.text('Export or delete my data instead'), findsOneWidget);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final backend = TestBackend(profile: testProfile)
        ..account.failFetch = true;
      await backend.pump(tester);

      expect(find.text('Try again'), findsOneWidget);
      backend.account.failFetch = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('Your data', () {
    testWidgets('shows when the user agreed', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.pump(tester);
      await _openYourData(tester);

      expect(
        find.text('You agreed on 20 Nov 2026 (version $privacyPolicyVersion)'),
        findsOneWidget,
      );
    });

    testWidgets('exports everything as JSON and the logs as CSV', (
      tester,
    ) async {
      final backend = TestBackend(profile: testProfile)
        ..account.export = {
          'format': 1,
          'weigh_ins': [
            {'measured_at': '2026-11-20T07:30:00Z', 'weight_kg': 82.4},
          ],
        };
      await backend.pump(tester);
      await _openYourData(tester);

      await tester.tap(find.text('Everything (JSON)'));
      await tester.pumpAndSettle();
      final json = backend.files.saved.single;
      expect(json.fileName, startsWith('trendline-data-'));
      expect(json.mimeType, 'application/json');
      expect(jsonDecode(json.contents), backend.account.export);
      expect(find.text('Saved'), findsOneWidget);

      await tester.tap(find.text('Weigh-ins (CSV)'));
      await tester.pumpAndSettle();
      expect(
        backend.files.saved.last.contents,
        contains('2026-11-20T07:30:00Z,82.4,,,'),
      );
    });

    testWidgets('a cancelled save says nothing', (tester) async {
      final backend = TestBackend(profile: testProfile);
      backend.files.cancel = true;
      await backend.pump(tester);
      await _openYourData(tester);

      await tester.tap(find.text('Food log (CSV)'));
      await tester.pumpAndSettle();
      expect(backend.files.saved, isEmpty);
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('deleting needs DELETE typed, then signs out', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.pump(tester);
      await _openYourData(tester);

      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(TextButton, 'Delete for good');
      expect(tester.widget<TextButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(backend.account.deletes, 1);
      expect(backend.auth.signOutCalls, 1);
      expect(find.text('Continue with Discord'), findsOneWidget);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.pump(tester);
      await _openYourData(tester);

      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.account.deletes, 0);
      expect(backend.auth.signOutCalls, 0);
    });

    testWidgets('a failed deletion keeps the user signed in', (tester) async {
      final backend = TestBackend(profile: testProfile);
      await backend.pump(tester);
      await _openYourData(tester);
      backend.account.failDelete = true;

      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.text('Delete for good'));
      await tester.pumpAndSettle();

      expect(backend.auth.signOutCalls, 0);
      expect(find.text('Privacy and your data'), findsOneWidget);
    });
  });

  testWidgets('Health Connect opens the policy without signing in', (
    tester,
  ) async {
    await tester.pumpWidget(const TrendlineApp.privacyPolicy());
    await tester.pumpAndSettle();

    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Health Connect'), 300);
    expect(find.text('Health Connect'), findsOneWidget);
  });
}
