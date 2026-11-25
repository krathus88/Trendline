import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trendline/app.dart';
import 'package:trendline/data/providers.dart';
import 'package:trendline/data/supabase/secure_session_storage.dart';
import 'package:trendline/data/supabase/supabase_config.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Opened from Health Connect's permission screen: show the privacy policy
  // only, without signing in.
  if (binding.platformDispatcher.defaultRouteName == privacyPolicyRoute) {
    runApp(const TrendlineApp.privacyPolicy());
    return;
  }

  final config = SupabaseConfig.fromEnvironment();
  if (config == null) {
    runApp(const TrendlineApp.missingConfig());
    return;
  }

  const storage = FlutterSecureStorage();
  final supabase = await Supabase.initialize(
    url: config.url,
    publishableKey: config.publishableKey,
    // Never log auth traffic: it can contain tokens.
    debug: false,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(storage),
      pkceAsyncStorage: SecurePkceStorage(storage),
    ),
  );

  runApp(
    ProviderScope(
      overrides: [supabaseClientProvider.overrideWithValue(supabase.client)],
      child: const TrendlineApp(),
    ),
  );
}
