import 'package:meta/meta.dart';

/// A small group that shares recipes (and, later, plans and prep). A user
/// is in at most one.
@immutable
class Household {
  const new({
    required this.id,
    required this.name,
    required this.members,
    this.invites = const [],
  });

  static const int maxMembers = 6;
  static const int maxNameLength = 60;
  static const int maxDisplayNameLength = 40;

  final String id;
  final String name;

  /// Owner first, then by when they joined.
  final List<HouseholdMember> members;

  /// Codes not yet used or expired.
  final List<HouseholdInvite> invites;

  HouseholdMember? memberFor(String userId) {
    for (final m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  bool isOwner(String userId) => memberFor(userId)?.isOwner ?? false;

  bool get isFull => members.length >= maxMembers;
}

@immutable
class HouseholdMember {
  const new({
    required this.userId,
    required this.displayName,
    required this.isOwner,
    required this.joinedAt,
  });

  final String userId;

  /// The name the member chose to show the others.
  final String displayName;
  final bool isOwner;
  final DateTime joinedAt;
}

/// A single-use code someone joins with.
@immutable
class HouseholdInvite {
  const new({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

/// Why a household name or display name can't be used, or null if it can.
String? validateHouseholdName(String name, {required String label}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Enter $label.';
  if (trimmed.length > Household.maxNameLength) {
    return 'Keep $label to ${Household.maxNameLength} characters.';
  }
  return null;
}

String? validateDisplayName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Enter the name the others will see.';
  if (trimmed.length > Household.maxDisplayNameLength) {
    return 'Keep your name to ${Household.maxDisplayNameLength} characters.';
  }
  return null;
}

/// An invite code as typed: spaces and dashes dropped, upper case. Null if
/// it can't be a code (10 letters and digits, no 0, O, 1 or I).
String? normaliseInviteCode(String input) {
  final code = input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return RegExp(r'^[A-HJ-NP-Z2-9]{10}$').hasMatch(code) ? code : null;
}

/// An invite code shown in two groups of five, easier to read out.
String formatInviteCode(String code) =>
    code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;
