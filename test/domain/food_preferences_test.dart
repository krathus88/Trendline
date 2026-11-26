import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/households/household_repository.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe_library.dart';

const FoodKey _rice = (code: '11-001', name: 'Rice, white, raw');

void main() {
  group('one person’s preferences', () {
    test('weigh likes up, dislikes down and leave out nevers', () {
      const prefs = FoodPreferences(
        ingredients: {_rice: Preference.never},
        cuisines: {Cuisine.italian: Preference.like},
      );
      expect(prefs.isNever(_rice), isTrue);
      expect(prefs.ingredientWeight(_rice), 0);
      expect(prefs.cuisineWeight(Cuisine.italian), 3);
      expect(prefs.cuisineWeight(Cuisine.indian), 1, reason: 'no preference');
    });
  });

  group('a household’s combined preferences', () {
    FoodPreferences combined(List<HouseholdPreference> counts) =>
        FoodPreferences.combined(counts);

    test('anything someone never wants is left out for everyone', () {
      final prefs = combined([
        const HouseholdPreference(
          target: _rice,
          likes: 2,
          nevers: 1,
          members: 3,
        ),
        const HouseholdPreference(
          target: Cuisine.mexican,
          nevers: 1,
          members: 3,
        ),
      ]);
      expect(prefs.isNever(_rice), isTrue);
      expect(prefs.ingredientWeight(_rice), 0);
      expect(prefs.cuisineWeight(Cuisine.mexican), 0);
      expect(prefs.cuisines[Cuisine.mexican], Preference.never);
    });

    test('each member counts equally, so a like and a dislike nearly '
        'cancel out', () {
      final prefs = combined([
        const HouseholdPreference(
          target: Cuisine.italian,
          likes: 1,
          dislikes: 1,
          members: 2,
        ),
      ]);
      // sqrt(3 × 0.25)
      expect(prefs.cuisineWeight(Cuisine.italian), closeTo(0.866, 1e-3));
    });

    test('one member’s like counts for less in a bigger household', () {
      double likedBy(int members) => combined([
        HouseholdPreference(target: _rice, likes: 1, members: members),
      ]).ingredientWeight(_rice);
      expect(likedBy(1), closeTo(3, 1e-9));
      expect(likedBy(2), closeTo(1.732, 1e-3));
      expect(likedBy(4), lessThan(likedBy(2)));
      expect(likedBy(4), greaterThan(1));
    });

    test('everyone liking something weighs it as one person liking it', () {
      expect(
        combined([
          const HouseholdPreference(target: _rice, likes: 3, members: 3),
        ]).ingredientWeight(_rice),
        closeTo(3, 1e-9),
      );
    });

    test('foods nobody has a preference about stay neutral', () {
      expect(combined(const []).ingredientWeight(_rice), 1);
    });
  });

  test('the database’s combined rows are read without who', () {
    final prefs = householdPreferencesFromRows([
      {
        'cuisine': 'italian',
        'cofid_code': null,
        'cofid_name': null,
        'likes': 2,
        'dislikes': 0,
        'nevers': 0,
        'members': 2,
      },
      {
        'cuisine': null,
        'cofid_code': _rice.code,
        'cofid_name': _rice.name,
        'likes': 0,
        'dislikes': 0,
        'nevers': 1,
        'members': 2,
      },
      // An unknown cuisine (from a newer app) is skipped.
      {'cuisine': 'martian', 'likes': 1, 'members': 2},
    ]);
    expect(prefs.cuisineWeight(Cuisine.italian), closeTo(3, 1e-9));
    expect(prefs.isNever(_rice), isTrue);
    expect(prefs.cuisineWeights, hasLength(1));
  });

  test('the database’s combined stars are read as shares, without who', () {
    expect(
      householdFavouritesFromRows([
        {'recipe_id': 'r1', 'stars': 1, 'members': 2},
        {'recipe_id': 'r2', 'stars': 3, 'members': 3},
        // Malformed or impossible rows are skipped or capped.
        {'recipe_id': 'r3', 'stars': 1, 'members': 0},
        {'recipe_id': 'r4', 'stars': '1', 'members': 2},
        {'recipe_id': 'r5', 'stars': 4, 'members': 2},
        {'stars': 1, 'members': 2},
      ]),
      {'r1': 0.5, 'r2': 1.0, 'r5': 1.0},
    );
  });
}
