import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/domain/household.dart';

/// A household action the database refused, with a message for the user.
class HouseholdError implements Exception {
  const new(this.message);

  final String message;

  static const alreadyMember = HouseholdError(
    'You’re already in a household. Leave it first.',
  );
  static const badInvite = HouseholdError(
    'That code doesn’t work. It may have been used or expired: ask for a '
    'new one.',
  );
  static const full = HouseholdError(
    'That household is full (${Household.maxMembers} people).',
  );
}

abstract interface class HouseholdRepository {
  /// The user's household, or null if they aren't in one.
  Future<Household?> fetch();

  /// Creates a household with the user as its owner. Returns its ID.
  Future<String> create({required String name, required String displayName});

  /// Joins with an invite [code] (normalised). Returns the household's ID.
  Future<String> join({required String code, required String displayName});

  /// Makes a new single-use invite code (owner only).
  Future<HouseholdInvite> createInvite(String householdId);

  Future<void> withdrawInvite(String code);

  /// Removes [userId] from the household: the user themself (leaving) or,
  /// for the owner, someone else.
  Future<void> removeMember(String userId);
}

class SupabaseHouseholdRepository implements HouseholdRepository {
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<Household?> fetch() async {
    // RLS shows only the user's own household.
    final row = await _db
        .from('households')
        .select(
          'id, name, '
          'household_members(user_id, display_name, role, joined_at), '
          'household_invites(code, expires_at)',
        )
        .maybeSingle();
    return row == null ? null : householdFromRow(row, now: DateTime.now());
  }

  @override
  Future<String> create({required String name, required String displayName}) =>
      _call('create_household', {
        'name': name.trim(),
        'display_name': displayName.trim(),
      });

  @override
  Future<String> join({required String code, required String displayName}) =>
      _call('join_household', {
        'code': code,
        'display_name': displayName.trim(),
      });

  Future<String> _call(String fn, Map<String, dynamic> params) async {
    try {
      return await _db.rpc<String>(fn, params: params);
    } on PostgrestException catch (e) {
      throw switch (e.code) {
        'TLH01' => HouseholdError.alreadyMember,
        'TLH02' => HouseholdError.badInvite,
        'TLH03' => HouseholdError.full,
        _ => e,
      };
    }
  }

  @override
  Future<HouseholdInvite> createInvite(String householdId) async {
    // The code, inviter and expiry come from the database.
    final row = await _db
        .from('household_invites')
        .insert({'household_id': householdId})
        .select('code, expires_at')
        .single();
    return _inviteFromRow(row);
  }

  @override
  Future<void> withdrawInvite(String code) async {
    await _db.from('household_invites').delete().eq('code', code);
  }

  @override
  Future<void> removeMember(String userId) async {
    await _db.from('household_members').delete().eq('user_id', userId);
  }
}

Household householdFromRow(Map<String, dynamic> row, {required DateTime now}) {
  final members = [
    for (final m in (row['household_members'] as List? ?? const []))
      m as Map<String, dynamic>,
  ];
  final list =
      [
        for (final m in members)
          HouseholdMember(
            userId: m['user_id'] as String,
            displayName: m['display_name'] as String,
            isOwner: m['role'] == 'owner',
            joinedAt: DateTime.parse(m['joined_at'] as String),
          ),
      ]..sort((a, b) {
        if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
        return a.joinedAt.compareTo(b.joinedAt);
      });
  final invites =
      [
          for (final i in (row['household_invites'] as List? ?? const []))
            _inviteFromRow(i as Map<String, dynamic>),
        ].where((i) => i.expiresAt.isAfter(now)).toList()
        ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  return Household(
    id: row['id'] as String,
    name: row['name'] as String,
    members: list,
    invites: invites,
  );
}

HouseholdInvite _inviteFromRow(Map<String, dynamic> row) => HouseholdInvite(
  code: row['code'] as String,
  expiresAt: DateTime.parse(row['expires_at'] as String),
);
