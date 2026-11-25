// Writes docs/PRIVACY.md from the privacy policy in the app, so the
// published copy (linked from the store listing) always matches.
//
// Run after changing lib/domain/privacy_policy.dart:
//   dart run tool/write_privacy_policy.dart
import 'dart:io';

import 'package:trendline/domain/privacy_policy.dart';

void main() {
  File('docs/PRIVACY.md').writeAsStringSync(privacyPolicyMarkdown());
  stdout.writeln('Wrote docs/PRIVACY.md');
}
