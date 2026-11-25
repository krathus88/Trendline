// Long list items are split over lines as adjacent strings on purpose.
// ignore_for_file: no_adjacent_strings_in_list

import 'package:meta/meta.dart';

/// The privacy policy, shown in the app and published as
/// `docs/PRIVACY.md` (a test checks the two match).
///
/// Bump [privacyPolicyVersion] and [privacyPolicyDate] whenever the
/// meaning changes: everyone is asked to agree again on their next start.
/// Fixing a typo doesn't need a new version.
const int privacyPolicyVersion = 1;

/// When this version took effect, as shown to the reader.
const String privacyPolicyDate = '25 November 2026';

/// Where people send privacy requests the app can't handle itself.
const String privacyContact =
    'https://github.com/krathus88/Trendline (or the person who invited you)';

/// The published account deletion page (`docs/DELETE_ACCOUNT.md`), linked
/// from the store listing and the policy for people who can't open the app.
const String accountDeletionUrl =
    'https://github.com/krathus88/Trendline/blob/main/docs/DELETE_ACCOUNT.md';

/// One section: a heading, then paragraphs and bullet lists.
@immutable
class PolicySection {
  const new(this.heading, this.blocks);

  final String heading;

  /// Each is a paragraph, or a bullet list.
  final List<PolicyBlock> blocks;
}

sealed class PolicyBlock {
  const new();
}

class Paragraph extends PolicyBlock {
  const new(this.text);

  final String text;
}

class Bullets extends PolicyBlock {
  const new(this.items);

  final List<String> items;
}

/// The short version shown on the consent screen.
const List<String> privacySummary = [
  'Your weight, body measurements and food log are health data. '
      'Trendline uses them only to work out your trend, targets and '
      'meal plans.',
  'Everything is stored with Supabase in London. No ads, no analytics, '
      'and nothing is ever sold.',
  'Nobody else sees your data unless you share it, and then only what '
      'you choose.',
  'You can export everything or delete your account at any time in '
      'Settings → Privacy and your data.',
];

const List<PolicySection> privacyPolicy = [
  PolicySection('Who we are', [
    Paragraph(
      'Trendline is a personal weight-loss and meal-planning app, run by '
      'its developer for people they invite. The developer decides how '
      'your data is used, so is the data controller under UK GDPR. '
      'Contact: $privacyContact.',
    ),
  ]),
  PolicySection('What we collect', [
    Bullets([
      'Your account: the Discord user ID you sign in with, and what Discord '
          'passes on at sign-in (username, display name, email address and '
          'avatar link). Trendline never sees your Discord password.',
      'Your profile: sex, birth year, height, activity level, units and '
          'other settings.',
      'Health data: weigh-ins with body fat and lean mass if you add them, '
          'that you confirmed none of the health check’s conditions apply '
          '(which one applies is never asked), your goal, your food log, '
          'which '
          'days you marked complete, and the calorie estimates worked out '
          'from them.',
      'Food and planning: the foods and recipes you save, likes and '
          'dislikes, meal rules, your day schedule, meal plans and meal prep.',
      'Households and sharing: the names you choose to show, who you share '
          'with and what, and invite codes.',
      'A record of when you agreed to this policy.',
    ]),
    Paragraph(
      'We don’t collect your location, contacts, photos, device identifiers '
      'or any data about how you use the app.',
    ),
  ]),
  PolicySection('Health Connect', [
    Paragraph(
      'On Android you can let Trendline read weight, body fat and lean mass '
      'from Health Connect, including readings from before you connected. '
      'It never writes to Health Connect and reads nothing else.',
    ),
    Paragraph(
      'Readings from Health Connect are used only to show your weight trend '
      'and work out your targets, the same as weigh-ins you enter yourself. '
      'They are never used for advertising, never sold, and never passed '
      'to anyone else except as described in “Who can see it”. You can '
      'turn access off at any time in Health Connect.',
    ),
  ]),
  PolicySection('Why, and on what basis', [
    Paragraph(
      'We use your data only to run the app for you: your trend, targets, '
      'meal plans and prep, and the households and shares you set up. The '
      'lawful basis is providing the service you asked for (UK GDPR '
      'article 6(1)(b)). Because weight, body measurements and food intake '
      'are health data, we also need your explicit consent (article '
      '9(2)(a)), which the app asks for before you start.',
    ),
  ]),
  PolicySection('Where it’s kept', [
    Paragraph(
      'Your data is stored with Supabase, in their London data centre '
      '(AWS eu-west-2), and travels encrypted. Access is limited by rules '
      'in the database itself, so each account can reach only its own data '
      'and what others have shared with it.',
    ),
    Paragraph(
      'On your device, the app keeps your sign-in, and copies of today’s '
      'plan, your saved foods and recipes, your recent weigh-ins and the '
      'products you looked up by barcode, in encrypted storage, so it opens '
      'quickly and still shows them without signal. All of it is deleted '
      'when you sign out.',
    ),
  ]),
  PolicySection('Who can see it', [
    Bullets([
      'You.',
      'People in your household see the recipes, plans and prep you share '
          'with it, including your portion sizes, which hint at your calorie '
          'targets. Likes and dislikes are combined for planning without '
          'saying whose they are.',
      'People you share with see only what you switch on for them (your '
          'weight trend, daily targets or meal plans), and only until you '
          'stop.',
      'Supabase stores the data for us and can’t use it for anything '
          'else. Discord handles sign-in only and gets nothing from the app.',
      'Open Food Facts receives the barcodes you scan and the words you '
          'search for, to look up products. Nothing that identifies you is '
          'sent with them.',
    ]),
    Paragraph(
      'There are no ads, analytics or crash-reporting services in the app, '
      'and your data is never sold.',
    ),
  ]),
  PolicySection('How long we keep it', [
    Paragraph(
      'Until you delete it, or delete your account. Deleting your account '
      'removes everything at once, including your place on the invite '
      'list. Recipes you shared with a household stay with the household. '
      'Supabase keeps no backups of Trendline’s database, so no copy '
      'remains after deletion.',
    ),
  ]),
  PolicySection('Your rights', [
    Bullets([
      'See and copy your data: Settings → Privacy and your data → Export '
          'my data saves all of it as a JSON file, or your weigh-ins and '
          'food log as spreadsheets (CSV).',
      'Correct it: edit or delete anything in the app.',
      'Delete it: Settings → Privacy and your data → Delete my account. '
          'If you can’t open the app, see $accountDeletionUrl.',
      'Withdraw your consent: deleting your account does this. To stop '
          'Health Connect imports only, turn Trendline’s access off in '
          'Health Connect.',
      'Complain: you can contact the Information Commissioner’s Office '
          '(ico.org.uk) if you’re unhappy with how your data is handled.',
    ]),
  ]),
  PolicySection('Age', [
    Paragraph('Trendline is for adults (18 and over) only.'),
  ]),
  PolicySection('Not medical advice', [
    Paragraph(
      'Trendline gives estimates, not medical advice. Talk to your GP if '
      'you have a health condition.',
    ),
  ]),
  PolicySection('Changes', [
    Paragraph(
      'If this policy changes in a way that matters, the version number '
      'goes up and the app asks you to agree again before you carry on.',
    ),
  ]),
];

