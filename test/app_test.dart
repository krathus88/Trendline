import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trendline/app.dart';
import 'package:trendline/data/supabase/supabase_config.dart';
import 'package:trendline/ui/setup/missing_config_screen.dart';

void main() {
  testWidgets('without Supabase settings, explains how to configure', (
    tester,
  ) async {
    await tester.pumpWidget(const TrendlineApp.missingConfig());

    expect(find.byType(MissingConfigScreen), findsOneWidget);
    expect(find.text('Supabase is not configured'), findsOneWidget);
  });

  test('config is absent when no dart-defines are given', () {
    // Tests run without --dart-define-from-file.
    expect(SupabaseConfig.fromEnvironment(), isNull);
  });

  test('redirect URL matches the Android intent filter scheme', () {
    expect(
      SupabaseConfig.authRedirectUrl,
      'com.krathus.trendline://login-callback',
    );
  });

  test('redirect URL matches the scheme the Windows app registers', () {
    final header = File('windows/runner/url_scheme.h').readAsStringSync();
    final scheme = RegExp(r'kUrlScheme\[\] = L"([^"]+)"')
        .firstMatch(header)
        ?.group(1);
    expect(scheme, Uri.parse(SupabaseConfig.authRedirectUrl).scheme);
  });
}
