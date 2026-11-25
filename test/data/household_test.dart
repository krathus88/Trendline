import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/auth/auth_repository.dart';
import 'package:trendline/data/households/household_notifier.dart';
import 'package:trendline/data/households/household_repository.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/recipes/recipe_repository.dart';
import 'package:trendline/data/recipes/recipes_notifier.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/nutrition.dart';
import 'package:trendline/domain/recipe.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fakes.dart';

void main() {
  group('household rows', () {
    test('owner first, then by joining; expired invites dropped', () {
      final h = householdFromRow({
        'id': 'h1',
        'name': 'Flat 2',
        'household_members': [
          {
            'user_id': 'b',
            'display_name': 'Bea',
            'role': 'member',
            'joined_at': '2026-11-20T10:00:00Z',
          },
          {
            'user_id': 'c',
            'display_name': 'Cat',
            'role': 'member',
            'joined_at': '2026-11-10T10:00:00Z',
          },
          {
            'user_id': 'a',
            'display_name': 'Alex',
            'role': 'owner',
            'joined_at': '2026-11-21T10:00:00Z',
          },
        ],
        'household_invites': [
          {'code': 'ABCDE23456', 'expires_at': '2026-11-26T10:00:00Z'},
          {'code': 'ZZZZZ23456', 'expires_at': '2026-11-24T10:00:00Z'},
        ],
      }, now: DateTime.utc(2026, 11, 25));

      expect(h.members.map((m) => m.displayName), ['Alex', 'Cat', 'Bea']);
      expect(h.isOwner('a'), isTrue);
      expect(h.invites.map((i) => i.code), ['ABCDE23456']);
    });
  });

  group('recipe rows', () {
    test('a shared recipe says which household', () {
      final r = recipeFromRow({
        'id': 'r1',
        'name': 'Dal',
        'portions': 4,
        'fridge_days': 3,
        'freezable': true,
        'household_id': 'h1',
        'recipe_ingredients': const <Object>[],
      });
      expect(r.householdId, 'h1');
      expect(r.isShared, isTrue);
    });

    test('sharing sends the household; a copy back sends none', () {
      const mine = Recipe(
        id: 'r1',
        name: 'Dal',
        ingredients: [RecipeIngredient(foodId: 'lentils', rawGrams: 200)],
      );
      final shared = saveRecipeParams(mine.copyFor('h1'));
      expect(shared['recipe_id'], isNull, reason: 'a new copy');
      expect(shared['household_id'], 'h1');
      expect(shared['ingredients'], [
        {'food_id': 'lentils', 'raw_grams': 200.0},
      ]);
      expect(
        saveRecipeParams(mine.copyFor('h1').copyFor(null))['household_id'],
        isNull,
      );
    });
  });

  group('HouseholdNotifier and shared recipes', () {
    late FakeAuthRepository auth;
    late FakeHouseholdRepository households;
    late FakeRecipeRepository recipes;
    late FakeFoodRepository foods;
    late ProviderContainer container;

    setUp(() async {
      auth = FakeAuthRepository(initial: const SignedIn('user-1'));
      households = FakeHouseholdRepository();
      recipes = FakeRecipeRepository();
      foods = FakeFoodRepository();
      container = ProviderContainer.test(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          householdRepositoryProvider.overrideWithValue(households),
          recipeRepositoryProvider.overrideWithValue(recipes),
          foodRepositoryProvider.overrideWithValue(foods),
        ],
      )..listen(authStatusProvider, (_, _) {});
      await container.read(authStatusProvider.future);
      container
        ..listen(householdProvider, (_, _) {})
        ..listen(recipesProvider, (_, _) {})
        ..listen(sharedRecipesProvider, (_, _) {})
        ..listen(foodsByIdProvider, (_, _) {});
    });

    tearDown(() => auth.dispose());

    const dal = Recipe(
      id: '',
      name: 'Dal',
      ingredients: [RecipeIngredient(foodId: 'f-lentils', rawGrams: 200)],
    );

    test('creating makes the user the owner', () async {
      expect(await container.read(householdProvider.future), isNull);
      await container
          .read(householdProvider.notifier)
          .create(name: 'Flat 2', displayName: 'Alex');
      final h = container.read(householdProvider).value!;
      expect(h.name, 'Flat 2');
      expect(h.isOwner('user-1'), isTrue);
    });

    test('a code that cannot be valid is refused before asking', () async {
      await container.read(householdProvider.future);
      await expectLater(
        container
            .read(householdProvider.notifier)
            .join(code: 'nope', displayName: 'Bea'),
        throwsA(HouseholdError.badInvite),
      );
    });

    test('joining reads the code as typed', () async {
      households.validCodes.add('ABCDE23456');
      await container.read(householdProvider.future);
      await container
          .read(householdProvider.notifier)
          .join(code: 'abcde-23456', displayName: 'Bea');
      expect(container.read(householdIdProvider), isNotNull);
    });

    test(
      'sharing copies a recipe; the own one stays; leaving drops access',
      () async {
        await container.read(householdProvider.future);
        await container
            .read(householdProvider.notifier)
            .create(name: 'Flat 2', displayName: 'Alex');
        final mine = await container.read(recipesProvider.notifier).save(dal);
        await container.read(sharedRecipesProvider.future);

        final shared = await container
            .read(sharedRecipesProvider.notifier)
            .share(mine);
        expect(shared.id, isNot(mine.id));
        expect(shared.householdId, container.read(householdIdProvider));
        expect(container.read(sharedRecipesProvider).value, [shared]);
        expect(container.read(recipesProvider).value!.map((r) => r.id), [
          mine.id,
        ]);

        await container.read(householdProvider.notifier).leave();
        expect(container.read(householdProvider).value, isNull);
        expect(await container.read(sharedRecipesProvider.future), isEmpty);
      },
    );

    test('copying a shared recipe makes an own one', () async {
      await container.read(householdProvider.future);
      await container
          .read(householdProvider.notifier)
          .create(name: 'Flat 2', displayName: 'Alex');
      final shared = await recipes.save(dal.copyFor('h0'));
      container.invalidate(sharedRecipesProvider);
      await container.read(sharedRecipesProvider.future);

      final copy = await container
          .read(sharedRecipesProvider.notifier)
          .copyToMine(shared);
      expect(copy.isShared, isFalse);
      expect(container.read(recipesProvider).value!.single.id, copy.id);
    });

    test('shared foods count for recipe nutrition', () async {
      await container.read(householdProvider.future);
      await container
          .read(householdProvider.notifier)
          .create(name: 'Flat 2', displayName: 'Alex');
      foods.shared.add(
        const Food(
          id: 'f-lentils',
          name: 'Lentils',
          per100g: Nutrition(kcal: 350, proteinG: 24, carbsG: 50, fatG: 1.5),
          source: FoodSource.manual,
        ),
      );
      container.invalidate(sharedFoodsProvider);
      await container.read(sharedFoodsProvider.future);
      expect(container.read(foodsByIdProvider)['f-lentils']?.name, 'Lentils');
    });
  });
}
