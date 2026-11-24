import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/goals/goal_notifier.dart';
import 'package:trendline/data/profile/profile_notifier.dart';
import 'package:trendline/data/snapshots/today_snapshot_notifier.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/goals/goal_screen.dart';
import 'package:trendline/ui/home/home_shell.dart';
import 'package:trendline/ui/profile/health_screen_screen.dart';
import 'package:trendline/ui/profile/profile_form_screen.dart';

/// Sends new users through onboarding (profile, health check, then goal)
/// before the app.
///
/// While the profile and goal load (or can't, without signal), a user with
/// a Today snapshot has been through onboarding already, so the app opens
/// on it straight away instead of waiting.
class ProfileGate extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    if (!profile.hasValue && ref.watch(todaySnapshotProvider).value != null) {
      return const HomeShell();
    }
    return switch (profile) {
      AsyncData(value: null) => const ProfileFormScreen(),
      AsyncData(:final value?) when value.healthScreenedAt == null =>
        const HealthScreenScreen(),
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
    final goal = ref.watch(goalProvider);
    if (!goal.hasValue && ref.watch(todaySnapshotProvider).value != null) {
      return const HomeShell();
    }
    return switch (goal) {
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
