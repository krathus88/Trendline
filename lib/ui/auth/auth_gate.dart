import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/ui/auth/sign_in_screen.dart';
import 'package:trendline/ui/dev/design_preview_screen.dart';

/// Shows the sign-in screen or the app, depending on the auth status.
class AuthGate extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(authStatusProvider)) {
      AsyncData(value: SignedIn()) => DesignPreviewScreen(
        // Placeholder home until the real screens land later in M1.
        onSignOut: () => ref.read(authRepositoryProvider).signOut(),
      ),
      AsyncLoading() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // Signed out, or the status couldn't be read: either way, sign in.
      _ => const SignInScreen(),
    };
  }
}
