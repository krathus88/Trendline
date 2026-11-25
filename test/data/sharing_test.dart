import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/sharing/sharing_notifier.dart';
import 'package:trendline/data/sharing/sharing_repository.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/sharing.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

void main() {
  group('share rows', () {
    test('kinds round-trip', () {
      final row = kindsToRow({ShareKind.weight, ShareKind.plans});
      expect(row, {
        'share_weight': true,
        'share_targets': false,
        'share_plans': true,
      });
      expect(kindsFromRow(row), {ShareKind.weight, ShareKind.plans});
    });

    test('a share says who owns and who views it', () {
      final s = shareFromRow({
        'id': 's1',
        'user_id': 'a',
        'viewer_id': 'b',
        'owner_name': 'Alex',
        'viewer_name': 'Bea',
        'share_weight': false,
        'share_targets': true,
        'share_plans': false,
      });
      expect(
        (s.ownerId, s.viewerId, s.ownerName, s.viewerName),
        ('a', 'b', 'Alex', 'Bea'),
      );
      expect(s.kinds, {ShareKind.targets});
    });

    test('a plan item reads numbers given as strings', () {
      final i = sharedPlanItemFromRow({
        'day': '2026-12-07',
        'slot': 'lunch',
        'name': 'Rice pot',
        'amount': '1.50',
        'is_recipe': true,
        'kcal': '525.0',
        'protein_g': null,
      });
      expect(i.day, DateTime(2026, 12, 7));
      expect(i.slot, MealSlot.lunch);
      expect(i.amount, 1.5);
      expect(i.kcal, 525);
      expect(i.proteinG, 0);
    });
  });

  group('SharedTargets', () {
    test('only numbers in the database ranges are published', () {
      const ok = SharedTargets(
        kcal: 2100,
        proteinG: 160,
        carbsG: 220,
        fatG: 70,
        fibreG: 30,
      );
      expect(ok.isValid, isTrue);
      expect(
        const SharedTargets(
          kcal: 700,
          proteinG: 60,
          carbsG: 50,
          fatG: 20,
          fibreG: 30,
        ).isValid,
        isFalse,
      );
      expect(
        const SharedTargets(
          kcal: 6500,
          proteinG: 160,
          carbsG: 220,
          fatG: 70,
          fibreG: 30,
        ).isValid,
        isFalse,
      );
    });
  });

  group('SharingNotifier', () {
    late FakeAuthRepository auth;
    late FakeSharingRepository sharing;
    late ProviderContainer container;

    setUp(() async {
      auth = FakeAuthRepository(initial: const SignedIn('user-1'));
      sharing = FakeSharingRepository();
      container = ProviderContainer.test(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          sharingRepositoryProvider.overrideWithValue(sharing),
        ],
      )..listen(authStatusProvider, (_, _) {});
      await container.read(authStatusProvider.future);
      container.listen(sharingProvider, (_, _) {});
    });

    tearDown(() => auth.dispose());

    test('splits shares into outgoing and incoming', () async {
      sharing.shares.addAll(const [
        Share(
          id: 'out',
          ownerId: 'user-1',
          viewerId: 'b',
          ownerName: 'Me',
          viewerName: 'Bea',
          kinds: {ShareKind.weight},
        ),
        Share(
          id: 'in',
          ownerId: 'c',
          viewerId: 'user-1',
          ownerName: 'Cat',
          viewerName: 'Me',
          kinds: {ShareKind.plans},
        ),
      ]);
      container.invalidate(sharingProvider);
      final state = await container.read(sharingProvider.future);
      expect(state.outgoing.map((s) => s.id), ['out']);
      expect(state.incoming.map((s) => s.id), ['in']);
      expect(state.sharesTargets, isFalse);
    });

    test('an invite must share something', () async {
      await container.read(sharingProvider.future);
      expect(
        () => container
            .read(sharingProvider.notifier)
            .invite(ownerName: 'Me', kinds: {}),
        throwsArgumentError,
      );
      await container
          .read(sharingProvider.notifier)
          .invite(ownerName: 'Me', kinds: {ShareKind.weight});
      expect(container.read(sharingProvider).value!.invites, hasLength(1));
    });

    test('accepting checks the code before asking', () async {
      await container.read(sharingProvider.future);
      await expectLater(
        container
            .read(sharingProvider.notifier)
            .accept(code: 'short', viewerName: 'Me'),
        throwsA(SharingError.badInvite),
      );
      sharing.validCodes['QRSTU23456'] = {ShareKind.weight};
      await container
          .read(sharingProvider.notifier)
          .accept(code: 'qrstu-23456', viewerName: 'Me');
      expect(container.read(sharingProvider).value!.incoming, hasLength(1));
    });

    test('switching a kind shows at once; switching all off keeps the '
        'viewer', () async {
      sharing.shares.add(
        const Share(
          id: 'out',
          ownerId: 'user-1',
          viewerId: 'b',
          ownerName: 'Me',
          viewerName: 'Bea',
          kinds: {ShareKind.weight},
        ),
      );
      container.invalidate(sharingProvider);
      final state = await container.read(sharingProvider.future);
      final n = container.read(sharingProvider.notifier);
      await n.setKind(state.outgoing.single, ShareKind.targets, on: true);
      expect(container.read(sharingProvider).value!.sharesTargets, isTrue);
      expect(sharing.shares.single.kinds, {
        ShareKind.weight,
        ShareKind.targets,
      });

      final now = container.read(sharingProvider).value!.outgoing.single;
      await n.setKind(now, ShareKind.weight, on: false);
      await n.setKind(
        container.read(sharingProvider).value!.outgoing.single,
        ShareKind.targets,
        on: false,
      );
      expect(sharing.shares.single.kinds, isEmpty);
    });

    test('a viewer sees only what is shared', () async {
      sharing
        ..shares.add(
          const Share(
            id: 'in',
            ownerId: 'c',
            viewerId: 'user-1',
            ownerName: 'Cat',
            viewerName: 'Me',
            kinds: {ShareKind.targets},
          ),
        )
        ..targets['c'] = const SharedTargets(
          kcal: 1800,
          proteinG: 120,
          carbsG: 200,
          fatG: 60,
          fibreG: 30,
        )
        ..plans['c'] = [
          SharedPlanItem(
            day: DateTime(2026, 12, 7),
            slot: MealSlot.lunch,
            name: 'Soup',
            amount: 1,
            isRecipe: true,
            kcal: 400,
            proteinG: 20,
          ),
        ];
      expect(
        (await container.read(viewedTargetsProvider('c').future))?.kcal,
        1800,
      );
      expect(
        await container.read(
          viewedPlanProvider(('c', DateTime(2026, 12, 7))).future,
        ),
        isEmpty,
        reason: 'plans aren’t shared',
      );
    });
  });
}
