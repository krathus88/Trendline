import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/consent.dart';
import 'package:trendline/domain/privacy_policy.dart';

/// The signed-in user's latest agreement to the privacy policy, or null.
final consentProvider = AsyncNotifierProvider<ConsentNotifier, Consent?>(
  ConsentNotifier.new,
);

class ConsentNotifier extends AsyncNotifier<Consent?> {
  @override
  Future<Consent?> build() async {
    if (ref.watch(currentUserIdProvider) == null) return null;
    return await ref.read(accountRepositoryProvider).fetchConsent();
  }

  /// Records agreement to the current policy.
  Future<void> agree() async {
    final consent = await ref
        .read(accountRepositoryProvider)
        .recordConsent(privacyPolicyVersion);
    state = AsyncData(consent);
  }
}
