import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/data/supabase/row_parsing.dart';
import 'package:trendline/domain/consent.dart';

/// The user's privacy choices and their account as a whole: consent to the
/// privacy policy, exporting everything, and deleting the account.
abstract interface class AccountRepository {
  /// The user's latest agreement to the privacy policy, or null.
  Future<Consent?> fetchConsent();

  /// Records agreement to [policyVersion]. The time is the server's.
  Future<Consent> recordConsent(int policyVersion);

  /// Everything stored about the user, one list of rows per table (see
  /// `export_my_data` in the database).
  Future<Map<String, Object?>> exportData();

  /// Deletes the account and all its data, for good. The caller signs out
  /// afterwards.
  Future<void> deleteAccount();
}

class SupabaseAccountRepository implements AccountRepository {
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<Consent?> fetchConsent() async {
    final row = await _db
        .from('consents')
        .select('policy_version, consented_at')
        .order('policy_version', ascending: false)
        .order('consented_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : consentFromRow(row);
  }

  @override
  Future<Consent> recordConsent(int policyVersion) async {
    final row = await _db
        .from('consents')
        .insert({'policy_version': policyVersion})
        .select('policy_version, consented_at')
        .single();
    return consentFromRow(row);
  }

  @override
  Future<Map<String, Object?>> exportData() async {
    final data = await _db.rpc<Map<String, dynamic>>('export_my_data');
    return data;
  }

  @override
  Future<void> deleteAccount() => _db.rpc<void>('delete_my_account');
}

Consent consentFromRow(Map<String, dynamic> row) => Consent(
  policyVersion: (row['policy_version'] as num).toInt(),
  consentedAt: readDateTime(row['consented_at']),
);
