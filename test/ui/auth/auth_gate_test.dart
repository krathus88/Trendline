import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/app.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/ui/auth/sign_in_screen.dart';
import 'package:trendline/ui/dev/design_preview_screen.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository auth;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
        child: const TrendlineApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() => auth.dispose());

  testWidgets('signed out shows the sign-in screen', (tester) async {
    auth = FakeAuthRepository();
    await pumpApp(tester);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Continue with Discord'), findsOneWidget);
  });

  testWidgets('tapping the button starts Discord sign-in', (tester) async {
    auth = FakeAuthRepository();
    await pumpApp(tester);

    await tester.tap(find.text('Continue with Discord'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
  });

  testWidgets('a failure to start sign-in is shown', (tester) async {
    auth = FakeAuthRepository()
      ..signInFailure = const AuthFailure('Could not open the browser.');
    await pumpApp(tester);

    await tester.tap(find.text('Continue with Discord'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open the browser.'), findsOneWidget);
  });

  testWidgets('signing in shows the app; signing out returns', (tester) async {
    auth = FakeAuthRepository();
    await pumpApp(tester);

    auth.emit(const SignedIn('user-1'));
    await tester.pumpAndSettle();
    expect(find.byType(DesignPreviewScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('an allowlist rejection explains the invite list', (
    tester,
  ) async {
    auth = FakeAuthRepository();
    await pumpApp(tester);

    auth.emitFailure(
      const AuthFailure(
        "This Discord account isn't on the invite list yet. "
        'Ask the app owner to add you.',
        notInvited: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.textContaining("isn't on the invite list"), findsOneWidget);
  });

  testWidgets('a restored session goes straight to the app in dark mode', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    auth = FakeAuthRepository(initial: const SignedIn('user-1'));
    await pumpApp(tester);

    final context = tester.element(find.byType(DesignPreviewScreen));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
