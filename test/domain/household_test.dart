import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/household.dart';

void main() {
  group('invite codes', () {
    test('are read in any case, with spaces or a dash', () {
      expect(normaliseInviteCode('abcde-23456'), 'ABCDE23456');
      expect(normaliseInviteCode(' ABCDE 23456 '), 'ABCDE23456');
    });

    test('must be 10 characters of the code alphabet', () {
      expect(normaliseInviteCode('ABCDE2345'), isNull, reason: 'too short');
      expect(normaliseInviteCode('ABCDE234567'), isNull, reason: 'too long');
      expect(normaliseInviteCode('ABCDE2345O'), isNull, reason: 'no O');
      expect(normaliseInviteCode('ABCDE23450'), isNull, reason: 'no 0');
      expect(normaliseInviteCode('ABCDE2345I'), isNull, reason: 'no I');
      expect(normaliseInviteCode('ABCDE23451'), isNull, reason: 'no 1');
      expect(normaliseInviteCode(''), isNull);
    });

    test('are shown in two groups of five', () {
      expect(formatInviteCode('ABCDE23456'), 'ABCDE-23456');
      expect(formatInviteCode('ABC'), 'ABC');
    });
  });

  group('names', () {
    test('a household needs a name of up to 60 characters', () {
      expect(validateHouseholdName('  ', label: 'a name'), isNotNull);
      expect(validateHouseholdName('Flat 2', label: 'a name'), isNull);
      expect(validateHouseholdName('x' * 60, label: 'a name'), isNull);
      expect(validateHouseholdName('x' * 61, label: 'a name'), isNotNull);
    });

    test('a display name is 1 to 40 characters, trimmed', () {
      expect(validateDisplayName(' '), isNotNull);
      expect(validateDisplayName('  Sam  '), isNull);
      expect(validateDisplayName('x' * 40), isNull);
      expect(validateDisplayName('x' * 41), isNotNull);
    });
  });

  test('knows its owner and when it is full', () {
    HouseholdMember member(String id, {bool owner = false}) => HouseholdMember(
      userId: id,
      displayName: id,
      isOwner: owner,
      joinedAt: DateTime(2026),
    );
    final h = Household(
      id: 'h',
      name: 'Home',
      members: [
        member('a', owner: true),
        for (final id in ['b', 'c', 'd', 'e']) member(id),
      ],
    );
    expect(h.isOwner('a'), isTrue);
    expect(h.isOwner('b'), isFalse);
    expect(h.isOwner('stranger'), isFalse);
    expect(h.isFull, isFalse);
    expect(
      Household(
        id: 'h',
        name: 'Home',
        members: [...h.members, member('f')],
      ).isFull,
      isTrue,
    );
  });
}
