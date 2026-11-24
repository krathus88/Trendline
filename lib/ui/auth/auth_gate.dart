import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/snapshots/today_snapshot_notifier.dart';
import 'package:trendline/ui/auth/sign_in_screen.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/home/profile_gate.dart';

/// Shows the sign-in screen or the app, depending on the auth status.
class AuthGate extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the Today snapshot's owner check running for the app's whole
    // life, so signing out deletes it straight away.
    ref.listen(todaySnapshotProvider, (_, _) {});
    return switch (ref.watch(authStatusProvider)) {
      AsyncData(value: SignedIn()) => const ProfileGate(),
      AsyncLoading() => const Scaffold(body: CenteredProgress()),
      // Signed out, or the status couldn't be read: either way, sign in.
      _ => const SignInScreen(),
    };
  }
}
