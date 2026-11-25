import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/data/account/consent_notifier.dart';
import 'package:trendline/data/snapshots/today_snapshot_notifier.dart';
import 'package:trendline/domain/privacy_policy.dart';
import 'package:trendline/ui/common/feedback.dart';
import 'package:trendline/ui/home/profile_gate.dart';
import 'package:trendline/ui/privacy/consent_screen.dart';

/// Asks for consent to the current privacy policy before anything else.
///
/// While the consent loads (or can't, without signal), a user with a Today
/// snapshot agreed before it was made, so the app opens on it straight
/// away; the check happens again once the consent loads.
class ConsentGate extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(consentProvider);
    if (!consent.hasValue && ref.watch(todaySnapshotProvider).value != null) {
      return const ProfileGate();
    }
    return switch (consent) {
      AsyncData(:final value)
          when value?.covers(privacyPolicyVersion) ?? false =>
        const ProfileGate(),
      AsyncData(:final value) => ConsentScreen(updated: value != null),
      AsyncError(:final error) => Scaffold(
        body: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(consentProvider),
        ),
      ),
      _ => const Scaffold(body: CenteredProgress()),
    };
  }
}
