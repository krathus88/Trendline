// Writes docs/PRIVACY.md and docs/DELETE_ACCOUNT.md from the text in the
// app, so the published copies (linked from the store listing) always match.
//
// Run after changing lib/domain/privacy_policy.dart:
//   dart run tool/write_privacy_policy.dart
import 'dart:io';

import 'package:trendline/domain/privacy_policy.dart';

void main() {
  File('docs/PRIVACY.md').writeAsStringSync(privacyPolicyMarkdown());
  File('docs/DELETE_ACCOUNT.md').writeAsStringSync(accountDeletionMarkdown());
  stdout.writeln('Wrote docs/PRIVACY.md and docs/DELETE_ACCOUNT.md');
}
