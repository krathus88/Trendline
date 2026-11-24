import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/goals/goal_screen.dart';
import 'package:trendline/ui/home/home_shell.dart';
import 'package:trendline/ui/profile/profile_form_screen.dart';

/// Sends new users through onboarding (profile, then goal) before the app.
class ProfileGate extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(profileProvider)) {
      AsyncData(value: null) => const ProfileFormScreen(),
      AsyncData() => const _GoalGate(),
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

class _GoalGate extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(goalProvider)) {
      AsyncData(value: null) => const GoalScreen(onboarding: true),
      AsyncData() => const HomeShell(),
      AsyncError(:final error) => Scaffold(
        body: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(goalProvider),
        ),
      ),
      _ => const Scaffold(body: CenteredProgress()),
    };
  }
}
