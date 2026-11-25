import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:trendline/data/goals/targets_provider.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/sharing/sharing_repository.dart';
import 'package:trendline/domain/dates.dart';
import 'package:trendline/domain/household.dart';
import 'package:trendline/domain/sharing.dart';
import 'package:trendline/domain/weigh_in.dart';

/// The user's shares both ways and their open invites.
final sharingProvider = AsyncNotifierProvider<SharingNotifier, SharingState>(
  SharingNotifier.new,
);

class SharingNotifier extends AsyncNotifier<SharingState> {
  @override
  Future<SharingState> build() async {
    final me = ref.watch(currentUserIdProvider);
    if (me == null) return SharingState.empty;
    return await _load(me);
  }

  Future<SharingState> _load(String me) async {
    final repo = ref.read(sharingRepositoryProvider);
    final shares = await repo.fetchShares();
    final invites = await repo.fetchInvites();
    return SharingState(
      outgoing: [
        for (final s in shares)
          if (s.ownerId == me) s,
      ],
      incoming: [
        for (final s in shares)
          if (s.viewerId == me) s,
      ],
      invites: invites,
    );
  }

  Future<void> _reload() async {
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    state = AsyncData(await _load(me));
  }

  /// A new code sharing [kinds] (at least one).
  Future<ShareInvite> invite({
    required String ownerName,
    required Set<ShareKind> kinds,
  }) async {
    if (kinds.isEmpty) throw ArgumentError('Share at least one thing');
    final invite = await ref
        .read(sharingRepositoryProvider)
        .createInvite(ownerName: ownerName, kinds: kinds);
    await _reload();
    return invite;
  }

  Future<void> withdrawInvite(String code) async {
    await ref.read(sharingRepositoryProvider).withdrawInvite(code);
    await _reload();
  }

  /// Accepts a code as typed. Throws [SharingError] when it can't work.
  Future<void> accept({
    required String code,
    required String viewerName,
  }) async {
    final normalised = normaliseInviteCode(code);
    if (normalised == null) throw SharingError.badInvite;
    await ref
        .read(sharingRepositoryProvider)
        .accept(code: normalised, viewerName: viewerName);
    await _reload();
  }

  /// Switches one kind on or off for an outgoing share (all off keeps the
  /// viewer listed but shows them nothing). Shows the change at once and
  /// puts it back if the save fails.
  Future<void> setKind(Share share, ShareKind kind, {required bool on}) async {
    final kinds = {...share.kinds};
    on ? kinds.add(kind) : kinds.remove(kind);
    final before = state.value ?? SharingState.empty;
    state = AsyncData(
      SharingState(
        outgoing: [
          for (final s in before.outgoing)
            if (s.id == share.id) s.withKinds(kinds) else s,
        ],
        incoming: before.incoming,
        invites: before.invites,
      ),
    );
    try {
      await ref.read(sharingRepositoryProvider).setKinds(share.id, kinds);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Ends a share: the owner stops sharing, or the viewer stops viewing.
  Future<void> end(Share share) async {
    await ref.read(sharingRepositoryProvider).end(share.id);
    final before = state.value ?? SharingState.empty;
    state = AsyncData(
      SharingState(
        outgoing: [
          for (final s in before.outgoing)
            if (s.id != share.id) s,
        ],
        incoming: [
          for (final s in before.incoming)
            if (s.id != share.id) s,
        ],
        invites: before.invites,
      ),
    );
  }
}

/// Keeps the published targets current while a share includes them. The
/// database deletes them when no share does. Listened to by the home shell.
final targetsPublisherProvider = FutureProvider<SharedTargets?>((ref) async {
  final sharing = await ref.watch(sharingProvider.future);
  if (!sharing.sharesTargets) return null;
  final today = await ref.watch(targetsProvider.future);
  if (today == null) return null;
  final targets = SharedTargets.of(today.targets);
  if (!targets.isValid) return null;
  await ref.read(sharingRepositoryProvider).publishTargets(targets);
  return targets;
});

/// How far back a viewer's weight chart goes.
const sharedWeightDays = 90;

/// What the user can see of someone who shares with them.
final FutureProviderFamily<List<WeighIn>, String> viewedWeighInsProvider =
    FutureProvider.family<List<WeighIn>, String>(
      (ref, ownerId) => ref
          .watch(sharingRepositoryProvider)
          .weighInsOf(
            ownerId,
            addDays(dayOf(DateTime.now()), -(sharedWeightDays - 1)),
          ),
    );

final FutureProviderFamily<SharedTargets?, String> viewedTargetsProvider =
    FutureProvider.family<SharedTargets?, String>(
      (ref, ownerId) => ref.watch(sharingRepositoryProvider).targetsOf(ownerId),
    );

final FutureProviderFamily<List<SharedPlanItem>, (String, DateTime)>
viewedPlanProvider =
    FutureProvider.family<List<SharedPlanItem>, (String, DateTime)>(
      (ref, key) => ref.watch(sharingRepositoryProvider).planOf(key.$1, key.$2),
    );
