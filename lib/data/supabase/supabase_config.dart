/// Supabase connection settings, supplied at build time with
/// `--dart-define-from-file=dart_defines.json` (git-ignored; see
/// `dart_defines.example.json`). Only the publishable key belongs here:
/// never the secret / service_role key.
class SupabaseConfig {
  const new({required this.url, required this.publishableKey});

  final String url;
  final String publishableKey;

  /// Where Supabase sends the browser back to after Discord sign-in. Must be
  /// listed under Auth > URL Configuration > Redirect URLs in the dashboard,
  /// and match the intent filter in `android/app/src/main/AndroidManifest.xml`.
  static const String authRedirectUrl =
      'com.krathus.trendline://login-callback';

  /// Reads the build-time settings, or returns null if they're missing.
  static SupabaseConfig? fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    if (url.isEmpty || key.isEmpty) return null;
    return const SupabaseConfig(url: url, publishableKey: key);
  }
}
