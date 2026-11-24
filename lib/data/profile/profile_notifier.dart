import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/domain/profile.dart';

/// The signed-in user's profile (null before onboarding), cached in memory.
final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile?>(
  ProfileNotifier.new,
);

class ProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    if (ref.watch(currentUserIdProvider) == null) return null;
    return await ref.watch(profileRepositoryProvider).fetch();
  }

  /// Records that none of the conditions needing medical supervision
  /// apply. Only the date is kept.
  Future<void> confirmHealthScreen() async {
    final profile = state.value;
    if (profile == null) return;
    await save(profile.copyWith(healthScreenedAt: DateTime.now()));
  }

  Future<void> save(Profile profile) async {
    final saved = await ref.read(profileRepositoryProvider).save(profile);
    state = AsyncData(saved);
  }
}