/// The account deletion page as Markdown, for `docs/DELETE_ACCOUNT.md`.
///
/// Google Play requires a web page, named after the app and its developer,
/// that shows how to ask for an account to be deleted, what is deleted,
/// what is kept and for how long. Keep it in step with
/// `delete_my_account()` and the policy's "How long we keep it".
/// Supabase's Free plan has no backups; moving to a paid plan adds daily
/// backups (Pro keeps 7 days), and this page and "How long we keep it"
/// must then say how long.
String accountDeletionMarkdown() => '''
# Delete your Trendline account

Trendline is a weight-loss and meal-planning app by its developer, Krathus88. This page explains how to delete your Trendline account and everything stored with it.

## In the app (immediate)

1. Open Trendline and sign in.
2. Go to **Settings → Privacy and your data**.
3. Optional: tap **Export my data** first if you want a copy.
4. Tap **Delete my account**, type DELETE and confirm.

Your account and data are deleted straight away, and the app signs you out.

## If you can't open the app

Send a deletion request to $privacyContact. Include your Discord username so we can find your account, and say that you want it deleted. We may ask you to confirm the request from that Discord account. We delete the account within 30 days of confirming it and reply when it's done.

## What is deleted

- Your account and sign-in details (Discord ID, username, display name, email address and avatar link) and your place on the invite list.
- Your profile, goals, weigh-ins (with body fat and lean mass), food log, completed days and calorie estimates.
- Your foods, recipes, likes and dislikes, meal rules, day schedule, meal plans and meal prep.
- Everything you share with others, and their access to it, and what others share with you.
- Your household membership and the record of when you agreed to the privacy policy.

## What is kept

- Foods and recipes you shared with a household stay with that household, which keeps using them. They don't include your health data. If you were its last member, the household and everything in it is deleted too.

Nothing else is kept. The database host (Supabase) keeps no backups on Trendline's plan, so no copy remains anywhere after deletion. For more, see the [privacy policy](PRIVACY.md).
''';

/// The policy as Markdown, for `docs/PRIVACY.md`.
String privacyPolicyMarkdown() {
  final out = StringBuffer()
    ..writeln('# Trendline privacy policy')
    ..writeln()
    ..writeln('Version $privacyPolicyVersion, $privacyPolicyDate.')
    ..writeln()
    ..writeln('In short:')
    ..writeln();
  for (final line in privacySummary) {
    out.writeln('- $line');
  }
  for (final section in privacyPolicy) {
    out
      ..writeln()
      ..writeln('## ${section.heading}');
    for (final block in section.blocks) {
      out.writeln();
      switch (block) {
        case Paragraph(:final text):
          out.writeln(text);
        case Bullets(:final items):
          for (final item in items) {
            out.writeln('- $item');
          }
      }
    }
  }
  return out.toString();
}
