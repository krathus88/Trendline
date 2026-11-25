import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/food.dart';
import 'package:trendline/domain/sharing.dart';
import 'package:trendline/domain/weigh_in.dart';

/// A sharing action the database refused, with a message for the user.
class SharingError implements Exception {
  const new(this.message);

  final String message;

  static const ownCode = SharingError('That’s your own code.');
  static const badInvite = SharingError(
    'That code doesn’t work. It may have been used or expired: ask for a '
    'new one.',
  );
}

abstract interface class SharingRepository {
  /// Shares both ways (the user is the owner or the viewer).
  Future<List<Share>> fetchShares();

  /// The user's own invites that haven't expired.
  Future<List<ShareInvite>> fetchInvites();

  Future<ShareInvite> createInvite({
    required String ownerName,
    required Set<ShareKind> kinds,
  });

  Future<void> withdrawInvite(String code);

  /// Accepts an invite code (normalised). Throws [SharingError].
  Future<void> accept({required String code, required String viewerName});

  /// What an outgoing share includes (owner only).
  Future<void> setKinds(String shareId, Set<ShareKind> kinds);

  /// Ends a share, from either side.
  Future<void> end(String shareId);

  /// Publishes the user's current targets for viewers.
  Future<void> publishTargets(SharedTargets targets);

  /// What a viewer can see of [ownerId]. Empty (or null) when the share
  /// doesn't include it.
  Future<List<WeighIn>> weighInsOf(String ownerId, DateTime since);
  Future<SharedTargets?> targetsOf(String ownerId);
  Future<List<SharedPlanItem>> planOf(String ownerId, DateTime weekStart);
}

class SupabaseSharingRepository implements SharingRepository {
  const new(this._db);

  final SupabaseClient _db;

  static const _shareColumns =
      'id, user_id, viewer_id, owner_name, viewer_name, share_weight, '
      'share_targets, share_plans';

  @override
  Future<List<Share>> fetchShares() async {
    final rows = await _db
        .from('shares')
        .select(_shareColumns)
        .order('created_at');
    return rows.map(shareFromRow).toList();
  }

  @override
  Future<List<ShareInvite>> fetchInvites() async {
    final rows = await _db
        .from('share_invites')
        .select(
          'code, owner_name, share_weight, share_targets, share_plans, '
          'expires_at',
        )
        .gt('expires_at', writeTimestamp(DateTime.now()))
        .order('expires_at');
    return rows.map(shareInviteFromRow).toList();
  }

  @override
  Future<ShareInvite> createInvite({
    required String ownerName,
    required Set<ShareKind> kinds,
  }) async {
    // The code, owner and expiry come from the database.
    final row = await _db
        .from('share_invites')
        .insert({'owner_name': ownerName.trim(), ...kindsToRow(kinds)})
        .select(
          'code, owner_name, share_weight, share_targets, share_plans, '
          'expires_at',
        )
        .single();
    return shareInviteFromRow(row);
  }

  @override
  Future<void> withdrawInvite(String code) async {
    await _db.from('share_invites').delete().eq('code', code);
  }

  @override
  Future<void> accept({
    required String code,
    required String viewerName,
  }) async {
    try {
      await _db.rpc<String>(
        'accept_share',
        params: {'code': code, 'viewer_name': viewerName.trim()},
      );
    } on PostgrestException catch (e) {
      throw switch (e.code) {
        'TLS01' => SharingError.ownCode,
        'TLS02' => SharingError.badInvite,
        _ => e,
      };
    }
  }

  @override
  Future<void> setKinds(String shareId, Set<ShareKind> kinds) async {
    await _db.from('shares').update(kindsToRow(kinds)).eq('id', shareId);
  }

  @override
  Future<void> end(String shareId) async {
    await _db.from('shares').delete().eq('id', shareId);
  }

  @override
  Future<void> publishTargets(SharedTargets t) async {
    await _db.from('shared_targets').upsert({
      'kcal': t.kcal,
      'protein_g': t.proteinG,
      'carbs_g': t.carbsG,
      'fat_g': t.fatG,
      'fibre_g': t.fibreG,
    }, onConflict: 'user_id');
  }

  @override
  Future<List<WeighIn>> weighInsOf(String ownerId, DateTime since) async {
    final rows = await _db.rpc<List<dynamic>>(
      'shared_weigh_ins',
      params: {'owner': ownerId, 'since': writeDate(since)},
    );
    return [
      for (final (i, r) in rows.indexed)
        WeighIn(
          id: 'shared-$i',
          measuredAt: readDateTime((r as Map<String, dynamic>)['measured_at']),
          weightKg: readDouble(r['weight_kg']),
        ),
    ];
  }

  @override
  Future<SharedTargets?> targetsOf(String ownerId) async {
    final rows = await _db.rpc<List<dynamic>>(
      'shared_targets_of',
      params: {'owner': ownerId},
    );
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return SharedTargets(
      kcal: readDouble(r['kcal']),
      proteinG: readDouble(r['protein_g']),
      carbsG: readDouble(r['carbs_g']),
      fatG: readDouble(r['fat_g']),
      fibreG: readDouble(r['fibre_g']),
      updatedAt: readDateTime(r['updated_at']),
    );
  }

  @override
  Future<List<SharedPlanItem>> planOf(
    String ownerId,
    DateTime weekStart,
  ) async {
    final rows = await _db.rpc<List<dynamic>>(
      'shared_plan_items',
      params: {'owner': ownerId, 'week_start': writeDate(weekStart)},
    );
    return [
      for (final r in rows) sharedPlanItemFromRow(r as Map<String, dynamic>),
    ];
  }
}

Map<String, bool> kindsToRow(Set<ShareKind> kinds) => {
  'share_weight': kinds.contains(ShareKind.weight),
  'share_targets': kinds.contains(ShareKind.targets),
  'share_plans': kinds.contains(ShareKind.plans),
};

Set<ShareKind> kindsFromRow(Map<String, dynamic> row) => {
  if (row['share_weight'] == true) ShareKind.weight,
  if (row['share_targets'] == true) ShareKind.targets,
  if (row['share_plans'] == true) ShareKind.plans,
};

Share shareFromRow(Map<String, dynamic> row) => Share(
  id: row['id'] as String,
  ownerId: row['user_id'] as String,
  viewerId: row['viewer_id'] as String,
  ownerName: row['owner_name'] as String,
  viewerName: row['viewer_name'] as String,
  kinds: kindsFromRow(row),
);

ShareInvite shareInviteFromRow(Map<String, dynamic> row) => ShareInvite(
  code: row['code'] as String,
  ownerName: row['owner_name'] as String,
  kinds: kindsFromRow(row),
  expiresAt: readDateTime(row['expires_at']),
);

SharedPlanItem sharedPlanItemFromRow(Map<String, dynamic> row) =>
    SharedPlanItem(
      day: readDate(row['day']),
      slot: MealSlot.values.byName(row['slot'] as String),
      name: row['name'] as String,
      amount: readDouble(row['amount']),
      isRecipe: row['is_recipe'] as bool,
      kcal: readDoubleOrNull(row['kcal']) ?? 0,
      proteinG: readDoubleOrNull(row['protein_g']) ?? 0,
    );
