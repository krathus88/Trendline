import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/ui/auth/sign_in_screen.dart';
import 'package:trendline/ui/home/home_shell.dart';
import 'package:trendline/ui/profile/profile_form_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('signed out shows the sign-in screen', (tester) async {
    await TestBackend(auth: const SignedOut()).pump(tester);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Continue with Discord'), findsOneWidget);
  });

  testWidgets('tapping the button starts Discord sign-in', (tester) async {
    final backend = TestBackend(auth: const SignedOut());
    await backend.pump(tester);

    await tester.tap(find.text('Continue with Discord'));
    await tester.pumpAndSettle();

    expect(backend.auth.signInCalls, 1);
  });

  testWidgets('a failure to start sign-in is shown', (tester) async {
    final backend = TestBackend(auth: const SignedOut());
    backend.auth.signInFailure = const AuthFailure(
      'Could not open the browser.',
    );
    await backend.pump(tester);

    await tester.tap(find.text('Continue with Discord'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open the browser.'), findsOneWidget);
  });

  testWidgets('an allowlist rejection explains the invite list', (
    tester,
  ) async {
    final backend = TestBackend(auth: const SignedOut());
    await backend.pump(tester);

    backend.auth.emitFailure(
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

  testWidgets('a new user signing in goes to onboarding', (tester) async {
    final backend = TestBackend(auth: const SignedOut());
    await backend.pump(tester);

    backend.auth.emit(const SignedIn('user-1'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileFormScreen), findsOneWidget);
    expect(find.text('Not medical advice'), findsOneWidget);
  });

  testWidgets('a user with a profile goes to the app; sign-out returns', (
    tester,
  ) async {
    final backend = TestBackend(profile: testProfile);
    await backend.pump(tester);
    expect(find.byType(HomeShell), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(backend.auth.signOutCalls, 1);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('the app renders in dark mode without errors', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await TestBackend(profile: testProfile).pump(tester);

    final context = tester.element(find.byType(HomeShell));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
