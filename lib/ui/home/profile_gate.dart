import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/home/home_shell.dart';
import 'package:trendline/ui/profile/profile_form_screen.dart';

/// Sends new users through onboarding before the app.
class ProfileGate extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(profileProvider)) {
      AsyncData(value: null) => const ProfileFormScreen(),
      AsyncData() => const HomeShell(),
      AsyncError(:final error) => Scaffold(
        body: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(profileProvider),
        ),
      ),
      _ => const Scaffold(body: CenteredProgress()),
    };
  }
}
