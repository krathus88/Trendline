import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/domain/consent.dart';
import 'package:trendline/domain/privacy_policy.dart';

void main() {
  test('docs/PRIVACY.md matches the policy in the app', () {
    final published = File(
      'docs/PRIVACY.md',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      published,
      privacyPolicyMarkdown(),
      reason: 'Run: dart run tool/write_privacy_policy.dart',
    );
  });

  test('the Markdown has the version, summary and every section', () {
    final md = privacyPolicyMarkdown();
    expect(md, contains('Version $privacyPolicyVersion, $privacyPolicyDate.'));
    for (final line in privacySummary) {
      expect(md, contains('- $line'));
    }
    for (final section in privacyPolicy) {
      expect(md, contains('## ${section.heading}'));
    }
  });

  test('the policy covers what Health Connect and the store require', () {
    final md = privacyPolicyMarkdown();
    // Health Connect: what is read, that nothing is written, limited use.
    expect(md, contains('weight, body fat and lean mass from Health Connect'));
    expect(md, contains('never writes to Health Connect'));
    expect(md, contains('never used for advertising'));
    // UK GDPR: basis for special category data, rights, regulator.
    expect(md, contains('9(2)(a)'));
    expect(md, contains('Delete my account'));
    expect(md, contains('Export my data'));
    expect(md, contains('ico.org.uk'));
  });

  test('docs/DELETE_ACCOUNT.md matches the page in the app', () {
    final published = File(
      'docs/DELETE_ACCOUNT.md',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      published,
      accountDeletionMarkdown(),
      reason: 'Run: dart run tool/write_privacy_policy.dart',
    );
  });

  test('the deletion page covers what Google Play requires', () {
    final md = accountDeletionMarkdown();
    // Names the app and developer, as on the store listing.
    expect(md, contains('Trendline'));
    expect(md, contains('Krathus88'));
    // Steps in the app, and a way to ask without it.
    expect(md, contains('Delete my account'));
    expect(md, contains(privacyContact));
    // What is deleted, what is kept and for how long.
    expect(md, contains('## What is deleted'));
    expect(md, contains('## What is kept'));
    expect(md, contains('keeps no backups'));
    // The policy points people who can't open the app to this page.
    expect(privacyPolicyMarkdown(), contains(accountDeletionUrl));
    expect(accountDeletionUrl, endsWith('docs/DELETE_ACCOUNT.md'));
  });

  test('a consent covers its own and earlier versions only', () {
    final consent = Consent(policyVersion: 2, consentedAt: DateTime(2026));
    expect(consent.covers(1), isTrue);
    expect(consent.covers(2), isTrue);
    expect(consent.covers(3), isFalse);
  });
}
