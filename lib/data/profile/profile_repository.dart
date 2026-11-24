import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/profile.dart';
import 'package:trendline/domain/units.dart';

abstract interface class ProfileRepository {
  /// The signed-in user's profile, or null before onboarding.
  Future<Profile?> fetch();

  /// Creates or replaces the signed-in user's profile.
  Future<Profile> save(Profile profile);
}

class SupabaseProfileRepository implements ProfileRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _columns =
      'sex, birth_year, height_cm, activity_level, weight_unit, '
      'use_lean_mass, disclaimer_accepted_at';

  @override
  Future<Profile?> fetch() async {
    final row = await _db.from('profiles').select(_columns).maybeSingle();
    return row == null ? null : profileFromRow(row);
  }

  @override
  Future<Profile> save(Profile profile) async {
    // user_id defaults to auth.uid() in the database; RLS enforces it.
    final row = await _db
        .from('profiles')
        .upsert(profileToRow(profile), onConflict: 'user_id')
        .select(_columns)
        .single();
    return profileFromRow(row);
  }
}

Profile profileFromRow(Map<String, dynamic> row) => Profile(
  sex: Sex.values.byName(row['sex'] as String),
  birthYear: row['birth_year'] as int,
  heightCm: readDouble(row['height_cm']),
  activityLevel: ActivityLevel.values.byName(row['activity_level'] as String),
  weightUnit: weightUnitFromDb(row['weight_unit'] as String),
  useLeanMass: row['use_lean_mass'] as bool? ?? false,
  disclaimerAcceptedAt: readDateTime(row['disclaimer_accepted_at']),
);

Map<String, dynamic> profileToRow(Profile p) => {
  'sex': p.sex.name,
  'birth_year': p.birthYear,
  'height_cm': p.heightCm,
  'activity_level': p.activityLevel.name,
  'weight_unit': weightUnitToDb(p.weightUnit),
  'use_lean_mass': p.useLeanMass,
  'disclaimer_accepted_at': writeTimestamp(p.disclaimerAcceptedAt),
};

WeightUnit weightUnitFromDb(String value) => switch (value) {
  'kg' => WeightUnit.kg,
  'lb' => WeightUnit.lb,
  'st_lb' => WeightUnit.stLb,
  _ => throw FormatException('Unknown weight unit: $value'),
};

String weightUnitToDb(WeightUnit unit) => switch (unit) {
  WeightUnit.kg => 'kg',
  WeightUnit.lb => 'lb',
  WeightUnit.stLb => 'st_lb',
};
