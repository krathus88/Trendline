import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/data/preferences/food_preferences_repository.dart';
import 'package:trendline/domain/food_preferences.dart';
import 'package:trendline/domain/recipe_library.dart';

void main() {
  test('preference rows become preferences; unknown values are skipped', () {
    final prefs = foodPreferencesFromRows([
      {'cuisine': 'indian', 'preference': 'like'},
      {
        'cofid_code': '13-888',
        'cofid_name': 'Coriander leaves, fresh',
        'preference': 'never',
      },
      {'cuisine': 'martian', 'preference': 'like'},
      {'cuisine': 'italian', 'preference': 'adore'},
    ]);
    expect(prefs.cuisines, {Cuisine.indian: Preference.like});
    expect(prefs.ingredients, {
      (code: '13-888', name: 'Coriander leaves, fresh'): Preference.never,
    });
  });

  test('preference weights', () {
    expect(preferenceWeight(Preference.like), 3);
    expect(preferenceWeight(null), 1);
    expect(preferenceWeight(Preference.dislike), 0.25);
    expect(preferenceWeight(Preference.never), 0);
  });
}
