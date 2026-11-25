import 'package:meta/meta.dart';

/// The user's agreement to a version of the privacy policy, which covers
/// the explicit consent health data needs.
@immutable
class Consent {
  const new({required this.policyVersion, required this.consentedAt});

  final int policyVersion;
  final DateTime consentedAt;

  /// Whether this agreement covers [currentVersion] of the policy.
  bool covers(int currentVersion) => policyVersion >= currentVersion;
}
